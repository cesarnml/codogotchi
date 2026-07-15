import Foundation

/// Pure fold: `derive(input:memory:) -> (DesiredWindows, PoolMemory)`.
///
/// P18.01 wires exactly `FloatingPetWindowPool.update()` Steps 1–5b plus the
/// eligibility-bounding block that follows Step 3b:
///
/// - Step 1: off-mode render-key filtering
/// - Step 2: the idle-frozen TTL clock, first-seen seeding, last-updated
///   tracking
/// - Step 3: the last-active election, restricted to eligible keys
/// - Step 3b: the sticky HUD-bearer election
/// - eligibility bounding: pruning the three clock maps to the eligibility
///   window
/// - `isTTLExpired`: the TTL-expiry-with-last-active-immunity predicate
///   (Steps 5a/5b's guard), exposed as a pure static function
///
/// Step mapping for the legacy `update()` pipeline (exit-condition evidence):
/// 1 `visibleEntries`; 2 clock/timer observation; 3/3b elections; 4 clock
/// bounding; 5a mode-derived membership; 5b TTL filtering; 6a/6a2/6b
/// `desiredWindowKey` plus previous-key diff; 6c cap selection, conflict target,
/// numbering and frame FIFO; 7 direct-window payload construction; 8 combined
/// winner/payload construction; 9 HUD projection. Every controller call from
/// Steps 7-9 is represented by `DesiredWindow` data; P18.04 only executes it.
///
/// P18.02 adds selection (Step 6c) and the collapse steps (6a/6a2/6b) —
/// though see this ticket's Rationale for why the collapse steps are not
/// transcribed as separate imperative branches: a pure fold that recomputes
/// desired membership from scratch every tick cannot exhibit the
/// stale-window bugs those steps exist to patch, so `derive` folds them into
/// one membership computation (`desiredWindowKey`) plus a diff against
/// `PoolMemory.previousDesiredWindowKeys` for the two things that genuinely
/// need "what changed since last tick" (grandfather-frame capture, and
/// knowing which keys are freshly spawning). Push-payload construction
/// (Steps 7/8's controller calls) remains P18.03; see `DesiredWindow`'s doc
/// comment for which fields are still placeholders.
///
/// No AppKit import anywhere in this file or elsewhere under `Pool/Derive/`
/// — enforced by `PoolDerivePurityGateTests`.
enum PoolDerive {
	static func derive(input: PoolTickInput, memory: PoolMemory) -> (DesiredWindows, PoolMemory) {
		var memory = memory
		let snapshot = input.snapshot
		let customization = input.customization
		let currentTime = input.currentTime
		let ttlSeconds: TimeInterval = customization.idleDismissTtlSeconds == 0
			? .infinity
			: TimeInterval(customization.idleDismissTtlSeconds)

		func mode(forWindowKey key: WindowKey) -> PlatformMode {
			customization.platformModes[key.origin] ?? .own
		}

		// Step 1: filter render keys whose owning origin's mode is off.
		let visibleEntries = snapshot.perPlatform.filter { mode(forWindowKey: $0.key) != .off }

		// Step 2: update tracking for each visible render key.
		for (renderKey, state) in visibleEntries {
			// TTL clock: advance only while the key is doing work. Seed on
			// first sight so a freshly-observed idle pet still gets a full
			// TTL grace window.
			if state.activityState != .idle || memory.lastSeenAt[renderKey] == nil {
				memory.lastSeenAt[renderKey] = currentTime
			}
			// First-seen clock: set once, never refreshed.
			if memory.firstSeenAt[renderKey] == nil {
				memory.firstSeenAt[renderKey] = currentTime
			}
			// Active-key election: track the snapshot's own updated_at.
			let stateDate = StateJsonReader.parseISO8601Date(state.updatedAt) ?? currentTime
			if memory.lastUpdatedAt[renderKey] == nil || stateDate > memory.lastUpdatedAt[renderKey]! {
				memory.lastUpdatedAt[renderKey] = stateDate
			}
			// Pool-owned prompt timer: observed every tick, BEFORE any
			// teardown/spawn decision below, so the timer keeps correct time
			// across hide/show, idle-TTL dismiss, and session-cap de-render —
			// mirrors `FloatingPetWindowPool`'s "observe before guards"
			// ordering. Later in this tick `derive` emits
			// `DesiredWindow.promptTimerStatus` from these trackers.
			memory.promptTimers[renderKey, default: PromptTimerTracker()].observe(
				state: state.activityState,
				updatedAt: state.updatedAt,
				sourceEvent: state.sourceEvent,
				attention: state.attention,
				promptStartedAt: state.promptStartedAt,
				erroredSince: state.erroredSince,
				turnEndedAt: state.turnEndedAt,
				now: currentTime
			)
		}

		// Step 3: elect lastActiveRenderKey only from keys that are currently
		// visible OR still within their TTL window — a clock-skewed key that
		// has left the snapshot must not hold last-active immunity forever.
		let eligibleKeys = Set(visibleEntries.keys).union(
			memory.lastSeenAt.keys.filter {
				currentTime.timeIntervalSince(memory.lastSeenAt[$0] ?? .distantPast) <= ttlSeconds
			}
		)
		let eligibleForElection = memory.lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		if !eligibleForElection.isEmpty {
			// Tie-break on `key.rawValue` (never bare `max(by:)`, whose result on
			// a tie depends on this Dictionary's internal hash-bucket layout,
			// not a canonical rule) — mirrors `freshestEntry(in:)` below.
			memory.lastActiveRenderKey = eligibleForElection.max { lhs, rhs in
				lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue < rhs.key.rawValue
			}?.key
		}

		// Step 3b: elect hudBearingRenderKey ("Show HUD on Most Recent Pet").
		// Re-elect only when the current holder is no longer in-flight or has
		// fallen out of eligibility; otherwise keep the same holder
		// regardless of what else updated this tick.
		let holderStillInFlight: Bool =
			if let key = memory.hudBearingRenderKey, eligibleKeys.contains(key) {
				visibleEntries[key]?.activityState.isInFlight ?? false
			} else {
				false
			}
		if !holderStillInFlight, !eligibleForElection.isEmpty {
			// Same canonical tie-break as `lastActiveRenderKey` above.
			memory.hudBearingRenderKey = eligibleForElection.max { lhs, rhs in
				lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue < rhs.key.rawValue
			}?.key
		}

		// Bound the tracked clocks to the eligibility window computed above —
		// without this they grow one entry per render key ever seen for the
		// lifetime of the process.
		memory.firstSeenAt = memory.firstSeenAt.filter { eligibleKeys.contains($0.key) }
		memory.lastSeenAt = memory.lastSeenAt.filter { eligibleKeys.contains($0.key) }
		memory.lastUpdatedAt = memory.lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		// "combined" is exempt, exactly like the legacy tracker: its eligibility
		// is per-origin while the tracker is keyed by the literal "combined".
		memory.promptTimers = memory.promptTimers.filter { eligibleKeys.contains($0.key) || $0.key == .combined }

		// The membership `derive` actually constructed a `DesiredWindow` for
		// LAST tick — the diff baseline for everything below. Captured before
		// any mutation this tick.
		let previousKeys = memory.previousDesiredWindowKeys

		// Which window key does a render key desire, given the CURRENT
		// customization? Combined-mode folds to `.combined` regardless of
		// session-pets; a non-combined origin with session-pets OFF folds
		// every render key sharing that origin down to the single plain
		// `.origin(origin)` key (mirroring `resolveRenderKeys`'s own fold,
		// generalized here so `derive` never depends on a stale window-key
		// shape surviving from a prior tick). Recomputing this fresh every
		// tick — rather than tracking "did the shape change since last
		// tick?" — is exactly what makes Steps 5a/6a/6a2/6b's imperative
		// teardown detection unnecessary: there is no stale `windows` dict to
		// mismatch against in the first place.
		func desiredWindowKey(_ renderKey: WindowKey) -> WindowKey {
			if renderKey == .combined { return .combined }
			let origin = renderKey.origin
			if mode(forWindowKey: renderKey) == .combined { return .combined }
			if customization.sessionPetsEnabled[origin] ?? false { return renderKey }
			return .origin(origin)
		}

		// Step 5b (render-key granularity): TTL-expiry, skipping the
		// last-active key.
		var ttlExpiredRenderKeys: Set<WindowKey> = []
		var survivingRenderKeys: [WindowKey] = []
		for key in visibleEntries.keys {
			if isTTLExpired(windowKey: key, memory: memory, ttlSeconds: ttlSeconds, currentTime: currentTime) {
				ttlExpiredRenderKeys.insert(key)
			} else {
				survivingRenderKeys.append(key)
			}
		}

		// Step 6: fold surviving render keys into their desired window keys.
		let foldedGroups = Dictionary(grouping: survivingRenderKeys, by: desiredWindowKey)
		let combinedModeConfigured = customization.platformModes.values.contains(.combined)
		func freshestEntry(in keys: [WindowKey]) -> (key: WindowKey, state: StateSnapshot)? {
			keys.compactMap { key in visibleEntries[key].map { (key, $0) } }.max { lhs, rhs in
				let left = StateJsonReader.parseISO8601Date(lhs.state.updatedAt) ?? .distantPast
				let right = StateJsonReader.parseISO8601Date(rhs.state.updatedAt) ?? .distantPast
				if left != right { return left < right }
				return lhs.key.rawValue < rhs.key.rawValue
			}
		}
		let combinedWinner = freshestEntry(in: foldedGroups[.combined] ?? [])
		if let winner = combinedWinner?.state {
			memory.promptTimers[.combined, default: PromptTimerTracker()].observe(
				state: winner.activityState, updatedAt: winner.updatedAt,
				sourceEvent: winner.sourceEvent, attention: winner.attention,
				promptStartedAt: winner.promptStartedAt, erroredSince: winner.erroredSince,
				turnEndedAt: winner.turnEndedAt, now: currentTime)
		} else if !combinedModeConfigured {
			memory.promptTimers.removeValue(forKey: .combined)
			memory.previousCombinedWindow = nil
		}

		// Session-keyed render keys whose fold preserved their own shape —
		// session-pets is genuinely on for their origin and they are not
		// combined-folded. Only these are subject to per-origin cap selection
		// (Step 6c); a plain-origin/"combined" fold group carries no cap
		// concept.
		let sessionCapCandidates = survivingRenderKeys.filter { $0.isSessionKeyed && desiredWindowKey($0) == $0 }
		let sessionCapKeysByOrigin = Dictionary(grouping: sessionCapCandidates, by: \.origin)

		// Non-cap-selected groups (plain-origin fold, combined fold, or an
		// already-origin-shaped key even with session-pets on) are always
		// admitted whole.
		var nonCapWindowKeys = Set(foldedGroups.keys).subtracting(sessionCapCandidates)
		// Legacy Step 8 transient-gap branch: while combined mode remains configured,
		// retain the last-active shared window across a one-tick empty poll.
		if foldedGroups[.combined] == nil, combinedModeConfigured,
			previousKeys.contains(.combined),
			memory.previousCombinedWindow.map({
				customization.platformModes[$0.resolvedIdentity.origin] == .combined
			}) == true,
			memory.lastActiveRenderKey.map(desiredWindowKey) == .combined
		{
			nonCapWindowKeys.insert(.combined)
		}

		// Step 6a2 (enabling direction only): a plain window desired LAST
		// tick that is no longer desired THIS tick, now that session-pets is
		// enabled for its origin, must hand its on-screen frame to the
		// grandfathered session replacing it. The disabling direction
		// (several session-keyed windows collapsing to one new plain window)
		// captures nothing — there is no single unambiguous frame to inherit
		// from, so `for case .origin` below simply never matches a
		// `.session` key in `previousKeys`.
		for case .origin(let origin) in previousKeys {
			guard customization.sessionPetsEnabled[origin] ?? false else { continue }
			guard !nonCapWindowKeys.contains(.origin(origin)) else { continue }
			memory.evictedFrameDirectives[origin, default: []].append(.origin(origin))
		}

		// Step 6c: per-origin session-cap selection (P15.07).
		var pendingWindowKeys: Set<WindowKey> = []
		var computedBlockedOrigins: Set<String> = []
		var genuinelyEvictedKeys: Set<WindowKey> = []
		var admittedSessionKeys: Set<WindowKey> = []
		for (origin, keys) in sessionCapKeysByOrigin {
			let states: [WindowKey: ActivityState] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.activityState
			}
			let updatedAt: [WindowKey: String] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.updatedAt
			}
			let cap = resolvedSessionCap(for: origin, customization: customization)
			memory.sessionNumberAllocator.setUnlimited(
				cap == CustomizationSnapshot.unlimitedSessionCap, origin: origin)

			// `currentlyRendered` reads from `slotOccupants`, NOT from
			// whichever keys happen to be visible this tick (P15.07-QC): a
			// user-hidden incumbent still holds its slot while its window is
			// torn down, and deriving incumbency from visibility/window
			// existence would strip that slot the instant it's hidden.
			let currentlyRendered = memory.slotOccupants.intersection(keys)
			let selection = SessionSelectionPolicy.select(
				sessions: states, cap: cap, currentlyRendered: currentlyRendered,
				updatedAt: updatedAt,
				incumbentsProtected: !customization.evictSessionPetsEnabled,
				// Explicitly-hidden keys are pinned — see
				// `SessionSelectionPolicy.select`'s own doc for the exact
				// "beats newcomers, yields to incumbents" contract.
				pinnedKeys: memory.userHiddenWindowKeys.intersection(keys),
				restrictNewPromotionsToInFlight: memory.prunedOrigins.contains(origin))

			// Resync `slotOccupants` to EXACTLY `selection.rendered` for this
			// origin's entire existing slice — not just the keys visible this
			// tick. A session that drops out of the snapshot entirely (TTL,
			// prune, or any other reason) must not leave a phantom slot
			// occupant behind for this origin to accumulate against; the
			// per-origin slice is fully replaced every tick, matching the
			// field's own documented contract ("replaces that origin's slice
			// of this set every tick").
			let existingOriginSlots = memory.slotOccupants.filter { $0.origin == origin }
			memory.slotOccupants.subtract(existingOriginSlots)
			memory.slotOccupants.formUnion(selection.rendered)

			let evictedThisOrigin = currentlyRendered.subtracting(selection.rendered)
			genuinelyEvictedKeys.formUnion(evictedThisOrigin)
			admittedSessionKeys.formUnion(selection.rendered)
			pendingWindowKeys.formUnion(selection.pending)

			// Capture each genuinely-evicted session's frame directive, in
			// deterministic eviction order (least-recently-updated first —
			// the same recency rule `SessionSelectionPolicy` itself uses to
			// rank evictability), never incidental `Set` iteration order
			// (this ticket's Review Focus). Only a key that actually had a
			// desired window last tick has a real frame to hand off — a
			// hidden incumbent's window is already gone by the time it's
			// evicted, so it is already absent from `previousKeys`.
			let capturedOrder = evictedThisOrigin.sorted { a, b in
				let dateA = updatedAt[a].flatMap(StateJsonReader.parseISO8601Date) ?? .distantPast
				let dateB = updatedAt[b].flatMap(StateJsonReader.parseISO8601Date) ?? .distantPast
				if dateA != dateB { return dateA < dateB }
				return a.rawValue < b.rawValue
			}
			for key in capturedOrder where previousKeys.contains(key) {
				memory.evictedFrameDirectives[origin, default: []].append(key)
			}

			if selection.blocked {
				computedBlockedOrigins.insert(origin)
			}
		}

		// An origin that held slot occupants on a prior tick but has ZERO
		// session-cap candidates this tick (every session-shaped render key
		// for that origin vanished from the snapshot entirely, not merely
		// evicted by the cap) never runs the per-origin loop above, so it
		// never reaches the slot-occupancy resync a few lines up. With no
		// surviving candidates, selection.rendered for that origin would
		// trivially be empty, so its entire slice is cleared here directly;
		// otherwise these stale occupants leak forever and can be
		// double-counted the next time the origin re-acquires candidates.
		let originsWithCandidatesThisTick = Set(sessionCapKeysByOrigin.keys)
		let staleOccupantOrigins = Set(memory.slotOccupants.map(\.origin))
			.subtracting(originsWithCandidatesThisTick)
		for origin in staleOccupantOrigins {
			memory.slotOccupants = memory.slotOccupants.filter { $0.origin != origin }
		}

		// A hidden key that genuinely loses the cap fight (P15.07-QC) must
		// not linger in `userHiddenWindowKeys` — otherwise the menu keeps
		// offering "Show <pet>" for a session that no longer holds a slot.
		let hiddenBeforePurge = memory.userHiddenWindowKeys
		memory.userHiddenWindowKeys.subtract(genuinelyEvictedKeys)

		// Final desired window-key membership, before the user-hidden filter.
		let finalKeys = nonCapWindowKeys.union(admittedSessionKeys)
		let visibleFinalKeys = finalKeys.subtracting(memory.userHiddenWindowKeys)

		// Freshly-spawning keys: desired this tick, absent from last tick's
		// actual desired membership — eligible to assign a session number and
		// drain one queued frame directive. Keys that disappeared (present
		// last tick, absent this tick) release their session number using
		// the identity CAPTURED AT ASSIGN TIME (`windowSessionIdentities`),
		// never the current tick's snapshot — which may no longer carry it
		// (the leak-under-cap bug this ticket's allocator fixes).
		let freshKeys = visibleFinalKeys.subtracting(previousKeys)
		let torndownKeys = previousKeys.subtracting(visibleFinalKeys)
		for key in torndownKeys where key.isSessionKeyed {
			memory.sessionNumbers.removeValue(forKey: key)
			memory.resolvedSessionTitles.removeValue(forKey: key)
			guard let identity = memory.windowSessionIdentities.removeValue(forKey: key) else { continue }
			// Refresh the allocator's unlimited/bounded mode for this identity's
			// origin against the CURRENT tick's customization before releasing —
			// not just relying on the per-origin cap-selection loop above, which
			// only runs for origins with candidates this tick. An origin whose
			// cap flips bounded<->unlimited on the very same tick all its
			// candidates disappear would otherwise release under whatever mode
			// was left over from a prior tick: incorrectly free-listing a number
			// (if now-unlimited) or incorrectly discarding a reusable number (if
			// now-bounded).
			let cap = resolvedSessionCap(for: identity.origin, customization: customization)
			memory.sessionNumberAllocator.setUnlimited(
				cap == CustomizationSnapshot.unlimitedSessionCap, origin: identity.origin)
			memory.sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
		}

		// Assign session numbers and drain frame directives for
		// freshly-spawning keys, in deterministic (sorted) order — draining
		// must not depend on `DesiredWindows.windows`'s own Dictionary
		// iteration order.
		var inheritedFrameByKey: [WindowKey: WindowKey] = [:]
		for key in freshKeys.sorted(by: { $0.rawValue < $1.rawValue }) {
			let origin = key.origin
			if key.isSessionKeyed, let identity = snapshot.renderKeyIdentities[key] {
				let cap = resolvedSessionCap(for: identity.origin, customization: customization)
				memory.sessionNumberAllocator.setUnlimited(
					cap == CustomizationSnapshot.unlimitedSessionCap, origin: identity.origin)
				memory.sessionNumbers[key] = memory.sessionNumberAllocator.assign(
					origin: identity.origin, sessionId: identity.sessionId)
				memory.windowSessionIdentities[key] = identity
			}
			if var queued = memory.evictedFrameDirectives[origin], !queued.isEmpty {
				let inherited = queued.removeFirst()
				if queued.isEmpty {
					memory.evictedFrameDirectives.removeValue(forKey: origin)
				} else {
					memory.evictedFrameDirectives[origin] = queued
				}
				inheritedFrameByKey[key] = inherited
			}
		}

		// Step 7/8: construct the complete controller push payload as data.
		var windows: [WindowKey: DesiredWindow] = [:]
		var titleRequests: [RenderKeyIdentity] = []
		for key in visibleFinalKeys.sorted(by: { $0.rawValue < $1.rawValue }) {
			var window = key == .combined
				? (memory.previousCombinedWindow ?? DesiredWindow(key: key))
				: DesiredWindow(key: key)
			if key != .combined || memory.previousCombinedWindow == nil {
				window.resolvedIdentity = key
			}
			window.isMinimalist =
				key == .combined
				? customization.combinedMinimalistEnabled
				: mode(forWindowKey: key) == .minimalist
			window.inheritedFrameFrom = inheritedFrameByKey[key]

			let winnerEntry: (key: WindowKey, state: StateSnapshot)? =
				if key == .combined {
					combinedWinner
				} else {
					visibleEntries[key].map { (key, $0) }
						?? freshestEntry(in: foldedGroups[key] ?? [])
				}

			if let winnerEntry {
				let mappedIdentity = snapshot.renderKeyIdentities[winnerEntry.key]
				if let identity = mappedIdentity {
					window.resolvedIdentity = identity.sessionId == "default"
						? .origin(identity.origin)
						: .session(origin: identity.origin, id: identity.sessionId)
				} else {
					window.resolvedIdentity = winnerEntry.key
				}
				window.hasActiveSession = mappedIdentity != nil || winnerEntry.key.isSessionKeyed
				let state = winnerEntry.state
				window.activityState = state.activityState
				window.attention = state.attention
				window.attentionSourceEvent = state.sourceEvent
				window.gateBadge = snapshot.gateBadges[winnerEntry.key]
				window.promptTimerStatus = memory.promptTimers[
					key == .combined ? .combined : winnerEntry.key]?.presentation(now: currentTime)
				if key == .combined {
					window.platformChip = state.activityState == .idle ? "combined" : state.sourceEvent?.origin
				} else if window.isMinimalist {
					window.platformChip = key.origin
				} else {
					window.platformChip = state.sourceEvent?.origin
				}
			}

			window.petId = input.assignments.resolve(origin: key == .combined ? "combined" : key.origin)
			window.rpgSnapshot = snapshot.rpgSnapshot
			window.sessionNumber = memory.sessionNumbers[key]
			window.sessionTooltip = key.isSessionKeyed ? input.sessionPromptSummaries[key] : nil
			let resolvedIdentity = window.resolvedIdentity
			if let known = input.knownSessionTitles[resolvedIdentity] {
				memory.resolvedSessionTitles[resolvedIdentity] = known
			}
			// Platform-only / Combined windows always own a fixed, non-renamable
			// mode chip ("Codex" / "Combined"). Session-keyed windows do not —
			// their `PlatformSessionBadge` is the only identity chrome.
			switch key {
			case .combined:
				window.modeIndicatorBadge = "Combined"
			case .origin(let origin):
				window.modeIndicatorBadge = PlatformAttribution(origin: origin)?.displayName
			case .session:
				window.modeIndicatorBadge = nil
			}
			// Session-label fallback must never reuse the mode-chip copy. Fold /
			// platform-only windows fall through to rename → LLM title →
			// "Session N", and omit the badge until one of those exists so the
			// mode chip stays the sole Combined/platform signal.
			let sessionFallback = memory.resolvedSessionTitles[resolvedIdentity]
				?? memory.sessionNumbers[resolvedIdentity].map { "Session \($0)" }
			let platformFallback =
				window.modeIndicatorBadge == nil
				? PlatformAttribution(origin: resolvedIdentity.origin)?.displayName
				: nil
			window.sessionLabel = input.sessionLabels[resolvedIdentity]
				?? sessionFallback
				?? platformFallback
			if key != resolvedIdentity, let label = window.sessionLabel {
				let platformName = PlatformAttribution(origin: resolvedIdentity.origin)?.displayName
				window.foldedSessionDisplay =
					if let platformName, platformName != label {
						"\(platformName) · \(label)"
					} else {
						label
					}
			}
			// Title requests key off resolvedIdentity's (origin, sessionId), not
			// `renderKeyIdentities[resolvedIdentity]`. Production identities are
			// keyed by the fold render key (`.origin` / `.combined` when
			// sessions are off), so a map lookup under the session key misses
			// and a fresh Combined/Minimalist prompt never fetches its LLM title.
			if case .session(let origin, let id) = resolvedIdentity,
				memory.resolvedSessionTitles[resolvedIdentity] == nil
			{
				titleRequests.append(RenderKeyIdentity(origin: origin, sessionId: id))
			}
			switch input.hudMode {
			case .all: window.hudEnabled = true
			case .hidden: window.hudEnabled = false
			case .mostRecent:
				let bearer = memory.hudBearingRenderKey.map(desiredWindowKey)
				window.hudEnabled = key == bearer
			}
			windows[key] = window
		}

		// Step 6c/7 conflict bubble: retain a living host; when it disappears,
		// re-home the same episode without consuming the one-hour fresh-presentation
		// limit. Only a genuinely new blocked episode consults and advances it.
		for origin in Set(memory.activeConflictBubbleTargets.keys).subtracting(computedBlockedOrigins) {
			memory.activeConflictBubbleTargets.removeValue(forKey: origin)
		}
		for origin in computedBlockedOrigins.sorted() {
			let candidates = visibleFinalKeys.filter { $0.origin == origin && $0.isSessionKeyed }
			let target = candidates.min {
				let left = memory.firstSeenAt[$0] ?? .distantFuture
				let right = memory.firstSeenAt[$1] ?? .distantFuture
				if left != right { return left < right }
				return $0.rawValue < $1.rawValue
			}
			guard let target else { continue }
			if let existing = memory.activeConflictBubbleTargets[origin] {
				let host = visibleFinalKeys.contains(existing) ? existing : target
				memory.activeConflictBubbleTargets[origin] = host
				windows[host]?.conflictBubble = ConflictBubblePayload(origin: origin)
			} else {
				let lastShown = memory.conflictBubbleLastShownAt[origin]
				guard lastShown == nil || currentTime.timeIntervalSince(lastShown!) > 3600 else { continue }
				memory.activeConflictBubbleTargets[origin] = target
				memory.conflictBubbleLastShownAt[origin] = currentTime
				windows[target]?.conflictBubble = ConflictBubblePayload(origin: origin)
			}
		}

		// `windowSpawnedModes` is recomputed fresh from scratch every tick for
		// exactly this tick's desired direct (non-`.combined`) keys — never
		// carried stale across a mode switch, since a pure fold recomputing
		// membership from scratch cannot exhibit the stale-window bug the
		// legacy imperative teardown steps (5a/6a/6a2/6b) exist to patch.
		memory.windowSpawnedModes = Dictionary(
			uniqueKeysWithValues: visibleFinalKeys.filter { $0 != .combined }.map { ($0, mode(forWindowKey: $0)) })

		memory.previousDesiredWindowKeys = visibleFinalKeys
		memory.previousCombinedWindow = windows[.combined]

		var desired = DesiredWindows()
		desired.windows = windows
		desired.titleResolutionRequests = titleRequests
		desired.idleEscalationConfig = IdleEscalationConfig.resolve(
			customization: customization, environment: input.idleEscalationEnvironment)
		if memory.lastMenubarIconMonochrome != customization.menubarIconMonochrome {
			desired.monochromeChanged = customization.menubarIconMonochrome
			memory.lastMenubarIconMonochrome = customization.menubarIconMonochrome
		}
		desired.blockedOrigins = computedBlockedOrigins
		desired.pendingSessionKeys = pendingWindowKeys
		desired.ttlDismissedWindowKeys = ttlExpiredRenderKeys.subtracting(pendingWindowKeys)
		if memory.userHiddenWindowKeys != hiddenBeforePurge {
			desired.hiddenWindowKeysToPersist = memory.userHiddenWindowKeys
		}

		return (desired, memory)
	}

	/// `origin`'s session cap per `CustomizationSnapshot.sessionCap`'s
	/// documented contract: an absent entry OR a negative value resolves to
	/// the shared default; `0` (Unlimited) and positive values pass through
	/// unchanged. Mirrors `FloatingPetWindowPool.resolvedSessionCap(for:)`.
	static func resolvedSessionCap(for origin: String, customization: CustomizationSnapshot) -> Int {
		guard let cap = customization.sessionCap[origin], cap >= 0 else {
			return CustomizationSnapshot.defaultSessionCap
		}
		return cap
	}

	/// True when `windowKey` is not the last-active key and its last-seen
	/// clock is older than `ttlSeconds`. Mirrors
	/// `FloatingPetWindowPool.isTTLExpired(windowKey:)` exactly, keyed by
	/// render key rather than the post-collapse window key — combined-window
	/// folding (Step 6/8) is P18.02 scope.
	static func isTTLExpired(
		windowKey: WindowKey, memory: PoolMemory, ttlSeconds: TimeInterval, currentTime: Date
	) -> Bool {
		guard windowKey != memory.lastActiveRenderKey else { return false }
		guard let seen = memory.lastSeenAt[windowKey] else { return true }
		return currentTime.timeIntervalSince(seen) > ttlSeconds
	}
}

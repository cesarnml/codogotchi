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
			// ordering. Bookkeeping only this ticket: `derive` does not yet
			// emit `DesiredWindow.promptTimerStatus` (P18.03).
			memory.promptTimers[renderKey, default: PromptTimerTracker()].observe(
				state: state.activityState,
				updatedAt: state.updatedAt,
				sourceEvent: state.sourceEvent,
				attention: state.attention,
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
			memory.lastActiveRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
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
			memory.hudBearingRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
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
		let nonCapWindowKeys = Set(foldedGroups.keys).subtracting(sessionCapCandidates)

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
				memory.sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
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

		// Step 7/8 membership (push-payload construction remains P18.03):
		// build one `DesiredWindow` per visible final key.
		var windows: [WindowKey: DesiredWindow] = [:]
		for key in visibleFinalKeys {
			var window = DesiredWindow(key: key)
			window.isMinimalist =
				key == .combined
				? customization.combinedMinimalistEnabled
				: mode(forWindowKey: key) == .minimalist
			window.inheritedFrameFrom = inheritedFrameByKey[key]
			windows[key] = window
		}

		// `windowSpawnedModes` is recomputed fresh from scratch every tick for
		// exactly this tick's desired direct (non-`.combined`) keys — never
		// carried stale across a mode switch, since a pure fold recomputing
		// membership from scratch cannot exhibit the stale-window bug the
		// legacy imperative teardown steps (5a/6a/6a2/6b) exist to patch.
		memory.windowSpawnedModes = Dictionary(
			uniqueKeysWithValues: visibleFinalKeys.filter { $0 != .combined }.map { ($0, mode(forWindowKey: $0)) })

		memory.previousDesiredWindowKeys = visibleFinalKeys

		var desired = DesiredWindows()
		desired.windows = windows
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

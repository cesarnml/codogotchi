import Foundation

/// Manages one `FloatingPetWindowControlling` instance per resolved render key
/// (or one shared "combined" window for combined-mode origins).
///
/// Since P15.03 the snapshot's `perPlatform` map is keyed by **resolved render
/// keys** from `resolveRenderKeys`: a plain `origin` (session-pets off), an
/// `origin:session_id` (session-pets on), or a pre-folded `"combined"`. The
/// pool keys windows by that resolved key uniformly — with session-pets on,
/// each active session gets its own window; collapsed keys are byte-identical
/// to the pre-Phase-15 origin keys, so all pre-existing behavior is unchanged.
///
/// Pool rules:
/// - Render keys whose owning origin's mode is "off" are filtered before any
///   window is spawned.
/// - Combined-mode origins fold into a single shared window keyed "combined"
///   (the driver pre-folds these; unfolded per-origin input folds here too).
/// - Every other render key gets its own window keyed by the resolved key.
/// - A window is dismissed when its render key's last-seen clock is older than
///   `ttlSeconds`, UNLESS that window is the last-active one.
/// - The last-active window (most-recently-updated render key across all
///   active keys) is never dismissed by TTL regardless of elapsed time.
@MainActor
final class FloatingPetWindowPool {
	typealias WindowFactory = (String, String) -> FloatingPetWindowControlling
	typealias MinimalistWindowFactory = (String) -> FloatingPetWindowControlling
	typealias CustomizationReader = () -> CustomizationSnapshot
	typealias AssignmentsReader = () -> AssignmentsSnapshot
	/// Reads a session's rename label given its window key
	/// (`"origin:session_id"` — the same string `SessionLabelStore` keys on).
	typealias SessionLabelReader = (String) -> String?
	/// Reads a session's last submitted prompt given its window key.
	typealias SessionPromptSummaryReader = (String) -> String?

	private let assignmentsReader: AssignmentsReader
	private let customizationReader: CustomizationReader
	private let windowFactory: WindowFactory
	private let minimalistWindowFactory: MinimalistWindowFactory?
	private let sessionLabelReader: SessionLabelReader
	private let sessionPromptSummaryReader: SessionPromptSummaryReader
	private let now: () -> Date

	/// Active windows keyed by window key (the resolved render key, or "combined").
	private var windows: [String: FloatingPetWindowControlling] = [:]
	/// Tracks the `now()` clock time when each render key was last present in a snapshot (TTL clock).
	private var lastSeenAt: [String: Date] = [:]
	/// First-seen clock per render key — unlike `lastSeenAt` this is set once
	/// and never refreshed, so P15.08's target selector can always find the
	/// longest-lived currently-rendered session for a blocked origin.
	private var firstSeenAt: [String: Date] = [:]
	/// Tracks the most-recent snapshot `updated_at` per render key (used to elect lastActiveRenderKey).
	private var lastUpdatedAt: [String: Date] = [:]
	/// Render key whose snapshot `updated_at` is most recent across all tracked keys.
	private var lastActiveRenderKey: String? = nil
	/// Most-recently read customization — updated at the start of each tick.
	private var currentCustomization: CustomizationSnapshot = .safeDefault
	/// Most-recently read assignments — updated at the start of each tick.
	private var currentAssignments: AssignmentsSnapshot = .safeDefault
	/// The `(origin, session_id)` identity behind each render key, from the
	/// latest `update(snapshot:)` tick — used to assign a session number when a
	/// window is spawned. NOT used to release, because a session's identity can
	/// (and, on the normal TTL-dismiss path, does) disappear from the snapshot
	/// before the window itself is torn down — see `windowSessionIdentities`.
	private var currentRenderKeyIdentities: [String: RenderKeyIdentity] = [:]
	/// Identity captured at assign time for every window key that currently
	/// holds a session number, keyed independently of `currentRenderKeyIdentities`.
	/// `releaseSessionNumber` must read from here, not from the latest snapshot:
	/// once a session ends, its `state.d` slice is deleted and its identity
	/// drops out of `snapshot.renderKeyIdentities` on the very next tick, but the
	/// window itself lingers until its TTL expires. Releasing from the stale
	/// snapshot would silently no-op and leak the number under a bounded cap.
	private var windowSessionIdentities: [String: RenderKeyIdentity] = [:]
	/// Free-list session-number allocator, keyed per-origin internally.
	/// Assign/release only apply to session-keyed windows (an `origin:session_id`
	/// render key) — plain-origin windows (session-pets off) and the literal
	/// "combined" window never carry a session number.
	private let sessionNumberAllocator = SessionNumberAllocator()
	/// Origins where `SessionSelectionPolicy` blocked an in-flight session from
	/// rendering on the most recent tick — every rendered slot for that origin
	/// is itself in-flight, so cap pressure has no evictable target (P15.07).
	/// Recomputed fresh every `update()` tick; consumed by P15.08's conflict
	/// bubble, never rendered here.
	private(set) var blockedOrigins: Set<String> = []
	/// Rate-limits P15.08 conflict-bubble presentation to at most one fire per
	/// platform per hour — `blockedOrigins` is recomputed fresh every tick, so
	/// without this gate a persisting conflict would re-front the bubble on
	/// every tick, including right after the user dismissed it.
	private var conflictBubbleRateLimiter = ConflictBubbleRateLimiter()
	/// Window key currently showing the P15.08 conflict bubble for each
	/// blocked origin, so an origin that clears from `blockedOrigins` can be
	/// told to hide its bubble.
	private var activeConflictBubbleTargets: [String: String] = [:]

	/// Window keys that currently have visible windows.
	var activeOrigins: [String] { Array(windows.keys).sorted() }

	/// Window keys explicitly hidden by the user via "Hide Pet". Excluded from spawning
	/// until the user explicitly shows them via "Show Pet".
	var hiddenWindowKeys: [String] { Array(userHiddenWindowKeys).sorted() }

	/// The pet ID currently assigned to the Default badge, read fresh from
	/// assignments.json on each `update()` tick.
	var defaultPetId: String { currentAssignments.default }

	/// Origins currently assigned to combined mode, read fresh from customization.
	/// The shared combined window folds all of these into one pet, so its right-click
	/// "Force Idle" must reset exactly this set — never every slice on disk, which
	/// would also idle independently-windowed pets.
	func combinedModeOrigins() -> [String] {
		let customization = customizationReader()
		return customization.platformModes
			.filter { $0.value == .combined }
			.map(\.key)
	}

	/// Owning origin of a window/render key: the prefix before the first colon
	/// for an `origin:session_id` key, the key itself otherwise (plain origins
	/// never contain a colon; the literal "combined" maps to itself).
	static func origin(forWindowKey key: String) -> String {
		guard let colon = key.firstIndex(of: ":") else { return key }
		return String(key[key.startIndex..<colon])
	}

	private var userHiddenWindowKeys: Set<String> = []

	/// Mode that was active when each window (keyed by window key) was spawned.
	/// Used to detect own↔minimalist transitions so the stale window is torn
	/// down and the correct factory runs on the next spawn gate.
	private var windowSpawnedModes: [String: PlatformMode] = [:]
	/// Renderer the current "combined" window was spawned with — nil when no
	/// combined window exists. Used to detect the combinedMinimalistEnabled
	/// setting toggling mid-flight so the window is torn down and respawned
	/// with the correct factory.
	private var combinedWindowIsMinimalist: Bool?

	/// Called when `menubarIconMonochrome` changes between ticks. The caller
	/// uses this to toggle `NSImage.isTemplate` on the status-item button.
	var onMonochromeChanged: ((Bool) -> Void)?

	init(
		assignmentsReader: @escaping AssignmentsReader = {
			AssignmentsJsonReader.read(at: CodogotchiFolders.assignmentsPath())
		},
		customizationReader: @escaping CustomizationReader = {
			CustomizationJsonReader.read(at: CodogotchiFolders.customizationPath())
		},
		windowFactory: @escaping WindowFactory,
		minimalistWindowFactory: MinimalistWindowFactory? = nil,
		sessionLabelReader: @escaping SessionLabelReader = { SessionLabelStore.label(for: $0) },
		sessionPromptSummaryReader: @escaping SessionPromptSummaryReader = {
			PromptAttentionReader.summary(forSessionKey: $0)
		},
		now: @escaping () -> Date = { Date() }
	) {
		self.assignmentsReader = assignmentsReader
		self.customizationReader = customizationReader
		self.windowFactory = windowFactory
		self.minimalistWindowFactory = minimalistWindowFactory
		self.sessionLabelReader = sessionLabelReader
		self.sessionPromptSummaryReader = sessionPromptSummaryReader
		self.now = now
	}

	func update(snapshot: PerPlatformSnapshot) {
		// Read customization and assignments fresh on every tick so Settings writes take effect within one second.
		let prevMonochrome = currentCustomization.menubarIconMonochrome
		currentCustomization = customizationReader()
		currentAssignments = assignmentsReader()
		currentRenderKeyIdentities = snapshot.renderKeyIdentities
		if currentCustomization.menubarIconMonochrome != prevMonochrome {
			onMonochromeChanged?(currentCustomization.menubarIconMonochrome)
		}
		let ttlSeconds: TimeInterval = currentCustomization.idleDismissTtlSeconds == 0
			? .infinity
			: TimeInterval(currentCustomization.idleDismissTtlSeconds)
		let currentTime = now()

		// Step 1: filter render keys whose owning origin's mode is off
		let visibleEntries = snapshot.perPlatform.filter { mode(forWindowKey: $0.key) != .off }

		// Step 2: update tracking for each visible render key
		for (renderKey, state) in visibleEntries {
			// TTL clock: advance only while the key is doing work. The idle-dismiss
			// TTL measures how long a pet has been idle, so an idle slice must NOT
			// refresh this clock — otherwise a still-present idle pet (whose slice
			// lingers in state.d/ for hours) reads as "just seen" every tick and never
			// dismisses. Seed on first sight so a freshly-observed idle pet still gets a
			// full TTL grace window before it disappears.
			if state.activityState != .idle || lastSeenAt[renderKey] == nil {
				lastSeenAt[renderKey] = currentTime
			}
			// First-seen clock: set once, never refreshed — P15.08's target
			// selector uses this to find the longest-lived rendered session.
			if firstSeenAt[renderKey] == nil {
				firstSeenAt[renderKey] = currentTime
			}
			// Active-key election: track snapshot's own updated_at timestamp
			let stateDate = StateJsonReader.parseISO8601Date(state.updatedAt) ?? currentTime
			if lastUpdatedAt[renderKey] == nil || stateDate > lastUpdatedAt[renderKey]! {
				lastUpdatedAt[renderKey] = stateDate
			}
		}

		// Step 3: elect lastActiveRenderKey only from keys that are currently visible
		// OR still within their TTL window. This prevents a clock-skewed key that
		// has left state.d/ from holding last-active immunity indefinitely.
		let eligibleKeys = Set(visibleEntries.keys).union(
			lastSeenAt.keys.filter {
				currentTime.timeIntervalSince(lastSeenAt[$0] ?? .distantPast) <= ttlSeconds
			}
		)
		let eligibleForElection = lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		if !eligibleForElection.isEmpty {
			lastActiveRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
		}

		// Step 4: compute the key of the window that must not be dismissed
		let lastActiveWindowKey: String? = lastActiveRenderKey.map { windowKey(for: $0) }

		// Step 5a: force-dismiss off-mode windows — no last-active immunity.
		// An origin switching to .off must exit the render pipeline this tick regardless of
		// TTL or last-active status. Only directly-keyed windows are affected here; the
		// combined window is handled in Step 8 when combinedEntries is empty.
		for renderKey in snapshot.perPlatform.keys where mode(forWindowKey: renderKey) == .off {
			if windows[renderKey] != nil {
				windows[renderKey]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: renderKey)
				windowSpawnedModes.removeValue(forKey: renderKey)
				releaseSessionNumber(forWindowKey: renderKey)
			}
		}

		// A window key is TTL-expired when it is not the last-active window and its
		// (idle-frozen) last-seen clock is older than the dismiss TTL. Used both to
		// dismiss existing windows (Step 5b) and to suppress re-spawn of an idle key
		// that has aged out (Steps 7–8): without the spawn guard, 5b would drop the
		// window and the spawn loop would immediately recreate it from the lingering
		// idle slice, so the pet would never actually disappear.
		func isTTLExpired(windowKey: String) -> Bool {
			guard windowKey != lastActiveWindowKey else { return false }
			guard let seen = lastSeenForWindow(key: windowKey) else { return true }
			return currentTime.timeIntervalSince(seen) > ttlSeconds
		}

		// Step 5b: dismiss stale windows (skip last-active)
		let staleKeys = windows.keys.filter { isTTLExpired(windowKey: $0) }
		for key in staleKeys {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			releaseSessionNumber(forWindowKey: key)
		}

		// Step 6: separate combined vs directly-keyed entries. The driver pre-folds
		// combined origins to the literal "combined" key; unfolded per-origin input
		// (the pre-P15.03 shape the existing tests feed) folds here via windowKey.
		// Sorted so Step 7's session-number assignment is deterministic when two
		// or more brand-new sessions for the same origin appear in the same tick —
		// `visibleEntries.keys` is a Dictionary view with unspecified iteration
		// order, and without sorting, which session gets the lower number would
		// vary run to run (same nondeterminism `resolveRenderKeys` already guards
		// against via sorted iteration).
		let directKeys = visibleEntries.keys.filter { windowKey(for: $0) != "combined" }.sorted()
		let combinedKeys = visibleEntries.keys.filter { windowKey(for: $0) == "combined" }

		// Step 6a: collapse directly-keyed windows for keys that switched to combined
		// mode. A key moving own→combined must lose its own window immediately so it
		// doesn't render a second window alongside the shared combined one. The
		// literal "combined" key IS the shared window, so it is never torn down here.
		for renderKey in combinedKeys where renderKey != "combined" && windows[renderKey] != nil {
			windows[renderKey]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: renderKey)
			windowSpawnedModes.removeValue(forKey: renderKey)
			releaseSessionNumber(forWindowKey: renderKey)
		}

		// Step 6b: collapse windows whose controller type no longer matches the current
		// mode. own→minimalist and minimalist→own transitions are not covered by Steps
		// 5a or 6a; if we skip teardown here the wrong-type window stays in `windows`
		// and the spawn gate below (windows[renderKey] == nil) is never entered.
		for renderKey in directKeys where windows[renderKey] != nil {
			if let spawnedMode = windowSpawnedModes[renderKey],
				spawnedMode != mode(forWindowKey: renderKey)
			{
				windows[renderKey]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: renderKey)
				windowSpawnedModes.removeValue(forKey: renderKey)
				releaseSessionNumber(forWindowKey: renderKey)
			}
		}

		// Step 6c: per-origin session-cap selection (P15.07). Only applies to
		// session-keyed render keys — a plain-origin key (session-pets off) is
		// already the sole entry for its origin, so cap partitioning is
		// meaningless for it. Recomputed fresh every tick from the currently
		// visible session set; "promotion" needs no dedicated bookkeeping
		// because a session that drops out of `pending` (its rival was pruned,
		// aged out, or dropped to an evictable state) simply becomes rendered
		// again the next time this runs.
		var pendingWindowKeys: Set<String> = []
		var computedBlockedOrigins: Set<String> = []
		let sessionKeyedDirectKeys = directKeys.filter { isSessionKeyed($0) }
		let sessionKeyedByOrigin = Dictionary(
			grouping: sessionKeyedDirectKeys, by: Self.origin(forWindowKey:))
		for (origin, keys) in sessionKeyedByOrigin {
			let states: [String: ActivityState] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.activityState
			}
			let cap = currentCustomization.sessionCap[origin] ?? 3
			let currentlyRendered = Set(keys.filter { windows[$0] != nil })
			let selection = SessionSelectionPolicy.select(
				sessions: states, cap: cap, currentlyRendered: currentlyRendered)
			pendingWindowKeys.formUnion(selection.pending)
			guard selection.blocked else { continue }
			computedBlockedOrigins.insert(origin)
			// P15.08: fire the conflict bubble on the longest-lived
			// currently-rendered session, subject to the per-platform rate
			// limit — this signal is recomputed fresh every tick, so without
			// the rate limiter a persisting conflict would re-front the
			// bubble every tick.
			guard conflictBubbleRateLimiter.shouldShow(origin: origin, now: currentTime) else { continue }
			let candidates = firstSeenAt.filter { currentlyRendered.contains($0.key) }
			guard let target = ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: candidates)
			else { continue }
			conflictBubbleRateLimiter.recordShown(origin: origin, now: currentTime)
			activeConflictBubbleTargets[origin] = target
			windows[target]?.applyConflictBubble(ConflictBubblePayload(origin: origin))
		}
		blockedOrigins = computedBlockedOrigins
		// Clear the conflict bubble for any origin that resolved this tick —
		// promotion (P15.07) freed the withheld slot, so the conflict no
		// longer applies. The one-hour rate limit is untouched by this clear.
		for (origin, targetKey) in activeConflictBubbleTargets
		where !computedBlockedOrigins.contains(origin) {
			windows[targetKey]?.applyConflictBubble(nil)
			activeConflictBubbleTargets.removeValue(forKey: origin)
		}

		// Step 7: spawn / update directly-keyed windows
		for renderKey in directKeys {
			guard let state = visibleEntries[renderKey] else { continue }
			// Idle past TTL: leave it dismissed and do not re-spawn from the lingering
			// idle slice (Step 5b already removed any window for it).
			if isTTLExpired(windowKey: renderKey) {
				if windows[renderKey] != nil {
					windows[renderKey]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: renderKey)
					windowSpawnedModes.removeValue(forKey: renderKey)
					releaseSessionNumber(forWindowKey: renderKey)
				}
				continue
			}
			// Cap-held (pending): a reversible de-render, not a delete — the
			// slice stays on disk untouched so this key can be promoted back the
			// instant it wins a later tick's partition. The session number is
			// released on de-render, matching every other window-teardown site
			// in this method; a promoted session may pick up a different number
			// than it held before, since only the currently-rendered set is ever
			// numbered.
			if pendingWindowKeys.contains(renderKey) {
				if windows[renderKey] != nil {
					windows[renderKey]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: renderKey)
					windowSpawnedModes.removeValue(forKey: renderKey)
					releaseSessionNumber(forWindowKey: renderKey)
				}
				continue
			}
			// User-hidden: do not re-spawn until the user explicitly shows the pet.
			if userHiddenWindowKeys.contains(renderKey) { continue }
			// Pet identity and mode are per-ORIGIN: every session window of a platform
			// renders that platform's assigned (or Default) pet and follows its mode.
			let origin = Self.origin(forWindowKey: renderKey)
			if windows[renderKey] == nil {
				let petId = currentAssignments.resolve(origin: origin)
				assignSessionNumber(forWindowKey: renderKey)
				let controller: FloatingPetWindowControlling
				if mode(for: origin) == .minimalist {
					guard let minimalistWindowFactory else {
						NSLog("FloatingPetWindowPool: minimalist mode requires a minimalistWindowFactory for \(renderKey)")
						continue
					}
					controller = minimalistWindowFactory(renderKey)
				} else {
					controller = windowFactory(renderKey, petId)
				}
				controller.setFloatingPetVisible(true)
				windows[renderKey] = controller
				windowSpawnedModes[renderKey] = mode(for: origin)
			}
			windows[renderKey]?.apply(state: state.activityState, visualMode: .normal)
			windows[renderKey]?.applyAttention(
				payload: state.attention,
				sourceEvent: state.sourceEvent
			)
			windows[renderKey]?.applyGateBadge(content: snapshot.gateBadges[renderKey])
			if mode(for: origin) == .minimalist {
				windows[renderKey]?.applyPlatform(origin: origin)
			} else if let sourceOrigin = state.sourceEvent?.origin {
				windows[renderKey]?.applyPlatform(origin: sourceOrigin)
			}
			windows[renderKey]?.applySessionNumber(sessionNumber(forWindowKey: renderKey))
			windows[renderKey]?.applySessionLabel(sessionLabel(forWindowKey: renderKey))
			windows[renderKey]?.applySessionTooltip(sessionPromptSummary(forWindowKey: renderKey))
		}

		// Step 8: spawn / update combined window
		if !combinedKeys.isEmpty {
			// Style toggle: if the existing combined window was spawned with the wrong
			// renderer for the current combinedMinimalistEnabled setting, tear it down so
			// the spawn gate below recreates it with the correct factory.
			if let combined = windows["combined"],
				combinedWindowIsMinimalist != currentCustomization.combinedMinimalistEnabled
			{
				combined.setFloatingPetVisible(false)
				windows.removeValue(forKey: "combined")
			}
			if isTTLExpired(windowKey: "combined") {
				// All combined-folded keys idle past TTL (and not last-active): dismiss
				// the shared window and do not re-spawn it this tick.
				if windows["combined"] != nil {
					windows["combined"]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: "combined")
				}
			} else if !userHiddenWindowKeys.contains("combined") {
				let combinedEntries = combinedKeys.compactMap { key in
					visibleEntries[key].map { (key: key, state: $0) }
				}
				let winnerEntry = combinedEntries.max(by: { a, b in
					(StateJsonReader.parseISO8601Date(a.state.updatedAt) ?? .distantPast)
						< (StateJsonReader.parseISO8601Date(b.state.updatedAt) ?? .distantPast)
				})
				if let winnerEntry {
					let winner = winnerEntry.state
					if windows["combined"] == nil {
						let useMinimalist = currentCustomization.combinedMinimalistEnabled
						let controller: FloatingPetWindowControlling
						if useMinimalist {
							guard let minimalistWindowFactory else {
								NSLog("FloatingPetWindowPool: combined-minimalist mode requires a minimalistWindowFactory")
								return
							}
							controller = minimalistWindowFactory("combined")
						} else {
							let petId = currentAssignments.resolve(origin: "combined")
							controller = windowFactory("combined", petId)
						}
						controller.setFloatingPetVisible(true)
						windows["combined"] = controller
						combinedWindowIsMinimalist = useMinimalist
					}
					windows["combined"]?.apply(state: winner.activityState, visualMode: .normal)
					windows["combined"]?.applyAttention(
						payload: winner.attention,
						sourceEvent: winner.sourceEvent
					)
					// The combined window's gate badge follows whichever entry is
					// currently winning the shared pet, mirroring the platform-chip
					// precedent below. Badges are keyed by render key, so the winning
					// entry's key resolves for both pre-folded ("combined") and
					// unfolded (per-origin) input.
					windows["combined"]?.applyGateBadge(content: snapshot.gateBadges[winnerEntry.key])
					// While idle the combined window shows the persistent ⭐ Default badge;
					// when active it badges with whichever platform triggered the winning
					// state, matching the pre-phase-13 single-pet behavior.
					if winner.activityState == .idle {
						windows["combined"]?.applyPlatform(origin: "combined")
					} else if let sourceOrigin = winner.sourceEvent?.origin {
						windows["combined"]?.applyPlatform(origin: sourceOrigin)
					}
				}
			}
		} else {
			// No combined-folded keys → dismiss combined window if present,
			// but only when it is not the last-active window (same immunity as own-mode).
			if windows["combined"] != nil && "combined" != lastActiveWindowKey {
				windows["combined"]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: "combined")
			}
		}

		// Step 9: broadcast RPG to all windows
		let rpg = snapshot.rpgSnapshot
		let hudEnabled = PetConfig.resolvedRPGHUDEnabled()
		for controller in windows.values {
			controller.applyRPGState(
				halfHearts: rpg.halfHearts,
				levelFraction: rpg.levelFraction,
				level: rpg.level,
				activeMinutes: rpg.activeMinutes,
				hudEnabled: hudEnabled
			)
		}
	}

	/// Returns true when the window for the given key is currently in `windows`.
	func isActive(for key: String) -> Bool { windows[key] != nil }

	/// Hides or shows the window for the given key.
	/// Hiding persists across update() ticks until setVisible(true) is called.
	func setVisible(_ visible: Bool, for key: String) {
		if visible {
			userHiddenWindowKeys.remove(key)
			// Re-spawn is handled by the next update() tick once the key is unblocked.
		} else {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			releaseSessionNumber(forWindowKey: key)
			userHiddenWindowKeys.insert(key)
		}
	}

	/// Returns the controller for the given window key. Used by MenubarApp to wire
	/// per-window callbacks (attention dismiss, app-nap opt-out).
	func controller(for key: String) -> FloatingPetWindowControlling? { windows[key] }

	/// Manual "Prune Session" (P15.07, right-click on a session-keyed window):
	/// tears down the panel and destroys its state.d slice, free-list number,
	/// and session-labels.json key — the same end-state as automatic TTL
	/// expiry plus the orphan-label sweep. No-op for a plain-origin/"combined"
	/// window, since those are never session-keyed. `stateDirectory` is the
	/// live `state.d/` path (`config.pollingTarget.path`), passed by the
	/// caller so this pool never hardcodes a filesystem location. `labelPath`
	/// defaults to the real `session-labels.json` location and exists as a
	/// parameter purely so tests can redirect it, mirroring `sessionLabelReader`.
	func pruneSession(
		windowKey: String,
		stateDirectory: String,
		labelPath: String = SessionLabelStore.path()
	) {
		guard isSessionKeyed(windowKey),
			let identity = windowSessionIdentities[windowKey] ?? currentRenderKeyIdentities[windowKey]
		else { return }
		windows[windowKey]?.setFloatingPetVisible(false)
		windows.removeValue(forKey: windowKey)
		windowSpawnedModes.removeValue(forKey: windowKey)
		windowSessionIdentities.removeValue(forKey: windowKey)
		SessionPruner.pruneSession(
			windowKey: windowKey,
			origin: identity.origin,
			sessionId: identity.sessionId,
			stateDirectory: stateDirectory,
			allocator: sessionNumberAllocator,
			labelPath: labelPath
		)
	}

	/// Live-swap the rendered pet for one origin's windows. Called when the user
	/// reassigns a platform badge in Settings > Pet so only that platform's windows
	/// update; other windows are untouched. Pet identity is per-origin, so ALL of
	/// the origin's session windows swap together (or its folded "combined"
	/// window when the origin is in combined mode). Newly spawned windows already
	/// pick up the current assignment via the factory's petId argument.
	func replacePet(origin: String, codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		let foldedKey = windowKey(for: origin)
		for key in windows.keys
		where key == foldedKey || Self.origin(forWindowKey: key) == origin {
			windows[key]?.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
		}
	}

	/// Session number assigned to `windowKey`, or `nil` for a plain-origin or
	/// "combined" window (session numbering only applies to session-keyed
	/// windows). Consumers (e.g. `MenubarApp` wiring the session badge) call
	/// this after a window is spawned/updated.
	func sessionNumber(forWindowKey key: String) -> Int? {
		guard isSessionKeyed(key), let identity = currentRenderKeyIdentities[key] else { return nil }
		return sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
	}

	/// Rename label for `windowKey`, or `nil` for a plain-origin/"combined"
	/// window, or a session-keyed window with no sidecar label set. The
	/// window key for a session-keyed window IS the `SessionLabelStore` key
	/// (`"origin:session_id"`), so no identity lookup is needed here.
	func sessionLabel(forWindowKey key: String) -> String? {
		guard isSessionKeyed(key) else { return nil }
		return sessionLabelReader(key)
	}

	/// Last submitted prompt for `windowKey`'s exact session, or `nil` for a
	/// plain-origin/"combined" window.
	func sessionPromptSummary(forWindowKey key: String) -> String? {
		guard isSessionKeyed(key) else { return nil }
		return sessionPromptSummaryReader(key)
	}

	// MARK: - Private helpers

	private func mode(for origin: String) -> PlatformMode {
		currentCustomization.platformModes[origin] ?? .own
	}

	/// True when `key` is a session-keyed render key (`origin:session_id`),
	/// as opposed to a plain origin (session-pets off) or the literal
	/// "combined" key. Session numbering only ever applies to these keys.
	private func isSessionKeyed(_ key: String) -> Bool {
		key != "combined" && key.contains(":")
	}

	/// Assigns a session number for a newly-spawned session-keyed window and
	/// remembers the identity under `windowSessionIdentities` so a later
	/// `releaseSessionNumber` call — which may land well after this session's
	/// identity has dropped out of `currentRenderKeyIdentities` (TTL dismiss of
	/// an already-ended session) — can still resolve the correct
	/// (origin, sessionId) pair to free. No-op for plain-origin or "combined"
	/// windows.
	private func assignSessionNumber(forWindowKey key: String) {
		guard isSessionKeyed(key), let identity = currentRenderKeyIdentities[key] else { return }
		let unlimited = (currentCustomization.sessionCap[identity.origin] ?? 3) == 0
		sessionNumberAllocator.setUnlimited(unlimited, origin: identity.origin)
		sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
		windowSessionIdentities[key] = identity
	}

	/// Releases the session number for a dismissed session-keyed window, using
	/// the identity captured at assign time rather than the latest snapshot —
	/// see `windowSessionIdentities`. No-op for plain-origin or "combined"
	/// windows, and a safe no-op if the window never held a session number
	/// (e.g. it was torn down before ever being assigned one).
	private func releaseSessionNumber(forWindowKey key: String) {
		guard isSessionKeyed(key), let identity = windowSessionIdentities.removeValue(forKey: key) else { return }
		let unlimited = (currentCustomization.sessionCap[identity.origin] ?? 3) == 0
		sessionNumberAllocator.setUnlimited(unlimited, origin: identity.origin)
		sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
	}

	private func mode(forWindowKey key: String) -> PlatformMode {
		mode(for: Self.origin(forWindowKey: key))
	}

	/// THE single branch site mapping a render key to its window key: the
	/// literal "combined" and combined-mode origins fold to "combined"; every
	/// other resolved key (plain origin or origin:session_id) is its own window.
	private func windowKey(for renderKey: String) -> String {
		renderKey == "combined" || mode(forWindowKey: renderKey) == .combined
			? "combined" : renderKey
	}

	/// Most-recent lastSeenAt across all tracked render keys that map to this
	/// window key (several fold into "combined"; every other key maps to itself).
	private func lastSeenForWindow(key: String) -> Date? {
		if key == "combined" {
			return lastSeenAt
				.filter { windowKey(for: $0.key) == "combined" }
				.values.max()
		}
		return lastSeenAt[key]
	}
}

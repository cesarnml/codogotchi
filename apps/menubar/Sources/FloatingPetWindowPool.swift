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
	/// The `IdleEscalationConfig` last pushed to every open window, so a tick
	/// that resolves an unchanged config (the common case) skips re-pushing it
	/// to every controller. `nil` until the first tick actually applies one.
	private var lastAppliedIdleEscalationConfig: IdleEscalationConfig?
	/// This tick's resolved `IdleEscalationConfig`, read by `windowFactory`
	/// (via the pool the caller holds) so a window spawned later in THIS same
	/// tick starts with the exact value already computed here, instead of the
	/// factory independently re-reading and re-decoding `customization.json`
	/// from disk — which would also risk disagreeing with `currentCustomization`
	/// if the file changed between the two reads.
	private(set) var resolvedIdleEscalationConfig: IdleEscalationConfig = .production
	/// Snapshotted once at init rather than re-read from `ProcessInfo` on
	/// every tick — the `CODOGOTCHI_IDLE_*_MS` overrides it carries are fixed
	/// for the life of the process, so there is nothing to gain from copying
	/// the whole environment dictionary again every ~1s tick.
	private let idleEscalationEnvironment: [String: String]
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
	/// Origins that have had a manual "Prune Session" (P15.07) at least once
	/// this app session (P15.07-QC). Once armed, `SessionSelectionPolicy.select`
	/// only lets a non-rendered session newly promote into a freed slot while
	/// it is in-flight — a manual prune is a deliberate curation action, and a
	/// standby/idle session merely held by cap pressure must not silently take
	/// the pruned session's place. Never cleared during the process lifetime;
	/// deliberately in-memory only so a restart returns the origin to the
	/// passive TTL/cap contract.
	private var prunedOrigins: Set<String> = []
	/// Session-keyed window keys that hold a cap slot (P15.07-QC), independent
	/// of whether their window is actually spawned. Diverges from
	/// `windows.keys` exactly when a slot's window is user-hidden: hide/show
	/// (`setVisible`) only ever toggles `windows`/`userHiddenWindowKeys` and
	/// must never write to this set, so a hidden incumbent keeps its slot and
	/// showing it again respawns immediately with no fresh cap contention —
	/// matching a manually-Pruned session's "gone" versus a hidden session's
	/// "still here, just concealed." The sole writer is Step 6c: each origin's
	/// `SessionSelectionPolicy.select` result replaces that origin's slice of
	/// this set every tick, so a key leaves it only via genuine eviction (rank
	/// loss), Prune, or TTL — never via hide. Bounded by the same
	/// `eligibleKeys` filter as `firstSeenAt`/`lastSeenAt`/`lastUpdatedAt`.
	private var slotOccupants: Set<String> = []
	/// Rate-limits P15.08 conflict-bubble presentation to at most one fire per
	/// platform per hour — `blockedOrigins` is recomputed fresh every tick, so
	/// without this gate a persisting conflict would re-front the bubble on
	/// every tick, including right after the user dismissed it.
	private var conflictBubbleRateLimiter = ConflictBubbleRateLimiter()
	/// Window key currently showing the P15.08 conflict bubble for each
	/// blocked origin, so an origin that clears from `blockedOrigins` can be
	/// told to hide its bubble.
	private var activeConflictBubbleTargets: [String: String] = [:]
	/// Frames of windows torn down per origin for reasons a later spawn for
	/// that same origin should inherit from, captured the instant the old
	/// window goes down and consumed FIFO the next time(s) a new window
	/// spawns for that origin — so the incoming window takes over the exact
	/// on-screen slot instead of defaulting. Two capture sites feed this: (1)
	/// session-cap eviction (P15.07) — a rendered session dropping to
	/// `pending` so the promoted session takes its slot; (2) the plain-origin
	/// window torn down when session-pets is enabled for its origin (Step
	/// 6a2) — so the grandfathered session inherits the collapsed pet's exact
	/// slot instead of the default spawn position. A queue, not a single
	/// slot: a single tick can evict more than one sibling at once (e.g.
	/// lowering a session cap by more than 1), and every evicted frame must
	/// survive to be claimed by a later spawn, not just the last one captured.
	private var evictedSessionFrames: [String: [CGRect]] = [:]

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

	/// Splits a session-keyed window key (`origin:session_id`) into its parts,
	/// or `nil` for a plain origin or the literal `"combined"` key — mirroring
	/// `origin(forWindowKey:)`'s colon-split contract. Used to target a
	/// session-precise Force Idle / dismiss-attention write at exactly the
	/// clicked session's `state.d/` slice instead of falling back to
	/// origin-only resolution, which can't distinguish which sibling session
	/// the user actually clicked.
	static func sessionIdentity(forWindowKey key: String) -> (origin: String, sessionId: String)? {
		guard key != "combined", let colon = key.firstIndex(of: ":") else { return nil }
		let origin = String(key[key.startIndex..<colon])
		let sessionId = String(key[key.index(after: colon)...])
		return (origin, sessionId)
	}

	/// Platform origin whose `platform_modes` entry the right-click mode-switch
	/// affordance (Pet Mode ↔ Minimalist Mode) should rewrite for the window
	/// keyed `key`, or `nil` for the literal `"combined"` window — that one
	/// flips `combined_minimalist_enabled` instead of any origin's mode. A
	/// session-keyed key resolves to its platform origin: mode is keyed
	/// per-origin, so the switch is platform-level and every sibling session
	/// panel of the same platform flips together.
	static func modeSwitchOrigin(forWindowKey key: String) -> String? {
		guard key != "combined" else { return nil }
		return sessionIdentity(forWindowKey: key)?.origin ?? key
	}

	private var userHiddenWindowKeys: Set<String> = []
	private let hiddenKeysSaver: (Set<String>) -> Void

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
		// No production-disk defaults: unlike assignmentsReader/customizationReader
		// (read-only, idempotent), a hidden-keys default that wrote through to
		// AppStateStore would make every setVisible() call in the test suite — which
		// does not sandbox CODOGOTCHI_HOME — silently overwrite the developer's real
		// ~/.codogotchi/app-state.json. Production wiring happens explicitly in
		// MenubarApp.
		hiddenKeysLoader: @escaping () -> Set<String> = { [] },
		hiddenKeysSaver: @escaping (Set<String>) -> Void = { _ in },
		now: @escaping () -> Date = { Date() },
		idleEscalationEnvironment: [String: String] = ProcessInfo.processInfo.environment
	) {
		self.assignmentsReader = assignmentsReader
		self.customizationReader = customizationReader
		self.windowFactory = windowFactory
		self.minimalistWindowFactory = minimalistWindowFactory
		self.sessionLabelReader = sessionLabelReader
		self.sessionPromptSummaryReader = sessionPromptSummaryReader
		self.hiddenKeysSaver = hiddenKeysSaver
		self.now = now
		self.idleEscalationEnvironment = idleEscalationEnvironment
		// Restore user-hidden window keys across app restarts. Keys for pets that
		// have since TTL-expired are harmless here: the spawn gate at Step 7 only
		// ever consults this set for keys already surviving this tick's TTL/mode
		// filtering, so restoration is implicitly "prune (by the tick's own
		// eligibility filtering), then restore" with no extra bookkeeping needed.
		self.userHiddenWindowKeys = hiddenKeysLoader()
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

		// Live-propagate a changed Idle Escalation Timing setting into every
		// already-open window: the config is otherwise only read once, at
		// window-spawn time, and would never notice a Settings change
		// mid-session without this. Stored on `self` (not just a local) so
		// `windowFactory` — called later in this same tick by Step 7 — can
		// read the exact value just resolved here instead of re-reading disk.
		resolvedIdleEscalationConfig = IdleEscalationConfig.resolve(
			customization: currentCustomization, environment: idleEscalationEnvironment)
		if resolvedIdleEscalationConfig != lastAppliedIdleEscalationConfig {
			for controller in windows.values {
				controller.updateIdleEscalationConfig(resolvedIdleEscalationConfig)
			}
			lastAppliedIdleEscalationConfig = resolvedIdleEscalationConfig
		}

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

		// Bound firstSeenAt/lastSeenAt/lastUpdatedAt to the same eligibility
		// window computed above — without this they grow one entry per render
		// key ever seen for the lifetime of the app process (P15.08
		// advisory-observation triage). A key outside eligibleKeys is neither
		// visible nor within its TTL grace window, so nothing later in this
		// tick — or any future tick — can legitimately reference it: render
		// key identities are agent-generated session ids that do not recur.
		// Any key with an open window is guaranteed to remain in
		// eligibleKeys (its TTL can't have expired, or Step 5b would already
		// have torn the window down), so this can never prune a live window's
		// bookkeeping out from under Step 6c.
		firstSeenAt = firstSeenAt.filter { eligibleKeys.contains($0.key) }
		lastSeenAt = lastSeenAt.filter { eligibleKeys.contains($0.key) }
		lastUpdatedAt = lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		slotOccupants = slotOccupants.filter { eligibleKeys.contains($0) }

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

		// Step 6a: collapse directly-keyed windows whose owning origin switched to
		// combined mode. A key moving own/minimalist→combined must lose its own
		// window immediately so it doesn't render a second window alongside the
		// shared combined one. Iterates the pool's OWN window keys, not the
		// snapshot's: since P15.03 the driver pre-folds combined origins to the
		// literal "combined" key, so the stale window's key never appears in the
		// snapshot again and only the current customization can identify it. The
		// literal "combined" key IS the shared window, so it is never torn down here.
		let collapsedKeys = windows.keys.filter { $0 != "combined" && windowKey(for: $0) == "combined" }
		for key in collapsedKeys {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			releaseSessionNumber(forWindowKey: key)
		}

		// Step 6a2: collapse windows whose origin's session-pets setting no longer
		// matches the window's key SHAPE (plain origin vs origin:session_id).
		// sessionPetsEnabled is read only in resolveRenderKeys (independent of
		// mode) to decide which shape a non-combined origin's render keys take;
		// toggling it makes the OLD shape's key vanish from the snapshot entirely
		// while the NEW shape's key(s) appear under a completely different
		// string, so none of the mode-keyed teardown branches above (5a, 6a, or
		// 6b below) ever observe the transition — 6b in particular only
		// re-checks a render key that is still present in this tick's snapshot
		// under the SAME key string, which is exactly what does not happen here.
		// Excludes combined-mode origins: combined folds unconditionally
		// regardless of sessionPetsEnabled (see resolveRenderKeys), so a
		// combined origin's windows are never plain/session-keyed to begin with
		// — Step 6a already owns their collapse.
		let sessionShapeMismatchKeys = windows.keys.filter { key in
			guard key != "combined" else { return false }
			let origin = Self.origin(forWindowKey: key)
			guard mode(for: origin) != .combined else { return false }
			let sessionsOn = currentCustomization.sessionPetsEnabled[origin] ?? false
			return isSessionKeyed(key) != sessionsOn
		}
		for key in sessionShapeMismatchKeys {
			// Grandfather-frame inheritance: when THIS key is the plain-origin
			// window being torn down because session-pets was just enabled for
			// its origin, capture its frame into the same evictedSessionFrames
			// queue Step 7 already drains on spawn — so the incoming
			// grandfathered session window inherits the exact slot the user was
			// already looking at, instead of defaulting. Only the enabling
			// direction is captured here: on the disabling direction (several
			// session-keyed windows collapsing to one new plain window), there
			// is no single unambiguous frame to inherit from, so that case is
			// left to spawn at the default position as before.
			if !isSessionKeyed(key) {
				let origin = Self.origin(forWindowKey: key)
				if currentCustomization.sessionPetsEnabled[origin] ?? false {
					evictedSessionFrames[origin, default: []].append(windows[key]!.currentFrame)
				}
			}
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			releaseSessionNumber(forWindowKey: key)
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
		//
		// `currentlyRendered` is read from `slotOccupants`, NOT `windows[$0] !=
		// nil` (P15.07-QC): a user-hidden incumbent's window is torn down while
		// it still holds its slot, and deriving incumbency from window
		// existence would strip that slot the instant it's hidden, letting an
		// unrelated standby session backfill it — indistinguishable in the UI
		// from the hidden pet reappearing as something else. `slotOccupants` is
		// resynced to exactly `selection.rendered` for this origin every tick,
		// so hide/show never has to touch it directly.
		var pendingWindowKeys: Set<String> = []
		var computedBlockedOrigins: Set<String> = []
		// Keys that genuinely lose the cap fight this tick (were an occupant,
		// no longer are) get their hidden flag cleared below — see the
		// `userHiddenWindowKeys.subtract` call after this loop.
		var genuinelyEvictedKeys: Set<String> = []
		let sessionKeyedDirectKeys = directKeys.filter { isSessionKeyed($0) }
		let sessionKeyedByOrigin = Dictionary(
			grouping: sessionKeyedDirectKeys, by: Self.origin(forWindowKey:))
		for (origin, keys) in sessionKeyedByOrigin {
			let states: [String: ActivityState] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.activityState
			}
			let updatedAt: [String: String] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.updatedAt
			}
			let cap = resolvedSessionCap(for: origin)
			let currentlyRendered = slotOccupants.intersection(keys)
			let selection = SessionSelectionPolicy.select(
				sessions: states, cap: cap, currentlyRendered: currentlyRendered,
				updatedAt: updatedAt,
				incumbentsProtected: !currentCustomization.evictSessionPetsEnabled,
				restrictNewPromotionsToInFlight: prunedOrigins.contains(origin))
			slotOccupants.subtract(keys)
			slotOccupants.formUnion(selection.rendered)
			genuinelyEvictedKeys.formUnion(currentlyRendered.subtracting(selection.rendered))
			pendingWindowKeys.formUnion(selection.pending)
			// Capture each evicted ("non-active") session's on-screen frame right
			// before Step 7 tears its window down, so the next session window(s)
			// spawned for this origin (the "active" incomer(s) that won the slot)
			// can inherit them. Only fires on the tick a rendered key actually
			// transitions to pending — `windows[key]` is already nil on later
			// ticks once Step 7 has removed it, so this never re-captures a
			// window that no longer exists. Appended, not overwritten: lowering
			// a session cap by more than 1 can evict several siblings in the
			// same tick, and every one of their frames must survive to be
			// claimed, not just the last one iterated from `selection.pending`
			// (a Set, with no defined iteration order).
			for key in selection.pending where windows[key] != nil {
				evictedSessionFrames[origin, default: []].append(windows[key]!.currentFrame)
			}
			guard selection.blocked else { continue }
			computedBlockedOrigins.insert(origin)
			let candidates = firstSeenAt.filter { currentlyRendered.contains($0.key) }
			let freshTarget = ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: candidates)

			// If the bubble's current host window died for a reason other than
			// resolution (TTL expiry, mode switch, the pending path, manual
			// prune) while this origin is still blocked, the bubble silently
			// vanished with it — `windows[existingTarget]` is nil even though
			// the conflict never went away. Re-home it onto the current
			// longest-lived live window immediately: this is the same ongoing
			// conflict continuing to display, not a new one, so it must not
			// consume or extend the one-hour rate limit (see P15.08
			// advisory-observation triage).
			if let existingTarget = activeConflictBubbleTargets[origin], windows[existingTarget] == nil {
				if let freshTarget {
					activeConflictBubbleTargets[origin] = freshTarget
					windows[freshTarget]?.applyConflictBubble(ConflictBubblePayload(origin: origin))
				} else {
					activeConflictBubbleTargets.removeValue(forKey: origin)
				}
				continue
			}

			// P15.08: fire the conflict bubble on the longest-lived
			// currently-rendered session, subject to the per-platform rate
			// limit — this signal is recomputed fresh every tick, so without
			// the rate limiter a persisting conflict would re-front the
			// bubble every tick.
			guard conflictBubbleRateLimiter.shouldShow(origin: origin, now: currentTime) else { continue }
			guard let freshTarget else { continue }
			conflictBubbleRateLimiter.recordShown(origin: origin, now: currentTime)
			activeConflictBubbleTargets[origin] = freshTarget
			windows[freshTarget]?.applyConflictBubble(ConflictBubblePayload(origin: origin))
		}
		// A hidden key that genuinely loses the cap fight (P15.07-QC) must not
		// linger in `userHiddenWindowKeys` — otherwise the menu keeps offering
		// "Show <pet>" for a session that no longer holds a slot, and clicking
		// it clears the hidden flag without spawning a window (nor leaving any
		// trace in `activeOrigins` either), silently vanishing from the menu
		// entirely. Dropping the flag here reverts the key to plain
		// cap-pending — invisible in the menu, exactly like any other session
		// that was never hidden and is merely held by cap pressure, and it
		// re-appears on its own the moment it legitimately wins a slot back.
		let hiddenKeysBeforePurge = userHiddenWindowKeys
		userHiddenWindowKeys.subtract(genuinelyEvictedKeys)
		if userHiddenWindowKeys != hiddenKeysBeforePurge {
			hiddenKeysSaver(userHiddenWindowKeys)
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
				// P15.07 slot inheritance: if a sibling session of this origin was
				// just session-cap-evicted, this newly-spawned session takes over
				// its exact on-screen location and size instead of the default spot.
				// FIFO: several evictions can queue up in one tick, and each
				// subsequent spawn for this origin claims the next one in line.
				if var queued = evictedSessionFrames[origin], !queued.isEmpty {
					let inheritedFrame = queued.removeFirst()
					if queued.isEmpty {
						evictedSessionFrames.removeValue(forKey: origin)
					} else {
						evictedSessionFrames[origin] = queued
					}
					controller.adoptFrame(inheritedFrame)
				}
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
			// A session-keyed window's own badge already synthesizes "Session N"
			// when unrenamed (`sessionLabel` nil is the right signal there); a
			// plain-origin window has no such built-in default, so it falls back
			// to the platform's display name here instead.
			let userLabel = sessionLabel(forWindowKey: renderKey)
			let resolvedLabel =
				isSessionKeyed(renderKey) ? userLabel : (userLabel ?? Self.defaultSessionLabel(forOrigin: origin))
			windows[renderKey]?.applySessionLabel(resolvedLabel)
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
					let combinedDefaultOrigin: String
					if winner.activityState == .idle {
						windows["combined"]?.applyPlatform(origin: "combined")
						combinedDefaultOrigin = "combined"
					} else if let sourceOrigin = winner.sourceEvent?.origin {
						windows["combined"]?.applyPlatform(origin: sourceOrigin)
						combinedDefaultOrigin = sourceOrigin
					} else {
						combinedDefaultOrigin = "combined"
					}
					// The combined window is never session-keyed (no session number —
					// `sessionNumber(forWindowKey:)` already guards that; nothing to
					// apply here), but it now gets a session-label badge too (P??
					// unification): the user's rename if set, else whichever platform
					// is currently driving the shared pet ("Default" while idle).
					windows["combined"]?.applySessionLabel(
						sessionLabel(forWindowKey: "combined")
							?? Self.defaultSessionLabel(forOrigin: combinedDefaultOrigin))
					windows["combined"]?.applySessionTooltip(nil)
				}
			}
		} else if combinedModeOrigins().isEmpty {
			// No origin is assigned to combined mode anymore — the shared window is
			// unconditionally obsolete, exactly like Step 5a's off-mode dismissal, and
			// must exit regardless of TTL or last-active status. Gating this on
			// last-active (as the transient-gap branch below does) let a genuine
			// mode-switch-away lose to a same-tick timestamp tie in the last-active
			// election: when the user flips combined→own/minimalist without any new
			// agent activity in between, the freshly-added directly-keyed render key
			// can carry the exact same updated_at as the stale "combined" entry
			// already in lastUpdatedAt, and Swift's max(by:) tie-break is
			// Dictionary-iteration-order dependent — so "combined" could keep
			// last-active immunity and never be dismissed.
			if windows["combined"] != nil {
				windows["combined"]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: "combined")
			}
		} else {
			// At least one origin is still assigned to combined mode; this tick's
			// snapshot simply has no combined-folded session present (a transient
			// polling gap), so the usual TTL/last-active immunity still applies —
			// dismissing here would flash the window off on any single gapped tick.
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
	/// Deliberately never touches `slotOccupants` (P15.07-QC): hide/show is a
	/// pure visibility toggle on an otherwise-unchanged session, not a cap
	/// release, so a hidden session keeps its slot reserved and un-hiding it
	/// respawns on the very next tick without competing for a new one.
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
		// Write-through on every toggle rather than only on app exit: a force-quit
		// or crash skips exit hooks entirely, which is a normal way this app dies.
		hiddenKeysSaver(userHiddenWindowKeys)
	}

	/// Returns the controller for the given window key. Used by MenubarApp to wire
	/// per-window callbacks (attention dismiss, app-nap opt-out).
	func controller(for key: String) -> FloatingPetWindowControlling? { windows[key] }

	/// Drops hidden window keys whose backing `state.d/` slice no longer
	/// exists on disk. `SlicePruner` deletes slices 24h after their last
	/// write, at which point the key's "Show … Pet" menu entry is a lie —
	/// `refreshForShow` has nothing left to rewrite, so Show would silently
	/// do nothing. Called by the menu just before it opens (via
	/// `MenubarMenu`'s `menuWillOpen` hook), so a zombie entry is culled at
	/// exactly the moment it would otherwise be displayed.
	///
	/// Matching is filename-authoritative via
	/// `StateJsonReader.parseSliceFilename` — the same parse `SlicePruner`'s
	/// own orphan-label sweep uses — so the two "does this session still have
	/// any trace on disk?" answers can never disagree. A session-keyed hidden
	/// key needs its exact `origin:session_id.json`; a plain-origin key
	/// survives while any slice of that origin exists; the literal
	/// `"combined"` key survives while any current combined-mode origin has a
	/// slice. The trimmed set is persisted so a culled key does not
	/// resurrect on relaunch.
	func pruneHiddenKeysWithoutBackingSlice(stateDirectory: String) {
		guard !userHiddenWindowKeys.isEmpty else { return }
		let names = (try? FileManager.default.contentsOfDirectory(atPath: stateDirectory)) ?? []
		var liveOrigins: Set<String> = []
		var liveSessionKeys: Set<String> = []
		for name in names {
			guard let (origin, sessionId) = StateJsonReader.parseSliceFilename(name) else { continue }
			liveOrigins.insert(origin)
			liveSessionKeys.insert(makeSessionKey(origin: origin, sessionId: sessionId))
		}
		let combinedOrigins = Set(combinedModeOrigins())
		let survivors = userHiddenWindowKeys.filter { key in
			if key == "combined" {
				return !liveOrigins.isDisjoint(with: combinedOrigins)
			}
			if let identity = Self.sessionIdentity(forWindowKey: key) {
				return liveSessionKeys.contains(
					makeSessionKey(origin: identity.origin, sessionId: identity.sessionId))
			}
			return liveOrigins.contains(key)
		}
		guard survivors.count != userHiddenWindowKeys.count else { return }
		userHiddenWindowKeys = survivors
		hiddenKeysSaver(userHiddenWindowKeys)
	}

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
		prunedOrigins.insert(identity.origin)
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

	/// Hides the visible attention bubble on every currently active window that
	/// shares `windowKey`'s owning platform. With session pets on, Focus can
	/// only foreground the platform app as a whole — there is no way to raise
	/// one specific agent thread — so a Focus or dismiss click on any one
	/// session's bubble must clear every sibling session's bubble too, not
	/// just the one clicked. Callers pair this with a `StateJsonWriter` write
	/// that idles every sibling's `state.d/` slice so the bubbles do not
	/// reappear on the next poll tick.
	func clearAttentionBubbles(sharingOriginWith windowKey: String) {
		let owningOrigin = Self.origin(forWindowKey: windowKey)
		for key in windows.keys where Self.origin(forWindowKey: key) == owningOrigin {
			windows[key]?.applyAttention(payload: nil, sourceEvent: nil)
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

	/// The user's rename override for `windowKey`, or `nil` if never renamed.
	/// `windowKey` doubles as the `SessionLabelStore` key regardless of shape
	/// (`"origin:session_id"`, a plain origin, or the literal `"combined"`),
	/// so no identity lookup is needed here. Unlike `sessionNumber`, this is
	/// not restricted to session-keyed windows — a plain-origin/"combined"
	/// window can be renamed too (P?? unification); see
	/// `defaultSessionLabel(forOrigin:)` for what a plain-origin/"combined"
	/// window shows when it has never been renamed.
	func sessionLabel(forWindowKey key: String) -> String? {
		sessionLabelReader(key)
	}

	/// Fallback session-label text for a plain-origin/"combined" window that
	/// has never been renamed — the platform's own display name (e.g.
	/// "Claude Code", "VS Code"), so every platform now shows *some* label
	/// even with session-pets off, mirroring the "Session N" default a
	/// session-keyed window's badge already synthesizes on its own. Passing
	/// the literal `"combined"` origin (the folded window while idle, before
	/// any platform has driven it this tick) resolves to `PlatformAttribution
	/// .default.displayName`, "Default" — the same label already shown on
	/// its ⭐ platform chip.
	static func defaultSessionLabel(forOrigin origin: String) -> String? {
		PlatformAttribution(origin: origin)?.displayName
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
		let unlimited = isUnlimited(origin: identity.origin)
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
		let unlimited = isUnlimited(origin: identity.origin)
		sessionNumberAllocator.setUnlimited(unlimited, origin: identity.origin)
		sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
	}

	/// Whether `origin`'s current session cap is the Unlimited sentinel,
	/// resolving an absent cap to the shared default first (see
	/// `CustomizationSnapshot.defaultSessionCap`).
	private func isUnlimited(origin: String) -> Bool {
		resolvedSessionCap(for: origin) == CustomizationSnapshot.unlimitedSessionCap
	}

	/// `origin`'s session cap per `CustomizationSnapshot.sessionCap`'s documented
	/// contract: an absent entry OR a negative value resolves to the shared
	/// default (`CustomizationSnapshot.defaultSessionCap`); `0` (Unlimited) and
	/// positive values pass through unchanged. A negative value can only reach
	/// this map via manual `customization.json` editing today, but without this
	/// guard `SessionSelectionPolicy.select`'s `cap > 0` check would silently
	/// treat it as Unlimited rather than the documented default-3 fallback.
	private func resolvedSessionCap(for origin: String) -> Int {
		guard let cap = currentCustomization.sessionCap[origin], cap >= 0 else {
			return CustomizationSnapshot.defaultSessionCap
		}
		return cap
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

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
	typealias WindowFactory = (WindowKey, String) -> FloatingPetWindowControlling
	typealias MinimalistWindowFactory = (WindowKey) -> FloatingPetWindowControlling
	typealias CustomizationReader = () -> CustomizationSnapshot
	typealias AssignmentsReader = () -> AssignmentsSnapshot
	/// Reads a session's rename label given its window key.
	typealias SessionLabelReader = (WindowKey) -> String?
	/// Reads a session's last submitted prompt given its window key.
	typealias SessionPromptSummaryReader = (WindowKey) -> String?
	/// Reads a session's platform-auto-generated thread title given its
	/// `(origin, session_id)` identity, or `nil` when unsupported/unresolved.
	typealias SessionTitleReader = (String, String) -> String?
	/// Reads a session's previously-resolved thread title from the on-disk
	/// cache, given its window key, or `nil` when never cached. Consulted
	/// BEFORE `sessionTitleReader` so a relaunch doesn't repeat the disk/
	/// subprocess cost of the original resolution.
	typealias RetrievedSessionTitleReader = (WindowKey) -> String?
	/// Persists a freshly-resolved thread title to the on-disk cache, given
	/// its window key.
	typealias RetrievedSessionTitleWriter = (WindowKey, String) -> Void

	private let assignmentsReader: AssignmentsReader
	private let customizationReader: CustomizationReader
	private let windowFactory: WindowFactory
	private let minimalistWindowFactory: MinimalistWindowFactory?
	private let sessionLabelReader: SessionLabelReader
	private let sessionPromptSummaryReader: SessionPromptSummaryReader
	private let sessionTitleReader: SessionTitleReader
	private let retrievedSessionTitleReader: RetrievedSessionTitleReader
	private let retrievedSessionTitleWriter: RetrievedSessionTitleWriter
	private let now: () -> Date

	/// Active windows keyed by window key (the resolved render key, or `.combined`).
	private var windows: [WindowKey: FloatingPetWindowControlling] = [:]
	/// Tracks the `now()` clock time when each render key was last present in a snapshot (TTL clock).
	private var lastSeenAt: [WindowKey: Date] = [:]
	/// First-seen clock per render key — unlike `lastSeenAt` this is set once
	/// and never refreshed, so P15.08's target selector can always find the
	/// longest-lived currently-rendered session for a blocked origin.
	private var firstSeenAt: [WindowKey: Date] = [:]
	/// Tracks the most-recent snapshot `updated_at` per render key (used to elect lastActiveRenderKey).
	private var lastUpdatedAt: [WindowKey: Date] = [:]
	/// Render key whose snapshot `updated_at` is most recent across all tracked keys.
	private var lastActiveRenderKey: WindowKey? = nil
	/// Render key currently holding the RPG HUD under "Show HUD on Most Recent
	/// Pet" mode. Sticky: unlike `lastActiveRenderKey` (a plain every-tick
	/// max-`updated_at` election used for TTL immunity), this only re-elects
	/// when the current holder goes idle, drops out of eligibility, or hasn't
	/// been elected yet — so the HUD doesn't hop to a different pet mid-prompt
	/// just because a background session's slice ticked with a newer timestamp.
	private var hudBearingRenderKey: WindowKey? = nil
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
	private var currentRenderKeyIdentities: [WindowKey: RenderKeyIdentity] = [:]
	/// Identity captured at assign time for every window key that currently
	/// holds a session number, keyed independently of `currentRenderKeyIdentities`.
	/// `releaseSessionNumber` must read from here, not from the latest snapshot:
	/// once a session ends, its `state.d` slice is deleted and its identity
	/// drops out of `snapshot.renderKeyIdentities` on the very next tick, but the
	/// window itself lingers until its TTL expires. Releasing from the stale
	/// snapshot would silently no-op and leak the number under a bounded cap.
	private var windowSessionIdentities: [WindowKey: RenderKeyIdentity] = [:]
	/// Platform-auto-generated thread title resolved for each session-keyed
	/// window key, once found. This is the in-process hot cache only —
	/// `RetrievedSessionTitleStore` (via `retrievedSessionTitleReader`/
	/// `retrievedSessionTitleWriter`) is the on-disk cache that survives a
	/// relaunch, consulted first so a resolved title never needs to hit
	/// `sessionTitleReader`'s disk/subprocess cost twice. A `nil` result from
	/// both is retried every tick — the platform may not have titled the
	/// thread yet — but a resolved title, once found, is never re-fetched,
	/// since these titles rarely change after generation. This in-memory
	/// entry is cleared alongside `windowSessionIdentities` in
	/// `releaseSessionNumber`, but the on-disk entry is deliberately left in
	/// place — a hide/show or TTL-dismiss-then-respawn of the SAME session
	/// should still hit the disk cache rather than re-resolving from
	/// scratch. The on-disk entry only disappears via the same orphan-label
	/// sweep and manual "Prune Session" path that clean up
	/// `session-labels.json`.
	private var resolvedSessionTitles: [WindowKey: String] = [:]
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
	/// Session-keyed window keys blocked from rendering by
	/// `SessionSelectionPolicy`'s per-origin cap on the most recent tick
	/// (Step 6c below). Exposed so the menu bar's "Capped Sessions" panel can
	/// list them with a status-only affordance instead of a "Show" button:
	/// cap partitioning is recomputed from activity/rank every tick and
	/// ignores the hidden flag, so `setVisible(true, for:)` on one of these
	/// keys would silently no-op until it wins the rank fight on its own.
	private(set) var pendingSessionKeys: Set<WindowKey> = []
	/// Window keys the idle-dismiss TTL ("Hide Idle Pet After") is currently
	/// suppressing: visible in this tick's snapshot but past the TTL, so their
	/// window was torn down (or never re-spawned) at Steps 7/8. Recomputed
	/// fresh every tick, exactly like `pendingSessionKeys`. Exposed so
	/// `SessionsTabViewModel` can classify these as Active (hidden) — a pet
	/// the idle timer set aside is the same "still here, just concealed"
	/// concept as a user Hide, and both surfaces (Settings > Sessions and the
	/// menubar's Active Pets section) list it with a Show affordance rather
	/// than demoting it to the Live tier. Cap-pending keys are excluded even
	/// when also TTL-expired, so a capped session never leaks a Show button
	/// through this set.
	private(set) var ttlDismissedWindowKeys: Set<WindowKey> = []
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
	private var slotOccupants: Set<WindowKey> = []
	/// Rate-limits P15.08 conflict-bubble presentation to at most one fire per
	/// platform per hour — `blockedOrigins` is recomputed fresh every tick, so
	/// without this gate a persisting conflict would re-front the bubble on
	/// every tick, including right after the user dismissed it.
	private var conflictBubbleRateLimiter = ConflictBubbleRateLimiter()
	/// Window key currently showing the P15.08 conflict bubble for each
	/// blocked origin, so an origin that clears from `blockedOrigins` can be
	/// told to hide its bubble.
	private var activeConflictBubbleTargets: [String: WindowKey] = [:]
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

	/// One prompt-timer tracker per render key, observed from the polled slice
	/// on EVERY tick — before and regardless of the window teardown/spawn
	/// decisions below — so the timer keeps correct time across hide/show,
	/// idle-TTL dismiss, and session-cap de-render, including turn boundaries
	/// (a prompt ending and a new one starting) that occur while no window
	/// exists to display it. Windows only receive the resulting status to
	/// render. Bounded by the same eligibility filter as the other per-key
	/// bookkeeping; the literal "combined" key is exempted there and cleared
	/// when no combined entries remain (Step 8).
	private var promptTimers: [WindowKey: PromptTimerTracker] = [:]

	/// Window keys that currently have visible windows.
	var activeOrigins: [WindowKey] { Array(windows.keys).sorted { $0.rawValue < $1.rawValue } }

	/// Window keys explicitly hidden by the user via "Hide Pet". Excluded from spawning
	/// until the user explicitly shows them via "Show Pet".
	var hiddenWindowKeys: [WindowKey] {
		Array(userHiddenWindowKeys).sorted { $0.rawValue < $1.rawValue }
	}

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

	/// Platform origin whose `platform_modes` entry the right-click mode-switch
	/// affordance (Pet Mode ↔ Minimalist Mode) should rewrite for the window
	/// keyed `key`, or `nil` for the `.combined` window — that one flips
	/// `combined_minimalist_enabled` instead of any origin's mode. A
	/// session-keyed key resolves to its platform origin: mode is keyed
	/// per-origin, so the switch is platform-level and every sibling session
	/// panel of the same platform flips together.
	static func modeSwitchOrigin(forWindowKey key: WindowKey) -> String? {
		switch key {
		case .combined: return nil
		case .origin(let origin): return origin
		case .session(let origin, _): return origin
		}
	}

	private var userHiddenWindowKeys: Set<WindowKey> = []
	private let hiddenKeysSaver: (Set<WindowKey>) -> Void

	/// Mode that was active when each window (keyed by window key) was spawned.
	/// Used to detect own↔minimalist transitions so the stale window is torn
	/// down and the correct factory runs on the next spawn gate.
	private var windowSpawnedModes: [WindowKey: PlatformMode] = [:]
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
		// `SessionLabelStore`/`PromptAttentionReader` are still String-keyed
		// persistence/lookup stores (session-labels.json, the in-memory
		// prompt-attention map) — `.rawValue` converts at exactly that edge,
		// the same sanctioned-boundary pattern as `app-state.json`.
		sessionLabelReader: @escaping SessionLabelReader = { SessionLabelStore.label(for: $0.rawValue) },
		sessionPromptSummaryReader: @escaping SessionPromptSummaryReader = {
			PromptAttentionReader.summary(forSessionKey: $0.rawValue)
		},
		sessionTitleReader: @escaping SessionTitleReader = { origin, sessionId in
			SessionTitleResolver.title(forOrigin: origin, sessionId: sessionId)
		},
		// No production-disk defaults, unlike sessionLabelReader/sessionTitleReader
		// above (both read-only): the writer half of this pair writes through to
		// disk on every freshly-resolved title, and the test suite reuses the same
		// handful of session keys (e.g. "codex:s1") across dozens of tests that
		// don't override these two — a real-disk default here would let one test's
		// resolved title leak into every later test (in this run AND every future
		// run) that shares its key, and would silently pollute the developer's
		// real ~/.codogotchi/retrieved-session-labels.json. Mirrors the
		// hiddenKeysLoader/hiddenKeysSaver precedent below. Production wiring
		// happens explicitly in MenubarApp.
		retrievedSessionTitleReader: @escaping RetrievedSessionTitleReader = { _ in nil },
		retrievedSessionTitleWriter: @escaping RetrievedSessionTitleWriter = { _, _ in },
		// No production-disk defaults: unlike assignmentsReader/customizationReader
		// (read-only, idempotent), a hidden-keys default that wrote through to
		// AppStateStore would make every setVisible() call in the test suite — which
		// does not sandbox CODOGOTCHI_HOME — silently overwrite the developer's real
		// ~/.codogotchi/app-state.json. Production wiring happens explicitly in
		// MenubarApp.
		hiddenKeysLoader: @escaping () -> Set<WindowKey> = { [] },
		hiddenKeysSaver: @escaping (Set<WindowKey>) -> Void = { _ in },
		now: @escaping () -> Date = { Date() },
		idleEscalationEnvironment: [String: String] = ProcessInfo.processInfo.environment
	) {
		self.assignmentsReader = assignmentsReader
		self.customizationReader = customizationReader
		self.windowFactory = windowFactory
		self.minimalistWindowFactory = minimalistWindowFactory
		self.sessionLabelReader = sessionLabelReader
		self.sessionPromptSummaryReader = sessionPromptSummaryReader
		self.sessionTitleReader = sessionTitleReader
		self.retrievedSessionTitleReader = retrievedSessionTitleReader
		self.retrievedSessionTitleWriter = retrievedSessionTitleWriter
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

		// Step 3b: elect hudBearingRenderKey ("Show HUD on Most Recent Pet").
		// Re-elect only when the current holder is no longer in-flight (idle,
		// or an ActivityState the snapshot doesn't carry) or has fallen out of
		// eligibility (TTL-expired / never seen). Otherwise keep pointing at
		// the same render key regardless of what else updated this tick.
		let holderStillInFlight: Bool =
			if let key = hudBearingRenderKey, eligibleKeys.contains(key) {
				visibleEntries[key]?.activityState.isInFlight ?? false
			} else {
				false
			}
		if !holderStillInFlight, !eligibleForElection.isEmpty {
			hudBearingRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
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
		// "combined" is exempt: with unfolded per-origin input its tracker is
		// keyed by the literal "combined" while eligibility is per-origin, so
		// the filter would drop it every tick. Step 8 clears it explicitly when
		// no combined-folded entries remain.
		promptTimers = promptTimers.filter { eligibleKeys.contains($0.key) || $0.key == .combined }

		// Step 4: compute the key of the window that must not be dismissed
		let lastActiveWindowKey: WindowKey? = lastActiveRenderKey.map { windowKey(for: $0) }

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
		func isTTLExpired(windowKey: WindowKey) -> Bool {
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
		let directKeys = visibleEntries.keys.filter { windowKey(for: $0) != .combined }
			.sorted { $0.rawValue < $1.rawValue }
		let combinedKeys = visibleEntries.keys.filter { windowKey(for: $0) == .combined }

		// Step 6a: collapse directly-keyed windows whose owning origin switched to
		// combined mode. A key moving own/minimalist→combined must lose its own
		// window immediately so it doesn't render a second window alongside the
		// shared combined one. Iterates the pool's OWN window keys, not the
		// snapshot's: since P15.03 the driver pre-folds combined origins to the
		// literal "combined" key, so the stale window's key never appears in the
		// snapshot again and only the current customization can identify it. The
		// literal "combined" key IS the shared window, so it is never torn down here.
		let collapsedKeys = windows.keys.filter { $0 != .combined && windowKey(for: $0) == .combined }
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
			guard key != .combined else { return false }
			let origin = key.origin
			guard mode(for: origin) != .combined else { return false }
			let sessionsOn = currentCustomization.sessionPetsEnabled[origin] ?? false
			return key.isSessionKeyed != sessionsOn
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
			if !key.isSessionKeyed {
				let origin = key.origin
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
		var pendingWindowKeys: Set<WindowKey> = []
		var computedBlockedOrigins: Set<String> = []
		// Keys that genuinely lose the cap fight this tick (were an occupant,
		// no longer are) get their hidden flag cleared below — see the
		// `userHiddenWindowKeys.subtract` call after this loop.
		var genuinelyEvictedKeys: Set<WindowKey> = []
		let sessionKeyedDirectKeys = directKeys.filter { $0.isSessionKeyed }
		let sessionKeyedByOrigin = Dictionary(grouping: sessionKeyedDirectKeys, by: \.origin)
		for (origin, keys) in sessionKeyedByOrigin {
			let states: [WindowKey: ActivityState] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.activityState
			}
			let updatedAt: [WindowKey: String] = keys.reduce(into: [:]) { acc, key in
				acc[key] = visibleEntries[key]?.updatedAt
			}
			let cap = resolvedSessionCap(for: origin)
			let currentlyRendered = slotOccupants.intersection(keys)
			let selection = SessionSelectionPolicy.select(
				sessions: states, cap: cap, currentlyRendered: currentlyRendered,
				updatedAt: updatedAt,
				incumbentsProtected: !currentCustomization.evictSessionPetsEnabled,
				// Explicitly-hidden keys are pinned: an intentional "Hide Pet"
				// must never lose its slot to passive cap eviction, even with
				// "Evict Session Pets" enabled — the user set that session
				// aside to revisit, and eviction would silently discard it
				// (the genuinelyEvictedKeys purge below drops the hidden flag).
				pinnedKeys: userHiddenWindowKeys.intersection(keys),
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
		pendingSessionKeys = pendingWindowKeys
		// Clear the conflict bubble for any origin that resolved this tick —
		// promotion (P15.07) freed the withheld slot, so the conflict no
		// longer applies. The one-hour rate limit is untouched by this clear.
		for (origin, targetKey) in activeConflictBubbleTargets
		where !computedBlockedOrigins.contains(origin) {
			windows[targetKey]?.applyConflictBubble(nil)
			activeConflictBubbleTargets.removeValue(forKey: origin)
		}

		// Step 7: spawn / update directly-keyed windows
		var computedTtlDismissedKeys: Set<WindowKey> = []
		for renderKey in directKeys {
			guard let state = visibleEntries[renderKey] else { continue }
			// Feed the pool-owned prompt timer BEFORE any of the teardown/spawn
			// guards below can `continue`: a hidden, TTL-dismissed, or
			// cap-pending key must still observe every tick so turn boundaries
			// occurring while no window exists keep the timer honest.
			promptTimers[renderKey, default: PromptTimerTracker()].observe(
				state: state.activityState,
				updatedAt: state.updatedAt,
				sourceEvent: state.sourceEvent,
				attention: state.attention
			)
			// Idle past TTL: leave it dismissed and do not re-spawn from the lingering
			// idle slice (Step 5b already removed any window for it).
			if isTTLExpired(windowKey: renderKey) {
				// Record the suppression for `ttlDismissedWindowKeys` — unless
				// the key is also cap-pending, which must keep presenting as
				// Capped (status-only), never as a showable Active (hidden) row.
				if !pendingWindowKeys.contains(renderKey) {
					computedTtlDismissedKeys.insert(renderKey)
				}
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
			let origin = renderKey.origin
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
			windows[renderKey]?.applyPromptTimerStatus(promptTimers[renderKey]?.currentStatus())
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
			let assignedNumber = sessionNumber(forWindowKey: renderKey)
			windows[renderKey]?.applySessionNumber(assignedNumber)
			// Every window gets a label at render — the user's rename if set,
			// else a default: the platform's own auto-generated thread title
			// when resolvable, else "Session N" for a session-keyed window,
			// else the platform's display name for a plain-origin one. A
			// non-nil label is what gates the right-click "Rename…"
			// affordance, so the session-keyed default must be resolved here
			// rather than left to the badge view's own "Session N" synthesis.
			windows[renderKey]?.applySessionLabel(sessionDisplayLabel(forWindowKey: renderKey, origin: origin))
			windows[renderKey]?.applySessionTooltip(sessionPromptSummary(forWindowKey: renderKey))
		}

		// Step 8: spawn / update combined window
		if !combinedKeys.isEmpty {
			// Style toggle: if the existing combined window was spawned with the wrong
			// renderer for the current combinedMinimalistEnabled setting, tear it down so
			// the spawn gate below recreates it with the correct factory.
			if let combined = windows[.combined],
				combinedWindowIsMinimalist != currentCustomization.combinedMinimalistEnabled
			{
				combined.setFloatingPetVisible(false)
				windows.removeValue(forKey: .combined)
			}
			// Feed the shared pet's pool-owned prompt timer from the winning
			// (freshest-updated) folded entry BEFORE the TTL/hidden branches can
			// skip rendering — mirroring Step 7's observe-before-guards so the
			// combined timer stays honest while its window doesn't exist.
			let combinedEntries = combinedKeys.compactMap { key in
				visibleEntries[key].map { (key: key, state: $0) }
			}
			let winnerEntry = combinedEntries.max(by: { a, b in
				(StateJsonReader.parseISO8601Date(a.state.updatedAt) ?? .distantPast)
					< (StateJsonReader.parseISO8601Date(b.state.updatedAt) ?? .distantPast)
			})
			if let winner = winnerEntry?.state {
				promptTimers[.combined, default: PromptTimerTracker()].observe(
					state: winner.activityState,
					updatedAt: winner.updatedAt,
					sourceEvent: winner.sourceEvent,
					attention: winner.attention
				)
			}
			if isTTLExpired(windowKey: .combined) {
				// All combined-folded keys idle past TTL (and not last-active): dismiss
				// the shared window and do not re-spawn it this tick.
				computedTtlDismissedKeys.insert(.combined)
				if windows[.combined] != nil {
					windows[.combined]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: .combined)
				}
			} else if !userHiddenWindowKeys.contains(.combined) {
				if let winnerEntry {
					let winner = winnerEntry.state
					if windows[.combined] == nil {
						let useMinimalist = currentCustomization.combinedMinimalistEnabled
						let controller: FloatingPetWindowControlling
						if useMinimalist {
							guard let minimalistWindowFactory else {
								NSLog("FloatingPetWindowPool: combined-minimalist mode requires a minimalistWindowFactory")
								return
							}
							controller = minimalistWindowFactory(.combined)
						} else {
							let petId = currentAssignments.resolve(origin: "combined")
							controller = windowFactory(.combined, petId)
						}
						controller.setFloatingPetVisible(true)
						windows[.combined] = controller
						combinedWindowIsMinimalist = useMinimalist
					}
					windows[.combined]?.apply(state: winner.activityState, visualMode: .normal)
					windows[.combined]?.applyPromptTimerStatus(promptTimers[.combined]?.currentStatus())
					windows[.combined]?.applyAttention(
						payload: winner.attention,
						sourceEvent: winner.sourceEvent
					)
					// The combined window's gate badge follows whichever entry is
					// currently winning the shared pet, mirroring the platform-chip
					// precedent below. Badges are keyed by render key, so the winning
					// entry's key resolves for both pre-folded (`.combined`) and
					// unfolded (per-origin) input.
					windows[.combined]?.applyGateBadge(content: snapshot.gateBadges[winnerEntry.key])
					// While idle the combined window shows the persistent ⭐ Default badge;
					// when active it badges with whichever platform triggered the winning
					// state, matching the pre-phase-13 single-pet behavior.
					let combinedDefaultOrigin: String
					if winner.activityState == .idle {
						windows[.combined]?.applyPlatform(origin: "combined")
						combinedDefaultOrigin = "combined"
					} else if let sourceOrigin = winner.sourceEvent?.origin {
						windows[.combined]?.applyPlatform(origin: sourceOrigin)
						combinedDefaultOrigin = sourceOrigin
					} else {
						combinedDefaultOrigin = "combined"
					}
					// The combined window is never session-keyed (no session number —
					// `sessionNumber(forWindowKey:)` already guards that; nothing to
					// apply here), but it now gets a session-label badge too (P??
					// unification): the user's rename if set, else whichever platform
					// is currently driving the shared pet, or "Combined" while idle —
					// distinct from the platform chip's ⭐ "Default" text (still driven
					// by `applyPlatform(origin: "combined")` above), which names the
					// idle *pet assignment* slot, not this window itself.
					let idleDefaultLabel = combinedDefaultOrigin == "combined"
						? "Combined" : Self.defaultSessionLabel(forOrigin: combinedDefaultOrigin)
					windows[.combined]?.applySessionLabel(
						sessionLabel(forWindowKey: .combined) ?? idleDefaultLabel)
					windows[.combined]?.applySessionTooltip(nil)
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
			if windows[.combined] != nil {
				windows[.combined]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: .combined)
			}
			// The shared timer is as obsolete as the shared window — and the
			// eligibility filter above deliberately exempts `.combined`, so this
			// is the only place it gets cleared.
			promptTimers.removeValue(forKey: .combined)
		} else {
			// At least one origin is still assigned to combined mode; this tick's
			// snapshot simply has no combined-folded session present (a transient
			// polling gap), so the usual TTL/last-active immunity still applies —
			// dismissing here would flash the window off on any single gapped tick.
			if windows[.combined] != nil && .combined != lastActiveWindowKey {
				windows[.combined]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: .combined)
			}
		}

		ttlDismissedWindowKeys = computedTtlDismissedKeys

		// Step 9: broadcast RPG to all windows. Which window(s) actually show the
		// HUD overlay depends on the configured mode: "all" broadcasts true to
		// every open window (pre-existing behavior), "hidden" broadcasts false,
		// and "most_recent" enables only the sticky hudBearingRenderKey's window
		// (Step 3b), so a background pet never steals the HUD mid-prompt.
		let rpg = snapshot.rpgSnapshot
		let hudMode = PetConfig.resolvedRPGHUDMode()
		let hudBearingWindowKey = hudBearingRenderKey.map(windowKey(for:))
		for (key, controller) in windows {
			let hudEnabled: Bool
			switch hudMode {
			case .all: hudEnabled = true
			case .hidden: hudEnabled = false
			case .mostRecent: hudEnabled = key == hudBearingWindowKey
			}
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
	func isActive(for key: WindowKey) -> Bool { windows[key] != nil }

	/// Resets the pool-owned prompt timer for a window key in response to a
	/// live user action (Force Idle, attention-bubble dismiss). The panel
	/// clears its own displayed status immediately for instant feedback; this
	/// reset is what makes it stick — `PromptTimerTracker.reset(now:)` stamps
	/// the real current time so a next-tick poll that reads the pre-rewrite
	/// on-disk in-flight slice (racing the async idle rewrite) is treated as
	/// stale and cannot restart the timer.
	func resetPromptTimer(forWindowKey key: WindowKey) {
		promptTimers[key]?.reset()
	}

	/// Hides or shows the window for the given key.
	/// Hiding persists across update() ticks until setVisible(true) is called.
	/// Deliberately never touches `slotOccupants` (P15.07-QC): hide/show is a
	/// pure visibility toggle on an otherwise-unchanged session, not a cap
	/// release, so a hidden session keeps its slot reserved and un-hiding it
	/// respawns on the very next tick without competing for a new one.
	func setVisible(_ visible: Bool, for key: WindowKey) {
		if visible {
			userHiddenWindowKeys.remove(key)
			// Restart the in-memory idle-TTL clock alongside the on-disk
			// `refreshForShow` rewrite callers already perform: dropping the
			// entry makes the next tick re-seed it (`lastSeenAt == nil` →
			// full TTL grace window), so an explicit Show deterministically
			// respawns a TTL-dismissed pet. Without this, respawn hinged on
			// the refreshed slice winning the last-active election — which a
			// concurrently-working sibling session's newer updated_at wins
			// instead, leaving Show a silent no-op. Harmless for the literal
			// "combined" key (its TTL reads per-folded-render-key clocks;
			// there is no "combined" entry here to drop).
			lastSeenAt.removeValue(forKey: key)
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

	/// Hides every currently active window except `keepVisible` — the
	/// right-click "Hide All Other Pets" affordance, offered on every panel
	/// regardless of mode or session-keyed-ness. A snapshot action, not a
	/// persistent mode: only windows rendered at the moment this fires are
	/// hidden, with the same persist-until-shown semantics as
	/// `setVisible(false, for:)` (a single batched disk write here instead of
	/// one per window) — a session or platform that spawns afterward is
	/// untouched and renders normally.
	func hideAllOtherWindows(keepVisible: WindowKey) {
		let others = windows.keys.filter { $0 != keepVisible }
		guard !others.isEmpty else { return }
		for key in others {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			releaseSessionNumber(forWindowKey: key)
			userHiddenWindowKeys.insert(key)
		}
		hiddenKeysSaver(userHiddenWindowKeys)
	}

	/// Returns the controller for the given window key. Used by MenubarApp to wire
	/// per-window callbacks (attention dismiss, app-nap opt-out).
	func controller(for key: WindowKey) -> FloatingPetWindowControlling? { windows[key] }

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
		var liveSessionKeys: Set<WindowKey> = []
		for name in names {
			guard let (origin, sessionId) = StateJsonReader.parseSliceFilename(name) else { continue }
			liveOrigins.insert(origin)
			liveSessionKeys.insert(.session(origin: origin, id: sessionId))
		}
		let combinedOrigins = Set(combinedModeOrigins())
		let survivors = userHiddenWindowKeys.filter { key in
			if key == .combined {
				return !liveOrigins.isDisjoint(with: combinedOrigins)
			}
			if key.isSessionKeyed {
				return liveSessionKeys.contains(key)
			}
			return liveOrigins.contains(key.origin)
		}
		guard survivors.count != userHiddenWindowKeys.count else { return }
		let culled = userHiddenWindowKeys.subtracting(survivors)
		for key in culled {
			promptTimers.removeValue(forKey: key)
		}
		userHiddenWindowKeys = survivors
		hiddenKeysSaver(userHiddenWindowKeys)
	}

	/// Manual "Prune Session" (P15.07, right-click on a session-keyed window):
	/// tears down the panel and destroys its state.d slice, free-list number,
	/// session-labels.json key, and retrieved-session-labels.json cached
	/// title — the same end-state as automatic TTL expiry plus the orphan
	/// sweeps. No-op for a plain-origin/"combined" window, since those are
	/// never session-keyed. `stateDirectory` is the live `state.d/` path
	/// (`config.pollingTarget.path`), passed by the caller so this pool never
	/// hardcodes a filesystem location. `labelPath`/`retrievedTitlePath`
	/// default to the real sidecar file locations and exist as parameters
	/// purely so tests can redirect them, mirroring `sessionLabelReader`.
	func pruneSession(
		windowKey: WindowKey,
		stateDirectory: String,
		labelPath: String = SessionLabelStore.path(),
		retrievedTitlePath: String = RetrievedSessionTitleStore.path()
	) {
		guard windowKey.isSessionKeyed,
			let identity = windowSessionIdentities[windowKey] ?? currentRenderKeyIdentities[windowKey]
		else { return }
		windows[windowKey]?.setFloatingPetVisible(false)
		windows.removeValue(forKey: windowKey)
		windowSpawnedModes.removeValue(forKey: windowKey)
		windowSessionIdentities.removeValue(forKey: windowKey)
		resolvedSessionTitles.removeValue(forKey: windowKey)
		promptTimers.removeValue(forKey: windowKey)
		prunedOrigins.insert(identity.origin)
		// `SessionPruner.pruneSession(windowKey:)` is the sanctioned
		// slice-filename boundary (P16.04): it builds
		// `state.d/<windowKey>.json` and the `session-labels.json` /
		// `retrieved-session-labels.json` sidecar keys, which are still
		// String-keyed persistence formats — `.rawValue` converts at exactly
		// that edge.
		SessionPruner.pruneSession(
			windowKey: windowKey.rawValue,
			origin: identity.origin,
			sessionId: identity.sessionId,
			stateDirectory: stateDirectory,
			allocator: sessionNumberAllocator,
			labelPath: labelPath,
			retrievedTitlePath: retrievedTitlePath
		)
	}

	/// Live-swap the rendered pet for one origin's windows. Called when the user
	/// reassigns a platform badge in Settings > Pet so only that platform's windows
	/// update; other windows are untouched. Pet identity is per-origin, so ALL of
	/// the origin's session windows swap together (or its folded "combined"
	/// window when the origin is in combined mode). Newly spawned windows already
	/// pick up the current assignment via the factory's petId argument.
	func replacePet(origin: String, codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		let foldedKey = windowKey(for: .origin(origin))
		for key in windows.keys
		where key == foldedKey || key.origin == origin {
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
	func clearAttentionBubbles(sharingOriginWith windowKey: WindowKey) {
		let owningOrigin = windowKey.origin
		for key in windows.keys where key.origin == owningOrigin {
			windows[key]?.applyAttention(payload: nil, sourceEvent: nil)
		}
	}

	/// Session number assigned to `windowKey`, or `nil` for a plain-origin or
	/// "combined" window (session numbering only applies to session-keyed
	/// windows). Consumers (e.g. `MenubarApp` wiring the session badge) call
	/// this after a window is spawned/updated.
	func sessionNumber(forWindowKey key: WindowKey) -> Int? {
		guard key.isSessionKeyed, let identity = currentRenderKeyIdentities[key] else { return nil }
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
	func sessionLabel(forWindowKey key: WindowKey) -> String? {
		sessionLabelReader(key)
	}

	/// User-facing label for a window key, with the same precedence everywhere
	/// it is surfaced: explicit `session-labels.json` rename, then a retrieved
	/// platform title, then the numeric session fallback, then platform name.
	func sessionDisplayLabel(forWindowKey key: WindowKey, origin: String? = nil) -> String? {
		let resolvedOrigin = origin ?? key.origin
		let userLabel = sessionLabel(forWindowKey: key)
		let retrievedTitle = resolveSessionTitle(forWindowKey: key)
		let defaultLabel =
			retrievedTitle ?? sessionNumber(forWindowKey: key).map { "Session \($0)" }
				?? Self.defaultSessionLabel(forOrigin: resolvedOrigin)
		return userLabel ?? defaultLabel
	}

	/// Fallback session-label text for a plain-origin/"combined" window that
	/// has never been renamed — the platform's own display name (e.g.
	/// "Claude Code", "VS Code"), so every platform now shows *some* label
	/// even with session-pets off, mirroring the "Session N" default the
	/// pool resolves for an unrenamed session-keyed window. Passing
	/// the literal `"combined"` origin (the folded window while idle, before
	/// any platform has driven it this tick) resolves to `PlatformAttribution
	/// .default.displayName`, "Default" — the same label already shown on
	/// its ⭐ platform chip.
	static func defaultSessionLabel(forOrigin origin: String) -> String? {
		PlatformAttribution(origin: origin)?.displayName
	}

	/// Last submitted prompt for `windowKey`'s exact session, or `nil` for a
	/// plain-origin/"combined" window.
	func sessionPromptSummary(forWindowKey key: WindowKey) -> String? {
		guard key.isSessionKeyed else { return nil }
		return sessionPromptSummaryReader(key)
	}

	// MARK: - Private helpers

	private func mode(for origin: String) -> PlatformMode {
		currentCustomization.platformModes[origin] ?? .own
	}

	/// Assigns a session number for a newly-spawned session-keyed window and
	/// remembers the identity under `windowSessionIdentities` so a later
	/// `releaseSessionNumber` call — which may land well after this session's
	/// identity has dropped out of `currentRenderKeyIdentities` (TTL dismiss of
	/// an already-ended session) — can still resolve the correct
	/// (origin, sessionId) pair to free. No-op for plain-origin or "combined"
	/// windows.
	private func assignSessionNumber(forWindowKey key: WindowKey) {
		guard key.isSessionKeyed, let identity = currentRenderKeyIdentities[key] else { return }
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
	private func releaseSessionNumber(forWindowKey key: WindowKey) {
		guard key.isSessionKeyed, let identity = windowSessionIdentities.removeValue(forKey: key) else { return }
		resolvedSessionTitles.removeValue(forKey: key)
		let unlimited = isUnlimited(origin: identity.origin)
		sessionNumberAllocator.setUnlimited(unlimited, origin: identity.origin)
		sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
	}

	/// Resolves and caches `key`'s platform-auto-generated thread title (see
	/// `resolvedSessionTitles`), or `nil` for a plain-origin/"combined"
	/// window, or a session-keyed window the platform hasn't titled (yet, or
	/// ever, e.g. an unsupported origin). Checks the in-memory cache, then
	/// `RetrievedSessionTitleStore`'s on-disk cache (cheap — a JSON dict
	/// lookup, no directory walk or subprocess), before finally falling
	/// through to `sessionTitleReader` — resolution touches another app's
	/// on-disk storage, so a title once found (from either cache or a fresh
	/// resolve) is never re-fetched. A fresh resolve is written through to
	/// the on-disk cache so a later relaunch skips straight to the second
	/// check.
	private func resolveSessionTitle(forWindowKey key: WindowKey) -> String? {
		if let cached = resolvedSessionTitles[key] { return cached }
		guard key.isSessionKeyed, let identity = currentRenderKeyIdentities[key] else { return nil }
		if let persisted = retrievedSessionTitleReader(key) {
			resolvedSessionTitles[key] = persisted
			return persisted
		}
		guard let title = sessionTitleReader(identity.origin, identity.sessionId) else { return nil }
		resolvedSessionTitles[key] = title
		retrievedSessionTitleWriter(key, title)
		return title
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

	private func mode(forWindowKey key: WindowKey) -> PlatformMode {
		mode(for: key.origin)
	}

	/// THE single branch site mapping a render key to its window key: `.combined`
	/// itself and combined-mode origins fold to `.combined`; every other
	/// resolved key (`.origin` or `.session`) is its own window.
	private func windowKey(for renderKey: WindowKey) -> WindowKey {
		renderKey == .combined || mode(forWindowKey: renderKey) == .combined
			? .combined : renderKey
	}

	/// Most-recent lastSeenAt across all tracked render keys that map to this
	/// window key (several fold into `.combined`; every other key maps to itself).
	private func lastSeenForWindow(key: WindowKey) -> Date? {
		if key == .combined {
			return lastSeenAt
				.filter { windowKey(for: $0.key) == .combined }
				.values.max()
		}
		return lastSeenAt[key]
	}
}

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
/// `update()` is a straight composition of `PoolDerive.derive` (pure policy)
/// → `PoolDiff.diff` (mechanical) → `PoolApply.apply` (effects only). See
/// `apps/menubar/Sources/Pool/Derive/` for the pure fold and
/// `docs/product/delivery/phase-18/` for the program that replaced the old
/// imperative pipeline with this shape.
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

/// Coordinator: reads the environment fresh every tick, builds `PoolTickInput`,
/// runs `PoolDerive.derive` against its own threaded `PoolMemory`, diffs the
/// result against the previous tick's desired windows via `PoolDiff.diff`,
/// and applies the diff to real controllers via `PoolApply.apply`.
@MainActor
final class FloatingPetWindowPool {

	// MARK: - Driving state

	private var memory = PoolMemory()
	private var windows: [WindowKey: FloatingPetWindowControlling] = [:]
	private var desiredWindows: [WindowKey: DesiredWindow] = [:]
	/// A dismissed window's live frame, captured the tick it's torn down and
	/// consumed the tick a later spawn inherits it (`inheritedFrameFrom`).
	/// `PoolApply.apply`'s own donor-frame lookup only resolves a donor still
	/// present in `controllers` — correct for same-tick eviction+respawn, but
	/// `PoolMemory.evictedFrameDirectives` can legitimately queue a donor
	/// across several ticks (its own key already torn down and gone from
	/// `windows`), so this survives across ticks where `PoolApply`'s in-tick
	/// lookup cannot.
	private var evictedFrameSnapshots: [WindowKey: CGRect] = [:]
	private var lastDesired = DesiredWindows()
	private var lastAppliedIdleEscalationConfig: IdleEscalationConfig?

	// MARK: - Reader/config copies

	private let assignmentsReader: AssignmentsReader
	private let customizationReader: CustomizationReader
	private let windowFactory: WindowFactory
	private let minimalistWindowFactory: MinimalistWindowFactory?
	private let sessionLabelReader: SessionLabelReader
	private let sessionPromptSummaryReader: SessionPromptSummaryReader
	private let sessionTitleReader: SessionTitleReader
	private let retrievedSessionTitleReader: RetrievedSessionTitleReader
	private let retrievedSessionTitleWriter: RetrievedSessionTitleWriter
	private let hiddenKeysSaver: (Set<WindowKey>) -> Void
	private let now: () -> Date
	private let idleEscalationEnvironment: [String: String]
	private var currentAssignments: AssignmentsSnapshot = .safeDefault

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
		// have since TTL-expired are harmless here: `derive`'s eligibility
		// filtering only ever consults this set for keys already surviving this
		// tick's TTL/mode filtering, so restoration is implicitly "prune (by the
		// tick's own eligibility filtering), then restore" with no extra
		// bookkeeping needed.
		memory.userHiddenWindowKeys = hiddenKeysLoader()
	}

	// MARK: - update()

	func update(snapshot: PerPlatformSnapshot) {
		currentAssignments = assignmentsReader()
		let customization = customizationReader()
		let currentTime = now()

		var sessionLabels: [WindowKey: String] = [:]
		var knownSessionTitles: [WindowKey: String] = [:]
		var sessionPromptSummaries: [WindowKey: String] = [:]
		var keysNeedingInput = Set(snapshot.perPlatform.keys)
		for identity in snapshot.renderKeyIdentities.values {
			keysNeedingInput.insert(
				identity.sessionId == "default"
					? .origin(identity.origin)
					: .session(origin: identity.origin, id: identity.sessionId))
		}
		keysNeedingInput.insert(.combined)
		for key in keysNeedingInput {
			if let label = sessionLabelReader(key) { sessionLabels[key] = label }
			// In-memory cache first: a title resolved earlier this process run
			// must never be re-fetched, and the disk reader closure is not
			// required to be stateful (production wiring reads a real on-disk
			// cache; tests often inject a bare `{ _ in nil }`).
			if let title = memory.resolvedSessionTitles[key] ?? retrievedSessionTitleReader(key) {
				knownSessionTitles[key] = title
			}
			if key.isSessionKeyed, let summary = sessionPromptSummaryReader(key) {
				sessionPromptSummaries[key] = summary
			}
		}

		let input = PoolTickInput(
			snapshot: snapshot, customization: customization, assignments: currentAssignments,
			currentTime: currentTime, idleEscalationEnvironment: idleEscalationEnvironment,
			sessionLabels: sessionLabels, knownSessionTitles: knownSessionTitles,
			sessionPromptSummaries: sessionPromptSummaries, hudMode: PetConfig.resolvedRPGHUDMode())

		let (desired, newMemory) = PoolDerive.derive(input: input, memory: memory)
		memory = newMemory

		// Title resolution: read-through the on-disk cache, resolve+write-through
		// on a miss.
		let resolvedTitles = PoolApply.resolveTitles(
			requests: desired.titleResolutionRequests,
			readCachedTitle: { [retrievedSessionTitleReader] identity in
				retrievedSessionTitleReader(.session(origin: identity.origin, id: identity.sessionId))
			},
			resolveTitle: { [sessionTitleReader] identity in
				sessionTitleReader(identity.origin, identity.sessionId)
			},
			writeCachedTitle: { [retrievedSessionTitleWriter] identity, title in
				retrievedSessionTitleWriter(.session(origin: identity.origin, id: identity.sessionId), title)
			})
		// Feed straight into the in-memory cache `derive` itself consults
		// (`memory.resolvedSessionTitles`). Without this, a title resolved via
		// the call above is invisible to `derive` until the disk reader closure
		// independently reflects it, which a stateless test double (or a slow
		// write) never does — the in-memory cache must be the source of truth
		// on the very next tick, not just the disk.
		for (identity, title) in resolvedTitles {
			memory.resolvedSessionTitles[.session(origin: identity.origin, id: identity.sessionId)] = title
		}

		// A window desired as minimalist with no injected `minimalistWindowFactory`
		// must fail closed (skip spawning entirely) — never silently render it
		// through the wrong renderer. `PoolApply.apply`'s spawn closure returns
		// non-optional, so the filtering happens here, before either engine ever
		// sees the key.
		var diff = PoolDiff.diff(desired: desired, current: desiredWindows)
		if minimalistWindowFactory == nil {
			for (key, window) in diff.toSpawn where window.isMinimalist {
				NSLog("FloatingPetWindowPool: minimalist mode requires a minimalistWindowFactory for \(key)")
				diff.toSpawn.removeValue(forKey: key)
			}
			for (key, window) in diff.toUpdate where window.isMinimalist {
				diff.toUpdate.removeValue(forKey: key)
				diff.toDismiss.insert(key)
			}
		}

		// Snapshot which windows already existed BEFORE this tick's spawns: a
		// freshly-spawned window must never also receive a redundant
		// `updateIdleEscalationConfig` call in the same tick (it already starts
		// current via its factory).
		let alreadyOpenKeys = Set(windows.keys)
		let configChangedThisTick = desired.idleEscalationConfig != lastAppliedIdleEscalationConfig
		lastAppliedIdleEscalationConfig = desired.idleEscalationConfig

		// Capture every about-to-be-dismissed window's live frame BEFORE
		// `apply` removes its controller — the cross-tick half of the frame-
		// inheritance fix; see `evictedFrameSnapshots`'s doc comment.
		for key in diff.toDismiss {
			if let frame = windows[key]?.currentFrame {
				evictedFrameSnapshots[key] = frame
			}
		}

		PoolApply.apply(diff: diff, controllers: &windows) { [windowFactory, minimalistWindowFactory] key, window in
			if window.isMinimalist, let minimalistWindowFactory {
				return minimalistWindowFactory(key)
			}
			return windowFactory(key, window.petId ?? "")
		}

		// Fallback for a donor already gone BEFORE this tick started (cross-
		// tick eviction→respawn gap) — skip any donor dismissed THIS tick:
		// `PoolApply.apply`'s own in-tick lookup (donor still in `controllers`
		// when the spawn runs, captured before its own teardown loop) already
		// resolved and applied those; calling `adoptFrame` again here would
		// double-push the same frame.
		for (key, window) in diff.toSpawn {
			guard let donorKey = window.inheritedFrameFrom, !diff.toDismiss.contains(donorKey) else { continue }
			guard let controller = windows[key] else { continue }
			guard let snapshot = evictedFrameSnapshots.removeValue(forKey: donorKey) else { continue }
			controller.adoptFrame(snapshot)
		}
		// Bounded by `PoolMemory.evictedFrameDirectives`'s own FIFO draining —
		// a donor key already claimed by a spawn is removed above; a donor
		// key still queued (not yet claimed) must survive here for a later
		// tick, so this only prunes keys no live directive can still reach.
		let reachableDonorKeys = Set(memory.evictedFrameDirectives.values.flatMap { $0 })
		evictedFrameSnapshots = evictedFrameSnapshots.filter { reachableDonorKeys.contains($0.key) }

		// `current` for next tick's diff: exactly the keys that actually have a
		// real controller after `apply` — excludes any key `PoolApply` was
		// never asked to spawn/update above (the fail-closed filter).
		desiredWindows = desired.windows.filter { windows[$0.key] != nil }

		if configChangedThisTick {
			for key in alreadyOpenKeys {
				windows[key]?.updateIdleEscalationConfig(desired.idleEscalationConfig)
			}
		}
		if let monochromeChanged = desired.monochromeChanged {
			onMonochromeChanged?(monochromeChanged)
		}
		if let hiddenToPersist = desired.hiddenWindowKeysToPersist {
			hiddenKeysSaver(hiddenToPersist)
		}
		lastDesired = desired
	}

	// MARK: - Public surface: reads

	var resolvedIdleEscalationConfig: IdleEscalationConfig { lastDesired.idleEscalationConfig }
	var blockedOrigins: Set<String> { lastDesired.blockedOrigins }
	var pendingSessionKeys: Set<WindowKey> { lastDesired.pendingSessionKeys }
	var ttlDismissedWindowKeys: Set<WindowKey> { lastDesired.ttlDismissedWindowKeys }
	/// Window keys that currently have visible windows.
	var activeOrigins: [WindowKey] { Array(windows.keys).sorted { $0.rawValue < $1.rawValue } }
	/// Window keys explicitly hidden by the user via "Hide Pet". Excluded from
	/// spawning until the user explicitly shows them via "Show Pet".
	var hiddenWindowKeys: [WindowKey] {
		Array(memory.userHiddenWindowKeys).sorted { $0.rawValue < $1.rawValue }
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
	/// Returns true when the window for the given key is currently spawned.
	func isActive(for key: WindowKey) -> Bool { windows[key] != nil }
	/// Returns the controller for the given window key. Used by MenubarApp to wire
	/// per-window callbacks (attention dismiss, app-nap opt-out).
	func controller(for key: WindowKey) -> FloatingPetWindowControlling? { windows[key] }
	func sessionNumber(forWindowKey key: WindowKey) -> Int? { memory.sessionNumbers[key] }
	/// The user's rename override for `windowKey`, or `nil` if never renamed.
	/// `windowKey` doubles as the `SessionLabelStore` key regardless of shape
	/// (`"origin:session_id"`, a plain origin, or the literal `"combined"`),
	/// so no identity lookup is needed here.
	func sessionLabel(forWindowKey key: WindowKey) -> String? { sessionLabelReader(key) }
	func sessionDisplayLabel(forWindowKey key: WindowKey, origin: String? = nil) -> String? {
		lastDesired.windows[key]?.sessionLabel
	}
	/// Fallback session-label text for a plain-origin/"combined" window that
	/// has never been renamed — the platform's own display name (e.g.
	/// "Claude Code", "VS Code"), so every platform now shows *some* label
	/// even with session-pets off, mirroring the "Session N" default resolved
	/// for an unrenamed session-keyed window. Passing the literal "combined"
	/// origin (the folded window while idle, before any platform has driven
	/// it this tick) resolves to `PlatformAttribution.default.displayName`,
	/// "Default" — the same label already shown on its ⭐ platform chip.
	static func defaultSessionLabel(forOrigin origin: String) -> String? {
		PlatformAttribution(origin: origin)?.displayName
	}
	/// Last submitted prompt for `windowKey`'s exact session, or `nil` for a
	/// plain-origin/"combined" window.
	func sessionPromptSummary(forWindowKey key: WindowKey) -> String? {
		guard key.isSessionKeyed else { return nil }
		return sessionPromptSummaryReader(key)
	}

	// MARK: - User actions (immediate pure `PoolMemory` transitions paired with
	// the immediate real-window effect — no event queue, no 1-tick lag)

	/// Resets the pool-owned prompt timer for a window key in response to a
	/// live user action (Force Idle, attention-bubble dismiss). The panel
	/// clears its own displayed status immediately for instant feedback; this
	/// reset is what makes it stick.
	func resetPromptTimer(forWindowKey key: WindowKey) {
		memory = memory.resettingPromptTimer(for: key)
	}

	/// Hides or shows the window for the given key.
	/// Hiding persists across update() ticks until setVisible(true) is called.
	/// Deliberately never touches slot occupancy: hide/show is a pure
	/// visibility toggle on an otherwise-unchanged session, not a cap
	/// release, so a hidden session keeps its slot reserved and un-hiding it
	/// respawns on the very next tick without competing for a new one.
	func setVisible(_ visible: Bool, for key: WindowKey) {
		memory = visible ? memory.showing(key) : memory.hiding(key)
		if !visible {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			// `PoolDiff.diff` treats a key present in both `desired` and
			// `current` as an update, not a spawn — leaving a stale entry here
			// after removing the real controller above would silently drop the
			// respawn push the next time this key is desired (no controller to
			// push to, no spawn triggered either).
			desiredWindows.removeValue(forKey: key)
			// `sessionDisplayLabel`/other `lastDesired`-backed readers must not
			// keep returning this key's stale last-tick label after an
			// out-of-band teardown.
			lastDesired.windows.removeValue(forKey: key)
		}
		hiddenKeysSaver(memory.userHiddenWindowKeys)
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
		memory = memory.hidingAllOthers(keeping: keepVisible, among: Set(windows.keys))
		for key in others {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			desiredWindows.removeValue(forKey: key)
			lastDesired.windows.removeValue(forKey: key)
		}
		hiddenKeysSaver(memory.userHiddenWindowKeys)
	}

	/// Manual "Prune Session" (P15.07, widened in P19.02 to every window
	/// backed by a resolved session):
	/// tears down the panel and destroys its state.d slice, free-list number,
	/// session-labels.json key, and retrieved-session-labels.json cached
	/// title — the same end-state as automatic TTL expiry plus the orphan
	/// sweeps. `stateDirectory` is the live `state.d/` path
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
		guard let resolvedIdentity = lastDesired.windows[windowKey]?.resolvedIdentity else { return }
		let identity: (origin: String, sessionId: String)
		switch resolvedIdentity {
		case .session(let origin, let sessionId):
			identity = (origin, sessionId)
		case .origin(let origin):
			identity = (origin, "default")
		case .combined:
			return
		}
		memory = memory.pruning(windowKey)
		windows[windowKey]?.setFloatingPetVisible(false)
		windows.removeValue(forKey: windowKey)
		desiredWindows.removeValue(forKey: windowKey)
		lastDesired.windows.removeValue(forKey: windowKey)
		// `memory.pruning(windowKey)` above already released the session
		// number from `memory.sessionNumberAllocator` (a value type) —
		// `SessionPruner` requires the legacy reference-type allocator only for
		// its own disk-deletion side effects, so a fresh throwaway instance is
		// passed here: its `.release` call is a guaranteed no-op (nothing was
		// ever assigned on it), never double-releasing the real number.
		SessionPruner.pruneSession(
			windowKey: resolvedIdentity.rawValue, origin: identity.origin, sessionId: identity.sessionId,
			stateDirectory: stateDirectory, allocator: SessionNumberAllocator(),
			labelPath: labelPath, retrievedTitlePath: retrievedTitlePath)
	}

	/// Live-swap the rendered pet for one origin's windows. Called when the user
	/// reassigns a platform badge in Settings > Pet so only that platform's windows
	/// update; other windows are untouched. Pet identity is per-origin, so ALL of
	/// the origin's session windows swap together (or its folded "combined"
	/// window when the origin is in combined mode). Newly spawned windows already
	/// pick up the current assignment via the factory's petId argument.
	func replacePet(origin: String, codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		for key in windows.keys where key.origin == origin || (key == .combined) {
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
		guard !memory.userHiddenWindowKeys.isEmpty else { return }
		let names = (try? FileManager.default.contentsOfDirectory(atPath: stateDirectory)) ?? []
		var liveOrigins: Set<String> = []
		var liveSessionKeys: Set<WindowKey> = []
		for name in names {
			guard let (origin, sessionId) = StateJsonReader.parseSliceFilename(name) else { continue }
			liveOrigins.insert(origin)
			liveSessionKeys.insert(.session(origin: origin, id: sessionId))
		}
		let combinedOrigins = Set(combinedModeOrigins())
		let survivors = memory.userHiddenWindowKeys.filter { key in
			if key == .combined {
				return !liveOrigins.isDisjoint(with: combinedOrigins)
			}
			if key.isSessionKeyed {
				return liveSessionKeys.contains(key)
			}
			return liveOrigins.contains(key.origin)
		}
		guard survivors.count != memory.userHiddenWindowKeys.count else { return }
		memory.userHiddenWindowKeys = survivors
		hiddenKeysSaver(memory.userHiddenWindowKeys)
	}
}

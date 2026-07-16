import Foundation

/// Pure, `Equatable` fold state for `PoolDerive.derive` — the value-type home
/// for the cross-tick mutables `FloatingPetWindowPool` currently stores
/// directly on itself. See each field's doc comment for the exact
/// `FloatingPetWindowPool` stored property it replaces.
///
/// P18.01 wired only the fields Steps 1–5b and the eligibility-bounding block
/// need: the TTL/first-seen/last-updated clocks and the two elections. P18.02
/// adds selection/collapse state (slot occupancy, pruned origins, hidden
/// keys, spawned modes, evicted-frame FIFO, the session-number allocator, and
/// prompt-timer bookkeeping so the user-action transitions below have
/// something to act on) plus `previousDesiredWindowKeys` — the one piece of
/// cross-tick membership state a pure recompute-from-scratch fold needs that
/// the old imperative pipeline got for free from `windows` persisting across
/// ticks. Remaining push-spec state (conflict-bubble rate limiting/targets,
/// resolved session titles) arrives with P18.03. Each is additive: no field
/// defined here changes shape once a later ticket starts writing it.
struct PoolMemory: Equatable {
	/// TTL clock per render key — advances only while the key is doing work
	/// (`activityState != .idle`), seeded on first sight so a freshly-observed
	/// idle pet still gets a full TTL grace window. Mirrors
	/// `FloatingPetWindowPool.lastSeenAt`.
	var lastSeenAt: [WindowKey: Date] = [:]

	/// First-seen clock per render key — set once, never refreshed. Mirrors
	/// `FloatingPetWindowPool.firstSeenAt`.
	var firstSeenAt: [WindowKey: Date] = [:]

	/// Most-recent snapshot `updated_at` per render key, used to elect
	/// `lastActiveRenderKey`. Mirrors `FloatingPetWindowPool.lastUpdatedAt`.
	var lastUpdatedAt: [WindowKey: Date] = [:]

	/// Render key currently holding last-active TTL immunity. Mirrors
	/// `FloatingPetWindowPool.lastActiveRenderKey`.
	var lastActiveRenderKey: WindowKey?

	/// Sticky RPG-HUD-bearer render key ("Show HUD on Most Recent Pet"):
	/// re-elects only when the current holder drops out of eligibility or is
	/// no longer in-flight. Mirrors `FloatingPetWindowPool.hudBearingRenderKey`.
	var hudBearingRenderKey: WindowKey?

	// MARK: - P18.02: selection / collapse / user-action bookkeeping

	/// Session-keyed window keys that hold a cap slot (P15.07-QC), independent
	/// of whether a window is actually desired for them this tick. Diverges
	/// from `previousDesiredWindowKeys` exactly when a slot's window is
	/// user-hidden: hide/show only ever toggle `userHiddenWindowKeys`, never
	/// this set, so a hidden incumbent keeps its slot and un-hiding it
	/// respawns immediately with no fresh cap contention. The sole writer is
	/// Step 6c: each origin's `SessionSelectionPolicy.select` result replaces
	/// that origin's slice of this set every tick. Mirrors
	/// `FloatingPetWindowPool.slotOccupants`.
	var slotOccupants: Set<WindowKey> = []

	/// Origins that have had a manual "Prune Session" at least once this app
	/// session (P15.07-QC). Once armed, cap-selection only lets a
	/// non-rendered session newly promote into a freed slot while it is
	/// in-flight. Never cleared during the process lifetime. Mirrors
	/// `FloatingPetWindowPool.prunedOrigins`.
	var prunedOrigins: Set<String> = []

	/// Window keys explicitly hidden by the user via "Hide Pet" (or "Hide All
	/// Other Pets"). Excluded from `derive`'s desired-window construction
	/// until `showing(_:)` clears the flag. Mirrors
	/// `FloatingPetWindowPool.userHiddenWindowKeys`.
	var userHiddenWindowKeys: Set<WindowKey> = []

	/// Mode a currently-desired window was built under this tick, keyed by
	/// window key — recomputed fresh every tick from the current
	/// `PlatformMode`, never carried stale across a mode switch (a pure fold
	/// recomputing membership from scratch cannot exhibit the own↔minimalist
	/// stale-window bug `FloatingPetWindowPool.windowSpawnedModes` exists to
	/// detect and patch). Never contains the `.combined` key, matching the
	/// legacy field's own contract. Mirrors
	/// `FloatingPetWindowPool.windowSpawnedModes`.
	var windowSpawnedModes: [WindowKey: PlatformMode] = [:]

	/// Per-origin FIFO of the torn-down window key whose on-screen frame a
	/// later spawn for that origin should inherit. Two capture sites feed
	/// this: (1) session-cap eviction (Step 6c) — a rendered session losing
	/// its slot; (2) the plain-origin window torn down when session-pets is
	/// enabled for its origin (Step 6a2's enabling direction) — so the
	/// grandfathered session inherits the collapsed pet's exact slot. Never
	/// holds a fabricated `CGRect` — only the key to look the real frame up
	/// from at `apply` time. Drained in `derive`'s own deterministic order
	/// (never incidental `Set`/`Dictionary` iteration order — see this
	/// ticket's Review Focus). Mirrors
	/// `FloatingPetWindowPool.evictedSessionFrames`, keyed the same way.
	var evictedFrameDirectives: [String: [WindowKey]] = [:]

	/// The full set of window keys `derive` actually constructed a
	/// `DesiredWindow` for on the previous tick (i.e. excluding user-hidden
	/// keys, exactly like `FloatingPetWindowPool.windows.keys`). This is the
	/// one piece of state a pure recompute-from-scratch fold needs that the
	/// old imperative pipeline got for free from `windows` persisting across
	/// ticks: diffing this tick's freshly-computed membership against it is
	/// what detects "a window was just torn down" (to capture a
	/// grandfather-frame directive) and "a window is freshly spawning" (to
	/// drain one, and to know whether a session number needs
	/// assigning/releasing) — see `PoolDerive`'s Rationale note on why a
	/// diffed value replaces the old step-by-step imperative teardown
	/// detection (Steps 5a/6a/6a2/6b) outright.
	var previousDesiredWindowKeys: Set<WindowKey> = []

	/// Free-list session-number allocator, keyed per-origin internally. See
	/// `SessionNumberAllocatorState`. Mirrors
	/// `FloatingPetWindowPool.sessionNumberAllocator`, converted to a value
	/// type per this ticket's Outcome.
	var sessionNumberAllocator = SessionNumberAllocatorState()

	/// Identity captured at assign time for every window key that currently
	/// holds a session number, keyed independently of the current tick's
	/// `PoolTickInput.snapshot.renderKeyIdentities`. Every release must read
	/// from here, not from the latest snapshot: once a session ends, its
	/// identity drops out of the snapshot before the window itself is torn
	/// down (TTL grace), and releasing from the stale/absent snapshot would
	/// silently no-op and leak the number under a bounded cap. Mirrors
	/// `FloatingPetWindowPool.windowSessionIdentities`.
	var windowSessionIdentities: [WindowKey: RenderKeyIdentity] = [:]

	/// One prompt-timer tracker per render key, observed every tick so the
	/// timer keeps correct time across hide/show, idle-TTL dismiss, and
	/// session-cap de-render exactly like the legacy tracker. `PoolDerive`
	/// reads these trackers when emitting `DesiredWindow.promptTimerStatus`.
	/// Also the target of the pure `resettingPromptTimer(for:)` user-action
	/// transition. Mirrors `FloatingPetWindowPool.promptTimers`.
	var promptTimers: [WindowKey: PromptTimerTracker] = [:]

	/// Last-known winning-session identity per render key, for prompt-timer
	/// continuity only. A folded render key (`.origin(origin)` with
	/// sessions off, or `.combined`) can have a DIFFERENT session win it
	/// tick to tick — `PoolTickInput.snapshot.renderKeyIdentities` names
	/// whichever session currently does. `PromptTimerTracker.observe`
	/// only restarts on an idle/session_start/first-observation activity
	/// transition (see its `shouldStartTimer`); it has no notion of "the
	/// session behind this render key just changed" and a still-running
	/// tracker will happily keep reporting the PREVIOUS winner's elapsed
	/// time through a silent rotation to a different in-flight session.
	/// `PoolDerive` compares this map against the current tick's resolved
	/// identity per render key and resets `promptTimers[renderKey]` when
	/// they diverge, before observing this tick's state.
	var promptTimerWinnerIdentity: [WindowKey: RenderKeyIdentity] = [:]

	// MARK: - P18.03: push-spec memory

	var sessionNumbers: [WindowKey: Int] = [:]
	var resolvedSessionTitles: [WindowKey: String] = [:]
	var lastMenubarIconMonochrome: Bool?
	var activeConflictBubbleTargets: [String: WindowKey] = [:]
	var conflictBubbleLastShownAt: [String: Date] = [:]
	var previousCombinedWindow: DesiredWindow?

	init() {}
}

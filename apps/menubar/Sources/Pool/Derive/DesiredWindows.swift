import Foundation

/// One window's fully-specified desired state for a tick — every push
/// payload `FloatingPetWindowPool.update()` currently calls a
/// `FloatingPetWindowControlling` method for, expressed as data. `apply`
/// (P18.04) will diff this against the previous tick's `DesiredWindows` and
/// issue only the calls that changed.
///
/// P18.03 populates this entire value from pure tick input and `PoolMemory`;
/// P18.04 may therefore apply it mechanically without policy decisions.
struct DesiredWindow: Equatable {
	let key: WindowKey
	/// The render key whose state and label are currently represented by this
	/// window. Folded windows use their elected winner; non-folded windows use
	/// their own key.
	var resolvedIdentity: WindowKey
	/// `true` when this window should use the minimalist renderer. P18.02
	/// resolves this from `PlatformMode`.
	var isMinimalist: Bool = false
	var petId: String = ""
	/// `nil` for a plain-origin/"combined" window. The session-number
	/// allocator itself (assign-on-spawn/release-on-teardown) is P18.02
	/// scope (`PoolMemory.sessionNumberAllocator`); populating this field
	/// with the resolved number as a push payload is still P18.03 — this
	/// ticket only guarantees the allocator's internal state (and the number
	/// it would hand out) is correct.
	var sessionNumber: Int?
	/// Whether this window currently resolves to a real state.d session and
	/// should expose session actions, independent of whether it has a numbered
	/// session-keyed window of its own.
	var hasActiveSession = false
	var sessionLabel: String?
	/// Small, fixed, non-renamable text naming this window's mode — the
	/// resolved session's platform display name for a folded `.origin`, or
	/// "Combined" for `.combined` — or `nil` when `resolvedIdentity == key`
	/// (a genuinely solo window has nothing to disambiguate). Feeds the
	/// visible always-on mode badge (P19.04).
	var modeIndicatorBadge: String?
	var sessionTooltip: String?
	var activityState: ActivityState = .idle
	var promptTimerStatus: PromptTimerPresentation?
	var attention: AttentionPayload?
	var attentionSourceEvent: SourceEvent?
	var gateBadge: GateBadgeContent?
	/// Platform origin to badge the window's platform chip with, or `nil` to
	/// leave it unset this tick.
	var platformChip: String?
	/// Whether the platform chip may animate its logo while this window's pet is
	/// mid-turn. Mirrors `customization.platformChipAnimationEnabled`; the chip
	/// still only animates when the pet is actually in flight.
	var platformChipAnimationEnabled: Bool = false
	var rpgSnapshot: RpgSnapshot = .safeDefault
	var hudEnabled: Bool = false
	var conflictBubble: ConflictBubblePayload?
	/// The window key of the sibling torn down by a session-cap eviction
	/// (Step 6c) or grandfather collapse (Step 6a2's enabling direction) this
	/// window should adopt the on-screen frame from, or `nil` for the
	/// default spawn position. Deliberately a `WindowKey`, never a
	/// fabricated `CGRect`: this ticket's contract is that `derive` never
	/// invents frame values — it only records WHICH torn-down window a later
	/// spawn should inherit from; `apply` (P18.04) reads the actual on-screen
	/// frame at execution time. Replaces P18.01's placeholder
	/// `inheritedFrame: CGRect?` — see this ticket's Rationale for why that
	/// placeholder shape was revised rather than kept.
	var inheritedFrameFrom: WindowKey?

	init(key: WindowKey) {
		self.key = key
		self.resolvedIdentity = key
	}
}

/// Pool-level tick output: the full desired window membership plus every
/// other value `FloatingPetWindowPool` currently exposes as a published
/// property (`blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`,
/// ...), so `apply` and its callers can read one shape instead of going back
/// through the shell's own dictionaries.
///
/// P18.01's `derive` always returned `DesiredWindows()` (every field at its
/// default). P18.02 starts populating `windows` (membership: cap/eviction,
/// grandfather collapse, mode-transition teardown), `pendingSessionKeys`,
/// `blockedOrigins`, and `hiddenWindowKeysToPersist` — see `PoolDerive` for
/// the ticket's exact scope. Push-payload fields on `DesiredWindow` besides
/// `isMinimalist`/`inheritedFrameFrom` remain P18.03.
struct DesiredWindows: Equatable {
	var windows: [WindowKey: DesiredWindow] = [:]
	var blockedOrigins: Set<String> = []
	var pendingSessionKeys: Set<WindowKey> = []
	var ttlDismissedWindowKeys: Set<WindowKey> = []
	/// Hidden-key set to persist via `hiddenKeysSaver`, or `nil` when
	/// unchanged this tick (P18.02).
	var hiddenWindowKeysToPersist: Set<WindowKey>?
	/// New `menubarIconMonochrome` value when it changed this tick, or `nil`
	/// when unchanged (P18.03).
	var monochromeChanged: Bool?
	var idleEscalationConfig: IdleEscalationConfig = .production
	/// `(origin, sessionId)` identities `apply` should resolve a
	/// platform-auto-generated thread title for — the title-resolution
	/// effect seam (Grill-Me decision 3). Populated by `PoolDerive` when a
	/// folded session still lacks a known platform thread title.
	var titleResolutionRequests: [RenderKeyIdentity] = []

	init() {}
}

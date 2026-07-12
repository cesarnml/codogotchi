import CoreGraphics
import Foundation

/// One window's fully-specified desired state for a tick — every push
/// payload `FloatingPetWindowPool.update()` currently calls a
/// `FloatingPetWindowControlling` method for, expressed as data. `apply`
/// (P18.04) will diff this against the previous tick's `DesiredWindows` and
/// issue only the calls that changed.
///
/// P18.01 never constructs a non-empty `DesiredWindow` — selection (which
/// keys exist at all) is P18.02, and the real push payloads below are
/// P18.03. Every field here is a placeholder with a safe default so
/// `DesiredWindows.windows` can stay `Equatable` and empty this ticket
/// without either later ticket reshaping the type.
struct DesiredWindow: Equatable {
	let key: WindowKey
	/// `true` when this window should use the minimalist renderer. P18.02
	/// resolves this from `PlatformMode`.
	var isMinimalist: Bool = false
	var petId: String = ""
	/// `nil` for a plain-origin/"combined" window; P18.03 resolves this via
	/// the session-number allocator.
	var sessionNumber: Int?
	var sessionLabel: String?
	var sessionTooltip: String?
	var activityState: ActivityState = .idle
	var promptTimerStatus: PromptTimerPresentation?
	var attention: AttentionPayload?
	var attentionSourceEvent: SourceEvent?
	var gateBadge: GateBadgeContent?
	/// Platform origin to badge the window's platform chip with, or `nil` to
	/// leave it unset this tick.
	var platformChip: String?
	var hudEnabled: Bool = false
	var conflictBubble: ConflictBubblePayload?
	/// Frame this window should adopt from a sibling's session-cap eviction
	/// or grandfather collapse, or `nil` for the default spawn position.
	/// P18.02 (frame-inheritance directives).
	var inheritedFrame: CGRect?

	init(key: WindowKey) {
		self.key = key
	}
}

/// Pool-level tick output: the full desired window membership plus every
/// other value `FloatingPetWindowPool` currently exposes as a published
/// property (`blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`,
/// ...), so `apply` and its callers can read one shape instead of going back
/// through the shell's own dictionaries.
///
/// P18.01's `derive` always returns `DesiredWindows()` (every field at its
/// default) — see `PoolDerive` for the ticket's exact scope.
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
	/// effect seam (Grill-Me decision 3). Always empty until P18.03.
	var titleResolutionRequests: [RenderKeyIdentity] = []

	init() {}
}

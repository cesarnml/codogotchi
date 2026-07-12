import AppKit

/// Owns panel-instance lifecycle, anchoring, drag/right-click routing, and
/// z-order/fronting for the five chrome panel types that fly in formation
/// with a host window: the animation badge, the gate badge, the attention
/// bubble, the P15.08 conflict (speech) bubble, and the RPG HUD family
/// (hearts/ring, tombstone, regen meter).
///
/// Per `docs/contracts/window-capability-matrix.md` §3, the animation badge
/// is a separate floating panel only in Own mode (R3.1 — Minimalist embeds
/// its badge directly in `MinimalistBadgeView`) and the RPG HUD family is
/// Own-only entirely (R3.9). Minimalist mode simply never calls those entry
/// points; that is the capability difference, not a converged behavior.
///
/// This coordinator does **not** decide *when* a panel should be visible —
/// each host still owns that business logic (active-content flags, hover
/// state, transient-reveal timers) exactly as before, and calls into this
/// coordinator's `reposition`/`hide` methods at the same call sites the
/// per-shape inline code used to live. What moves here is the *mechanical*
/// act of positioning and fronting (or hiding) a panel, and the drag/
/// right-click routing that sends a gesture on floating chrome back into
/// the host window — never new anchor math. Per-shape anchor geometry
/// continues to come from each panel's existing `reposition(...)` overload,
/// which in turn calls the already-pure, already-tested `*Layout` types
/// (`AnimationBadgeLayout`, `GateBadgeLayout`, `AttentionBubbleLayout`,
/// `SpeechBubbleLayout`, `RPGHUDLayout`).
@MainActor
final class ChromeFlockCoordinator {
	/// Host-supplied routing for a drag or right-click landing on chrome that
	/// lives in its own floating window. Own mode routes into
	/// `FloatingPetInteractionView`'s external-drag/hide-prompt handling;
	/// Minimalist mode routes into `MinimalistBadgeView`'s equivalents — same
	/// end effect, different plumbing per shape (R3.2/R3.3/R3.5).
	struct ChromeRouting {
		var presentHidePrompt: (CGPoint) -> Void
		var beginDrag: () -> Void
		var continueDrag: () -> Void
		var endDrag: () -> Void
	}

	private var routing: ChromeRouting

	/// Routing is supplied via `configureRouting(_:)` rather than an init
	/// parameter so a host can construct its coordinator as the very last
	/// stored property in its own `init` and wire routing closures that
	/// capture `self` afterward, once `self` is fully initialized (a routing
	/// closure capturing `self` as part of the coordinator's own init
	/// argument list is rejected by Swift's definite-initialization check —
	/// the property being assigned is not yet considered initialized while
	/// its own initializer expression evaluates).
	init() {
		self.routing = ChromeRouting(
			presentHidePrompt: { _ in }, beginDrag: {}, continueDrag: {}, endDrag: {})
	}

	func configureRouting(_ routing: ChromeRouting) {
		self.routing = routing
	}

	// MARK: - Animation badge (Own only — separate floating panel, R3.1)

	private var animationBadgePanel: AnimationBadgePanel?

	/// Returns the existing animation badge panel without creating one, for
	/// callers that must reposition-only-if-already-shown (verbatim mirror of
	/// the pre-coordinator `animationBadgePanel?.reposition(...)` call in
	/// `resetPromptTimer`, which silently no-ops rather than lazily spawning
	/// a badge outside the normal show/reposition flow).
	var existingAnimationBadgePanel: AnimationBadgePanel? { animationBadgePanel }

	/// Screen-space x of the platform chip's leading edge — the animation
	/// badge panel's own `minX`. `nil` before the panel has been created.
	var animationBadgeLeadingX: CGFloat? { animationBadgePanel?.frame.minX }
	/// Screen-space y of the animation badge panel's own bottom edge. `nil`
	/// before the panel has been created.
	var animationBadgeBottomY: CGFloat? { animationBadgePanel?.frame.minY }

	/// Fired when the user double-clicks the platform chip.
	var onAnimationBadgePlatformChipDoubleClick: (() -> Void)?

	@discardableResult
	func repositionAnimationBadge(
		label: String,
		platform: PlatformAttribution?,
		inFlight: Bool,
		promptTimer: PromptTimerPresentation? = nil,
		sessionNumber: Int? = nil,
		sessionLabel: String? = nil,
		sessionTooltip: String? = nil,
		relativeTo petFrame: CGRect,
		visibleFrame: CGRect
	) -> AnimationBadgePanel {
		let badge = animationBadgePanelInstance()
		badge.reposition(
			label: label,
			platform: platform,
			inFlight: inFlight,
			promptTimer: promptTimer,
			sessionNumber: sessionNumber,
			sessionLabel: sessionLabel,
			sessionTooltip: sessionTooltip,
			relativeTo: petFrame,
			visibleFrame: visibleFrame
		)
		// Reordering the window on every tick fought AppKit's tooltip
		// hover-delay timer, so only reorder when the panel isn't already
		// visible (verbatim from the pre-coordinator implementation).
		if !badge.isVisible {
			badge.orderFrontRegardless()
		}
		return badge
	}

	private func animationBadgePanelInstance() -> AnimationBadgePanel {
		if let existing = animationBadgePanel { return existing }
		let panel = AnimationBadgePanel()
		panel.onRightClickRequested = { [routing] anchor in routing.presentHidePrompt(anchor) }
		panel.onDragBegan = { [routing] in routing.beginDrag() }
		panel.onDragChanged = { [routing] in routing.continueDrag() }
		panel.onDragEnded = { [routing] in routing.endDrag() }
		panel.onPlatformChipDoubleClick = { [weak self] in self?.onAnimationBadgePlatformChipDoubleClick?() }
		animationBadgePanel = panel
		return panel
	}

	func hideAnimationBadge() {
		animationBadgePanel?.orderOut(nil)
	}

	// MARK: - Gate badge (Own + Minimalist, different anchor overloads — R3.4/R3.5)

	private var gateBadgePanel: GateBadgePanel?

	/// Returns the existing gate badge panel without creating one, for
	/// callers (e.g. live drag re-anchoring) that must reposition-only-if-
	/// already-shown without touching z-order.
	var existingGateBadgePanel: GateBadgePanel? { gateBadgePanel }

	/// Refreshes badge content/metrics without moving the panel — mirrors the
	/// pre-coordinator behavior of keeping badge content current even while
	/// the panel is not yet shown, so a later `repositionGateBadgeOwn` call
	/// positions freshly-configured content on its very first frame.
	@discardableResult
	func updateGateBadge(content: GateBadgeContent, relativeTo petFrame: CGRect) -> GateBadgePanel {
		let badge = gateBadgePanelInstance()
		badge.update(content: content, relativeTo: petFrame)
		return badge
	}

	@discardableResult
	func repositionGateBadgeOwn(
		content: GateBadgeContent, relativeTo petFrame: CGRect, chipLeadingX: CGFloat, visibleFrame: CGRect
	) -> GateBadgePanel {
		let badge = gateBadgePanelInstance()
		badge.reposition(
			content: content, relativeTo: petFrame, chipLeadingX: chipLeadingX, visibleFrame: visibleFrame)
		badge.orderFrontRegardless()
		return badge
	}

	@discardableResult
	func repositionGateBadgeMinimalist(
		content: GateBadgeContent,
		metrics: GateBadgeLayout.Metrics,
		relativeTo anchorFrame: CGRect,
		visibleFrame: CGRect
	) -> GateBadgePanel {
		let badge = gateBadgePanelInstance()
		badge.reposition(content: content, metrics: metrics, relativeTo: anchorFrame, visibleFrame: visibleFrame)
		badge.orderFrontRegardless()
		return badge
	}

	func hideGateBadge() {
		gateBadgePanel?.orderOut(nil)
	}

	private func gateBadgePanelInstance() -> GateBadgePanel {
		if let existing = gateBadgePanel { return existing }
		let panel = GateBadgePanel()
		panel.onRightClickRequested = { [routing] anchor in routing.presentHidePrompt(anchor) }
		panel.onDragBegan = { [routing] in routing.beginDrag() }
		panel.onDragChanged = { [routing] in routing.continueDrag() }
		panel.onDragEnded = { [routing] in routing.endDrag() }
		gateBadgePanel = panel
		return panel
	}

	// MARK: - Attention bubble (Own + Minimalist, different anchors — R3.7)

	private var attentionBubblePanel: AttentionBubblePanel?

	/// Returns the existing attention bubble panel without creating one, for
	/// callers (e.g. live drag re-anchoring) that must reposition-only-if-
	/// already-shown without touching z-order.
	var existingAttentionBubblePanel: AttentionBubblePanel? { attentionBubblePanel }

	/// Fired when the user dismisses the attention bubble (X button or the
	/// Focus action, both of which call through to this). The host remains
	/// responsible for its own reaction (resetting prompt timers, returning
	/// to idle, etc.) — this coordinator only relays the event.
	var onAttentionDismiss: (() -> Void)?

	@discardableResult
	func updateAttentionBubble(payload: AttentionPayload, sourceEvent: SourceEvent?) -> AttentionBubblePanel {
		let bubble = attentionBubblePanelInstance()
		bubble.update(payload: payload, sourceEvent: sourceEvent)
		return bubble
	}

	func repositionAttentionBubble(
		relativeTo petFrame: CGRect, leadingX: CGFloat, bottomAnchorY: CGFloat, visibleFrame: CGRect
	) {
		guard let bubble = attentionBubblePanel else { return }
		bubble.reposition(
			relativeTo: petFrame, leadingX: leadingX, bottomAnchorY: bottomAnchorY, visibleFrame: visibleFrame)
		bubble.orderFrontRegardless()
	}

	func hideAttentionBubble() {
		attentionBubblePanel?.orderOut(nil)
	}

	private func attentionBubblePanelInstance() -> AttentionBubblePanel {
		if let existing = attentionBubblePanel { return existing }
		let bubble = AttentionBubblePanel()
		bubble.onDismiss = { [weak self] in self?.onAttentionDismiss?() }
		attentionBubblePanel = bubble
		return bubble
	}

	// MARK: - Conflict / speech bubble (Own + Minimalist, different anchors — R3.8)

	private var conflictBubblePanel: SpeechBubblePanel?

	/// Returns the existing conflict bubble panel without creating one, for
	/// callers (e.g. live drag re-anchoring) that must reposition-only-if-
	/// already-shown without touching z-order.
	var existingConflictBubblePanel: SpeechBubblePanel? { conflictBubblePanel }

	/// Fired when the user clicks the conflict bubble's action affordance
	/// (opens Settings > Customization).
	var onConflictAction: (() -> Void)?
	/// Fired when the user dismisses the conflict bubble. Clearing the
	/// host's own "conflict active" flag (not just ordering out) is what
	/// makes the dismissal stick — a later reposition call while the flag
	/// stays true would re-front the panel. The host owns that flag.
	var onConflictDismiss: (() -> Void)?

	@discardableResult
	func updateConflictBubble(origin: String?) -> SpeechBubblePanel {
		let bubble = conflictBubblePanelInstance()
		bubble.configureConflict(origin: origin)
		return bubble
	}

	func repositionConflictBubbleOwn(aboveFloatingPetFrame petFrame: CGRect, visibleFrame: CGRect) {
		guard let bubble = conflictBubblePanel else { return }
		bubble.reposition(aboveFloatingPetFrame: petFrame, visibleFrame: visibleFrame)
		bubble.orderFrontRegardless()
	}

	func repositionConflictBubbleMinimalist(aboveMinimalistStrip stripFrame: CGRect, visibleFrame: CGRect) {
		guard let bubble = conflictBubblePanel else { return }
		bubble.reposition(aboveMinimalistStrip: stripFrame, visibleFrame: visibleFrame)
		bubble.orderFrontRegardless()
	}

	func hideConflictBubble() {
		conflictBubblePanel?.orderOut(nil)
	}

	private func conflictBubblePanelInstance() -> SpeechBubblePanel {
		if let existing = conflictBubblePanel { return existing }
		let bubble = SpeechBubblePanel()
		bubble.onAction = { [weak self] in self?.onConflictAction?() }
		bubble.onDismiss = { [weak self] in self?.onConflictDismiss?() }
		conflictBubblePanel = bubble
		return bubble
	}

	// MARK: - RPG HUD family (Own only — R3.9)

	private var rpgHUDPanel: RPGHUDPanel?
	private var tombstonePanel: TombstonePanel?
	private var regenMeterPanel: RegenMeterPanel?

	@discardableResult
	func repositionHUD(
		hearts: [HeartState],
		ringFraction: Double,
		level: Int,
		regenProgress: Double,
		showsRegenBar: Bool,
		relativeTo petFrame: CGRect,
		spriteAnchor: CGRect?,
		visibleFrame: CGRect
	) -> RPGHUDPanel {
		let hud = rpgHUDPanelInstance()
		hud.reposition(
			hearts: hearts,
			ringFraction: ringFraction,
			level: level,
			regenProgress: regenProgress,
			showsRegenBar: showsRegenBar,
			relativeTo: petFrame,
			spriteAnchor: spriteAnchor,
			visibleFrame: visibleFrame
		)
		return hud
	}

	func hideHUDImmediately() {
		rpgHUDPanel?.hideImmediately()
	}

	private func rpgHUDPanelInstance() -> RPGHUDPanel {
		if let existing = rpgHUDPanel { return existing }
		let panel = RPGHUDPanel()
		rpgHUDPanel = panel
		return panel
	}

	/// Returns the existing HUD panel without creating one, for callers (hover
	/// tracking, ring-hover pointer updates) that must not lazily spawn a HUD
	/// that was never shown.
	var existingHUDPanel: RPGHUDPanel? { rpgHUDPanel }
	/// Returns the existing tombstone panel without creating one, for callers
	/// (e.g. live drag re-anchoring) that must reposition-only-if-already-shown
	/// without touching z-order.
	var existingTombstonePanel: TombstonePanel? { tombstonePanel }
	/// Returns the existing regen meter panel without creating one, mirroring
	/// `existingTombstonePanel`.
	var existingRegenMeterPanel: RegenMeterPanel? { regenMeterPanel }

	func repositionGhostChrome(relativeTo petFrame: CGRect, spriteAnchor: CGRect?, visibleFrame: CGRect) {
		let tomb = tombstonePanelInstance()
		tomb.reposition(relativeTo: petFrame, spriteAnchor: spriteAnchor, visibleFrame: visibleFrame)
		tomb.orderFrontRegardless()
	}

	func repositionRegenMeter(
		progress: Double, relativeTo petFrame: CGRect, spriteAnchor: CGRect?, visibleFrame: CGRect
	) {
		let meter = regenMeterPanelInstance()
		meter.reposition(
			progress: progress, relativeTo: petFrame, spriteAnchor: spriteAnchor, visibleFrame: visibleFrame)
		meter.orderFrontRegardless()
	}

	func hideGhostChrome() {
		tombstonePanel?.orderOut(nil)
		regenMeterPanel?.orderOut(nil)
	}

	private func tombstonePanelInstance() -> TombstonePanel {
		if let existing = tombstonePanel { return existing }
		let panel = TombstonePanel()
		tombstonePanel = panel
		return panel
	}

	private func regenMeterPanelInstance() -> RegenMeterPanel {
		if let existing = regenMeterPanel { return existing }
		let panel = RegenMeterPanel()
		regenMeterPanel = panel
		return panel
	}
}

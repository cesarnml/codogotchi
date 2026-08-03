import AppKit

/// Minimalist-mode renderer. Two independent single-purpose floating panels,
/// mirroring how Own mode keeps its pet panel and attention bubble separate:
///
/// - `badgePanel` hosts only the `AnimationBadgeView` (platform chip + activity
///   label). It is content-tight, owns the drag, and is the persisted frame.
///   It never embeds the bubble and never resizes when attention toggles.
/// - the attention bubble is the SAME `AttentionBubblePanel` Own mode uses
///   (owned by `chromeCoordinator`), ordered in/out as attention arrives and
///   positioned relative to the badge panel.
///
/// Keeping the two as separate windows is the whole point: the earlier design
/// shape-shifted one panel between a content-tight badge and a fixed-width
/// embedded bubble, which let the bubble's required-priority constraints leak
/// into the badge's fitting-size math (runaway width) and produced torn /
/// clipped repaints when a dismiss and a combined-window chip swap resized the
/// same panel in one tick. With two panels neither failure mode is reachable.
@MainActor
final class MinimalistPanelController: PanelActionHandling {
	private enum Layout {
		static let height: CGFloat = 58
		/// Floor for the identity-row (mode chip + session label) reserve —
		/// scaled badge metrics may require more; see `panelHeight`.
		static let sessionRowExtraHeight: CGFloat = 26
		static let minBadgeWidth: CGFloat = 80
		/// Vertical inset around the stacked badge content inside the strip.
		static let contentVerticalInset: CGFloat = 8
	}

	private let visibleFrameProvider: () -> CGRect
	private var badgePanel: NSPanel?
	private let badgeView = MinimalistBadgeView(frame: .zero)
	private var currentConflictPayload: ConflictBubblePayload?
	/// Owns instance lifecycle, anchoring, drag/right-click routing, and
	/// fronting for the gate badge, attention bubble, and conflict (speech)
	/// bubble — the same shared panel types Own mode uses (P17.03). This
	/// controller still owns all "when is this visible" business logic.
	private let chromeCoordinator: ChromeFlockCoordinator

	private var currentPlatformOrigin: String?
	private var motionSettings = MotionSettings.disabled
	private var currentActivity: ActivityState = .idle
	private var currentAttention: AttentionPayload?
	private var currentSourceEvent: SourceEvent?
	private var currentGateBadge: GateBadgeContent?
	/// Session number assigned to this window by `FloatingPetWindowPool`, or
	/// `nil` for a plain-origin/combined window. Non-nil grows the panel to
	/// make room for the identity row (`modeIndicator` + `PlatformSessionBadge`).
	private var currentSessionNumber: Int?
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N".
	private var currentSessionLabel: String?
	/// Fixed Combined / platform-name chip for fold windows. Non-nil (along
	/// with a session number or session label) grows `panelHeight` so the
	/// identity row is not clipped by the activity-only strip height.
	private var currentModeIndicatorBadge: String?
	/// Last submitted prompt for this session, shown as a delayed hover
	/// tooltip on the session badge.
	private var currentSessionTooltip: String?
	/// Badge metrics driven by the user's "PlatformChip and AnimationBadge Size"
	/// slider in Settings > Customization. Updated via applyBadgeScale(_:).
	private var currentBadgeMetrics = GateBadgeLayout.metrics(scale: 1.0)
	/// True when the identity row under the activity chip+pill is populated.
	private var hasIdentityRow: Bool {
		currentSessionNumber != nil
			|| !(currentSessionLabel ?? "").isEmpty
			|| !(currentModeIndicatorBadge ?? "").isEmpty
	}
	/// Panel height for the current tick. Always tall enough for the activity
	/// strip; when a mode/session identity row is present, reserve room sized
	/// to the current badge metrics (Large slider must not clip Combined /
	/// platform chips).
	private var panelHeight: CGFloat {
		guard hasIdentityRow else { return Layout.height }
		let identityExtra = max(
			Layout.sessionRowExtraHeight,
			currentBadgeMetrics.badgeHeight + MinimalistBadgeView.rowSpacing)
		return Layout.height + identityExtra
	}
	private var frameChangeHandler: ((CGRect) -> Void)?
	private var isShown = false
	/// Called after the user dismisses or focuses away from the attention bubble.
	var onAttentionDismissed: (() -> Void)?
	/// Called when the user activates the badge's right-click "Hide panel"
	/// affordance. Mirrors `FloatingPetPanelController.onHideFloatingPet`; the app
	/// wires this to hide this window via the window pool.
	var onHideWindowRequested: (() -> Void)?
	/// Called when the user activates the badge's right-click "Force Idle"
	/// affordance (only offered while non-idle). The app wires this to rewrite
	/// this origin's `state.d/` slice back to idle.
	var onForceIdle: (() -> Void)?
	/// Called when the user clicks the P15.08 conflict bubble's action button.
	/// Wired by the caller to open Settings > Customization.
	var onOpenSettingsRequested: (() -> Void)?
	/// Fired with the trimmed/capped label the user commits via the badge's
	/// right-click rename affordance. Wired by the caller (`MenubarApp`) to
	/// persist to `SessionLabelStore` — mirrors Own mode's `onRenameRequested`.
	var onRenameRequested: ((String) -> Void)?
	/// Fired when the user activates the badge's right-click "Sync Label"
	/// affordance. Wired by the caller (`MenubarApp`) to re-fetch the
	/// platform's current thread title and persist it — mirrors Own mode's
	/// `onSyncLabelRequested`.
	var onSyncLabelRequested: (() -> Void)?
	/// Fired when the user confirms the badge's right-click "Prune Session"
	/// affordance. Wired by the caller (`MenubarApp`) to destroy the session's
	/// backing state via the window pool — mirrors Own mode's
	/// `onPruneRequested`.
	var onPruneRequested: (() -> Void)?
	/// Fired when the user activates the badge's right-click "Hide All Other
	/// Pets" affordance. Wired by the caller (`MenubarApp`) to hide every
	/// other currently-rendered window via the pool — mirrors Own mode's
	/// `onHideAllOtherPetsRequested`.
	var onHideAllOtherPetsRequested: (() -> Void)?
	/// Fired when the user activates the badge's right-click "Pet Mode"
	/// affordance. Wired by the caller (`MenubarApp`) to persist the mode
	/// switch to customization.json — mirrors Own mode's `onSwitchToMinimalist`.
	var onModeSwitchRequested: (() -> Void)?
	/// Fired on each tick of the badge's right-click "Panel Size" slider
	/// (`isFinal` marks the tick ending the drag gesture). Wired by the
	/// caller (`MenubarApp`) to persist the global `minimalist_badge_scale` —
	/// the same setting the Customization tab's slider writes.
	var onPanelSizeChanged: ((Double, Bool) -> Void)?

	init(
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.screens.isEmpty
				? CGRect(x: 0, y: 0, width: 800, height: 600)
				: NSScreen.screens.map(\.visibleFrame).reduce(CGRect.null) { $0.union($1) }
		}
	) {
		self.visibleFrameProvider = visibleFrameProvider
		self.chromeCoordinator = ChromeFlockCoordinator()
		badgeView.clampedFrameProvider = { [weak self] origin in
			guard let self else { return CGRect(origin: origin, size: .zero) }
			let size = self.badgePanel?.frame.size
				?? CGSize(width: Layout.minBadgeWidth, height: self.panelHeight)
			return self.clampedFrame(origin: origin, size: size)
		}
		// Keep the bubble and gate badge anchored to the badge while it is dragged.
		badgeView.onDragMoved = { [weak self] frame in
			self?.repositionBubble(badgeFrame: frame)
			self?.repositionConflictBubble(badgeFrame: frame)
			self?.applyGateBadgePanel(badgeFrame: frame)
		}
		// Persist the badge frame when the drag ends.
		badgeView.frameChangeHandler = { [weak self] frame in
			self?.frameChangeHandler?(frame)
		}
		// Right-click "Hide panel" affordance on the badge (chip or activity pill).
		badgeView.onHidePanelRequested = { [weak self] in
			self?.onHideWindowRequested?()
		}
		// Double-click the platform chip to jump to the driving app, mirroring
		// the attention bubble's Focus button.
		badgeView.onPlatformChipDoubleClick = { [weak self] in
			AttentionFocusTarget.focus(sourceEvent: self?.currentSourceEvent)
		}
		// Right-click "Force Idle" affordance, shown only while non-idle.
		badgeView.onForceIdleRequested = { [weak self] in
			self?.badgeView.resetPromptTimer()
			self?.onForceIdle?()
		}
		// Right-click "Rename…" affordance, offered only while a session number
		// is assigned. This panel never writes the sidecar itself.
		badgeView.renameHandler = { [weak self] newLabel in
			self?.applySessionLabel(newLabel)
			self?.onRenameRequested?(newLabel)
		}
		// Right-click "Sync Label" affordance, offered only while a session
		// number is assigned. This panel never resolves or writes the label
		// itself — the app-level handler does the fetch-and-persist and the
		// next poll tick re-applies it via `applySessionLabel`.
		badgeView.syncLabelHandler = { [weak self] in
			self?.onSyncLabelRequested?()
		}
		// Right-click "Prune Session" affordance, offered only while a session
		// number is assigned. This panel never destroys session state itself —
		// the app-level handler routes the prune through the window pool.
		badgeView.pruneHandler = { [weak self] in
			self?.onPruneRequested?()
		}
		// Right-click "Hide All Other Pets" affordance, offered
		// unconditionally. This panel never touches other windows itself.
		badgeView.hideAllOtherPetsHandler = { [weak self] in
			self?.onHideAllOtherPetsRequested?()
		}
		// Right-click "Pet Mode" affordance — back to the full pet renderer.
		badgeView.onPetModeRequested = { [weak self] in
			self?.onModeSwitchRequested?()
		}
		// Right-click "Panel Size" slider: live-apply the scale to this
		// strip immediately for direct feedback (sibling strips follow on their
		// next poll tick once the persisted write lands), then forward for
		// persistence.
		badgeView.panelSizeHandler = { [weak self] scale, isFinal in
			self?.applyBadgeScale(scale)
			self?.onPanelSizeChanged?(scale, isFinal)
		}
		self.chromeCoordinator.configureRouting(
			ChromeFlockCoordinator.ChromeRouting(
				presentHidePrompt: { [weak self] anchor in self?.badgeView.presentHidePrompt(anchorInScreen: anchor) },
				beginDrag: { [weak self] in self?.badgeView.beginExternalDrag() },
				continueDrag: { [weak self] in self?.badgeView.continueExternalDrag() },
				endDrag: { [weak self] in self?.badgeView.endExternalDrag() }
			)
		)
		self.chromeCoordinator.onAttentionDismiss = { [weak self] in self?.handleBubbleDismiss() }
		self.chromeCoordinator.onConflictAction = { [weak self] in self?.onOpenSettingsRequested?() }
		self.chromeCoordinator.onConflictDismiss = { [weak self] in
			// Clearing the payload (not just ordering out) is what makes the
			// dismissal stick: `applyConflictBubblePresentation` re-fronts the
			// panel on every badge pass while a payload is set. The pool's
			// hourly rate limiter may legitimately re-show it later.
			self?.currentConflictPayload = nil
			self?.chromeCoordinator.hideConflictBubble()
		}
	}

	func show(frame: CGRect) {
		let panel = badgePanel ?? makeBadgePanel()
		badgePanel = panel
		isShown = true
		applyBadge(anchorOrigin: frame.origin)
		panel.orderFrontRegardless()
		applyBubble()
		applyConflictBubblePresentation()
	}

	func hide() {
		isShown = false
		badgeView.dismissHidePromptIfPresent()
		// Stand the chip's logo animation down before ordering out, exactly as the
		// Own path does in `ChromeFlockCoordinator.hideAnimationBadge`. Ordering a
		// window out leaves `window` set on its views and Core Animation keeps
		// evaluating their animations, and `applyBadge` is gated on `isShown`, so
		// nothing else would ever stop it — a hidden Minimalist pet would spin on
		// an invisible layer for the rest of the session.
		badgeView.setChipAnimationSuspended(true)
		badgePanel?.orderOut(nil)
		chromeCoordinator.hideAttentionBubble()
		chromeCoordinator.hideConflictBubble()
		chromeCoordinator.hideGateBadge()
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		currentConflictPayload = payload
		applyConflictBubblePresentation()
	}

	func applyPlatform(origin: String?) {
		currentPlatformOrigin = origin
		applyBadge()
		applyBubble()
	}

	func applyMotionSettings(_ settings: MotionSettings) {
		guard settings != motionSettings else { return }
		motionSettings = settings
		applyBadge()
	}

	func applyActivity(_ state: ActivityState) {
		currentActivity = state
		applyBadge()
	}

	func applyLocalPromptTimerStatus(_ status: PromptTimerStatus?) {
		badgeView.applyLocalPromptTimerStatus(status)
		applyBadge()
	}

	/// `PoolApply` (P18.04)'s already-rendered equivalent — see
	/// `FloatingPetPanelController.applyElapsedPresentation`'s doc for
	/// why this forwards directly rather than deriving from a raw status.
	func applyElapsedPresentation(_ presentation: ElapsedPresentation?) {
		badgeView.applyElapsedPresentation(presentation)
		applyBadge()
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		currentAttention = payload?.isExpired() == true ? nil : payload
		currentSourceEvent = sourceEvent
		applyBubble()
	}

	func applyPromptSummary(_ summary: String) {
		// Prompt summary is not shown for platform-linked minimalist panels.
	}

	func applyBadgeScale(_ scale: Double) {
		// Mirror before the no-change guard so the size pill's dial always
		// starts at the live value, even when metrics quantize to no repaint.
		badgeView.currentBadgeScale = scale
		let newMetrics = GateBadgeLayout.metrics(scale: CGFloat(scale))
		guard newMetrics != currentBadgeMetrics else { return }
		currentBadgeMetrics = newMetrics
		applyBadge()
	}

	func applySessionNumber(_ number: Int?) {
		guard currentSessionNumber != number else { return }
		currentSessionNumber = number
		badgeView.configureSessionNumber(number, label: currentSessionLabel, tooltip: currentSessionTooltip)
		applyBadge()
	}

	func applyHasActiveSession(_ hasActiveSession: Bool) {
		badgeView.applyHasActiveSession(hasActiveSession)
	}

	func applySessionLabel(_ label: String?) {
		guard currentSessionLabel != label else { return }
		currentSessionLabel = label
		badgeView.configureSessionNumber(currentSessionNumber, label: label, tooltip: currentSessionTooltip)
		applyBadge()
	}

	func applyModeIndicatorBadge(_ text: String?) {
		guard currentModeIndicatorBadge != text else { return }
		currentModeIndicatorBadge = text
		badgeView.applyModeIndicatorBadge(text)
		applyBadge()
	}

	func applySessionTooltip(_ summary: String?) {
		guard currentSessionTooltip != summary else { return }
		currentSessionTooltip = summary
		badgeView.configureSessionNumber(currentSessionNumber, label: currentSessionLabel, tooltip: summary)
	}

	func applyGateBadge(content: GateBadgeContent?) {
		currentGateBadge = content
		applyGateBadgePanel(badgeFrame: badgePanel?.frame ?? .zero)
	}

	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
		frameChangeHandler = handler
	}

	private func makeBadgePanel() -> NSPanel {
		let initialSize = CGSize(width: Layout.minBadgeWidth, height: panelHeight)
		let panel = NSPanel(
			contentRect: CGRect(origin: .zero, size: initialSize),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.level = .floating
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		panel.hidesOnDeactivate = false
		panel.isReleasedWhenClosed = false
		panel.ignoresMouseEvents = false
		panel.contentView = badgeView
		return panel
	}

	/// Clamps `origin` so a panel of `size` stays fully within the visible frame.
	private func clampedFrame(origin: CGPoint, size: CGSize) -> CGRect {
		let visible = visibleFrameProvider().insetBy(dx: 6, dy: 6)
		let x = max(visible.minX, min(visible.maxX - size.width, origin.x))
		let y = max(visible.minY, min(visible.maxY - size.height, origin.y))
		return CGRect(x: x, y: y, width: size.width, height: size.height)
	}

	// MARK: - Badge panel

	/// Re-render the badge and size its panel content-tight. Touches only the
	/// badge panel; the bubble is repositioned to follow but never resized here.
	/// `anchorOrigin` is the saved origin on first show; later calls keep the
	/// current origin so the badge does not jump on every poll tick.
	private func applyBadge(anchorOrigin: CGPoint? = nil) {
		guard isShown, let panel = badgePanel else { return }
		badgeView.setChipAnimationSuspended(false)
		badgeView.configureBadge(
			platform: PlatformAttribution(origin: currentPlatformOrigin),
			activity: currentActivity,
			metrics: currentBadgeMetrics,
			motionSettings: motionSettings
		)
		let origin = anchorOrigin ?? panel.frame.origin
		let badgeW = max(Layout.minBadgeWidth, badgeView.badgePreferredWidth)
		let newFrame = clampedFrame(origin: origin, size: CGSize(width: badgeW, height: panelHeight))
		if newFrame != panel.frame {
			panel.setFrame(newFrame, display: true)
		}
		repositionBubble(badgeFrame: newFrame)
		repositionConflictBubble(badgeFrame: newFrame)
		applyGateBadgePanel(badgeFrame: newFrame)
	}

	// MARK: - Gate badge panel (independent window, stacked above the strip)

	/// Order the gate badge panel in or out and, when visible, reposition it
	/// centered above `badgeFrame` (the strip containing the platform chip +
	/// animation badge) — reusing `GateBadgeLayout`'s "centered on midX, just
	/// above the anchor" placement verbatim from Own mode.
	private func applyGateBadgePanel(badgeFrame: CGRect) {
		guard isShown else { return }
		guard let content = currentGateBadge else {
			chromeCoordinator.hideGateBadge()
			return
		}
		chromeCoordinator.repositionGateBadgeMinimalist(
			content: content,
			metrics: currentBadgeMetrics,
			relativeTo: badgeFrame,
			visibleFrame: visibleFrameProvider()
		)
	}

	// MARK: - Bubble panel (independent window, mirrors Own mode)

	/// Order the bubble panel in or out based on the current attention payload.
	private func applyBubble() {
		guard isShown else { return }
		guard let payload = currentAttention else {
			chromeCoordinator.hideAttentionBubble()
			return
		}
		chromeCoordinator.updateAttentionBubble(payload: payload, sourceEvent: currentSourceEvent)
		let badgeFrame = badgePanel?.frame ?? .zero
		chromeCoordinator.repositionAttentionBubble(
			relativeTo: badgeFrame,
			leadingX: badgeFrame.minX + MinimalistBadgeView.hPad,
			bottomAnchorY: badgeFrame.minY,
			visibleFrame: visibleFrameProvider()
		)
	}

	/// Live re-anchor while the strip moves/resizes: reposition-only, never
	/// re-fronting — front-on-content-change lives in `applyBubble`.
	private func repositionBubble(badgeFrame: CGRect) {
		guard currentAttention != nil else { return }
		chromeCoordinator.liveRepositionAttentionBubble(
			relativeTo: badgeFrame,
			leadingX: badgeFrame.minX + MinimalistBadgeView.hPad,
			bottomAnchorY: badgeFrame.minY,
			visibleFrame: visibleFrameProvider()
		)
	}

	// MARK: - Conflict bubble panel (P15.08, independent window)

	/// Order the P15.08 conflict-bubble panel in or out based on the current
	/// conflict payload. Distinct from `applyBubble` (real attention) — the two
	/// bubbles never share a field or a panel instance.
	private func applyConflictBubblePresentation() {
		guard isShown else { return }
		guard let payload = currentConflictPayload else {
			chromeCoordinator.hideConflictBubble()
			return
		}
		chromeCoordinator.updateConflictBubble(origin: payload.origin)
		chromeCoordinator.repositionConflictBubbleMinimalist(
			aboveMinimalistStrip: badgePanel?.frame ?? .zero, visibleFrame: visibleFrameProvider())
	}

	/// Live re-anchor while the strip moves/resizes: reposition-only, never
	/// re-fronting — front-on-content-change lives in
	/// `applyConflictBubblePresentation`.
	private func repositionConflictBubble(badgeFrame: CGRect) {
		guard currentConflictPayload != nil else { return }
		chromeCoordinator.liveRepositionConflictBubbleMinimalist(
			aboveMinimalistStrip: badgeFrame, visibleFrame: visibleFrameProvider())
	}

	private func handleBubbleDismiss() {
		currentAttention = nil
		currentActivity = .idle
		badgeView.resetPromptTimer()
		chromeCoordinator.hideAttentionBubble()
		applyBadge()
		onAttentionDismissed?()
	}
}

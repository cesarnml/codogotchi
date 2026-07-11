import AppKit

/// Minimalist-mode renderer. Two independent single-purpose floating panels,
/// mirroring how Own mode keeps its pet panel and attention bubble separate:
///
/// - `badgePanel` hosts only the `AnimationBadgeView` (platform chip + activity
///   label). It is content-tight, owns the drag, and is the persisted frame.
///   It never embeds the bubble and never resizes when attention toggles.
/// - `bubblePanel` is the SAME `AttentionBubblePanel` Own mode uses, ordered in
///   / out as attention arrives and positioned relative to the badge panel.
///
/// Keeping the two as separate windows is the whole point: the earlier design
/// shape-shifted one panel between a content-tight badge and a fixed-width
/// embedded bubble, which let the bubble's required-priority constraints leak
/// into the badge's fitting-size math (runaway width) and produced torn /
/// clipped repaints when a dismiss and a combined-window chip swap resized the
/// same panel in one tick. With two panels neither failure mode is reachable.
@MainActor
final class MinimalistPanelController: MinimalistPanelManaging {
	private enum Layout {
		static let height: CGFloat = 58
		/// Extra vertical room for the `PlatformSessionBadge` row, only added
		/// when a session number is actually assigned to this panel (i.e. the
		/// window is session-keyed and session-pets is on) — a plain-origin
		/// Minimalist strip never grows. `AttentionBubblePanel.reposition`
		/// anchors off this panel's actual on-screen frame
		/// (`BubbleLayout.frame`: `y = petFrame.minY - gapBelowPet - height`),
		/// so growing the badge panel's height naturally pushes the bubble down
		/// without a separate offset constant.
		static let sessionRowExtraHeight: CGFloat = 26
		static let minBadgeWidth: CGFloat = 80
	}

	private let visibleFrameProvider: () -> CGRect
	private var badgePanel: NSPanel?
	private let badgeView = MinimalistBadgeView(frame: .zero)
	/// Separate attention-bubble panel — the same component Own mode uses,
	/// created lazily on first attention event.
	private var bubblePanel: AttentionBubblePanel?
	/// P15.08 conflict-bubble panel — distinct from `bubblePanel` (real
	/// attention) so the two never contend for the same field.
	private var conflictBubblePanel: SpeechBubblePanel?
	private var currentConflictPayload: ConflictBubblePayload?
	/// Ticket/gate badge panel, stacked above the strip (ticket over gate,
	/// centered on the strip's midX) — the same `GateBadgePanel` Own mode uses,
	/// created lazily on the first non-nil gate badge.
	private var gateBadgePanel: GateBadgePanel?

	private var currentPlatformOrigin: String?
	private var currentActivity: ActivityState = .idle
	private var currentAttention: AttentionPayload?
	private var currentSourceEvent: SourceEvent?
	private var currentGateBadge: GateBadgeContent?
	/// Session number assigned to this window by `FloatingPetWindowPool`, or
	/// `nil` for a plain-origin/combined window. Non-nil grows the panel to
	/// make room for the `PlatformSessionBadge` row.
	private var currentSessionNumber: Int?
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N".
	private var currentSessionLabel: String?
	/// Last submitted prompt for this session, shown as a delayed hover
	/// tooltip on the session badge.
	private var currentSessionTooltip: String?
	/// Badge metrics driven by the user's "PlatformChip and AnimationBadge Size"
	/// slider in Settings > Customization. Updated via applyBadgeScale(_:).
	private var currentBadgeMetrics = GateBadgeLayout.metrics(scale: 1.0)
	/// Panel height for the current tick — base height, or base + the session
	/// row's extra height while a session number is assigned.
	private var panelHeight: CGFloat {
		currentSessionNumber != nil ? Layout.height + Layout.sessionRowExtraHeight : Layout.height
	}
	private var frameChangeHandler: ((CGRect) -> Void)?
	private var isShown = false
	/// Called after the user dismisses or focuses away from the attention bubble.
	var onAttentionDismissed: (() -> Void)?
	/// Called when the user activates the badge's right-click "Hide panel"
	/// affordance. Mirrors `FloatingPetPanelController.onHideFloatingPet`; the app
	/// wires this to hide this window via the window pool.
	var onHidePanel: (() -> Void)?
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
	var onSwitchToPetMode: (() -> Void)?
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
			self?.onHidePanel?()
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
			self?.onSwitchToPetMode?()
		}
		// Right-click "Panel Size" slider: live-apply the scale to this
		// strip immediately for direct feedback (sibling strips follow on their
		// next poll tick once the persisted write lands), then forward for
		// persistence.
		badgeView.panelSizeHandler = { [weak self] scale, isFinal in
			self?.applyBadgeScale(scale)
			self?.onPanelSizeChanged?(scale, isFinal)
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
		badgePanel?.orderOut(nil)
		bubblePanel?.orderOut(nil)
		conflictBubblePanel?.orderOut(nil)
		gateBadgePanel?.orderOut(nil)
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

	func applyActivity(_ state: ActivityState) {
		currentActivity = state
		applyBadge()
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		badgeView.applyPromptTimerStatus(status)
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

	func applySessionLabel(_ label: String?) {
		guard currentSessionLabel != label else { return }
		currentSessionLabel = label
		badgeView.configureSessionNumber(currentSessionNumber, label: label, tooltip: currentSessionTooltip)
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
		badgeView.configureBadge(
			platform: PlatformAttribution(origin: currentPlatformOrigin),
			activity: currentActivity,
			metrics: currentBadgeMetrics
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
			gateBadgePanel?.orderOut(nil)
			return
		}
		let badge = gateBadgePanel ?? {
			let panel = GateBadgePanel()
			// Route a right-click on the ticket/gate stack into the same
			// hide/rename/force-idle prompt a click on the badge strip itself
			// presents (P?? unification: right-click works from any chrome
			// piece, not just the strip's own view).
			panel.onRightClickRequested = { [weak self] anchor in
				self?.badgeView.presentHidePrompt(anchorInScreen: anchor)
			}
			// Route a left-click-drag on the ticket/gate stack into moving
			// this strip, same as grabbing the strip itself would.
			panel.onDragBegan = { [weak self] in self?.badgeView.beginExternalDrag() }
			panel.onDragChanged = { [weak self] in self?.badgeView.continueExternalDrag() }
			panel.onDragEnded = { [weak self] in self?.badgeView.endExternalDrag() }
			gateBadgePanel = panel
			return panel
		}()
		badge.reposition(
			content: content,
			metrics: currentBadgeMetrics,
			relativeTo: badgeFrame,
			visibleFrame: visibleFrameProvider()
		)
		badge.orderFrontRegardless()
	}

	// MARK: - Bubble panel (independent window, mirrors Own mode)

	/// Order the bubble panel in or out based on the current attention payload.
	private func applyBubble() {
		guard isShown else { return }
		guard let payload = currentAttention else {
			bubblePanel?.orderOut(nil)
			return
		}
		let bubble = bubblePanel ?? {
			let b = AttentionBubblePanel()
			b.onDismiss = { [weak self] in self?.handleBubbleDismiss() }
			bubblePanel = b
			return b
		}()
		bubble.update(payload: payload, sourceEvent: currentSourceEvent)
		repositionBubble(badgeFrame: badgePanel?.frame ?? .zero)
		bubble.orderFrontRegardless()
	}

	private func repositionBubble(badgeFrame: CGRect) {
		guard currentAttention != nil, let bubble = bubblePanel else { return }
		bubble.reposition(
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
			conflictBubblePanel?.orderOut(nil)
			return
		}
		let bubble = conflictBubblePanel ?? {
			let b = SpeechBubblePanel()
			b.onAction = { [weak self] in self?.onOpenSettingsRequested?() }
			// Clearing the payload (not just ordering out) is what makes the
			// dismissal stick: `applyConflictBubblePresentation` re-fronts the
			// panel on every badge pass while a payload is set. The pool's
			// hourly rate limiter may legitimately re-show it later.
			b.onDismiss = { [weak self] in
				self?.currentConflictPayload = nil
				self?.conflictBubblePanel?.orderOut(nil)
			}
			conflictBubblePanel = b
			return b
		}()
		bubble.configureConflict(origin: payload.origin)
		repositionConflictBubble(badgeFrame: badgePanel?.frame ?? .zero)
		bubble.orderFrontRegardless()
	}

	private func repositionConflictBubble(badgeFrame: CGRect) {
		guard currentConflictPayload != nil, let bubble = conflictBubblePanel else { return }
		bubble.reposition(aboveMinimalistStrip: badgeFrame, visibleFrame: visibleFrameProvider())
	}

	private func handleBubbleDismiss() {
		currentAttention = nil
		currentActivity = .idle
		badgeView.resetPromptTimer()
		bubblePanel?.orderOut(nil)
		applyBadge()
		onAttentionDismissed?()
	}
}


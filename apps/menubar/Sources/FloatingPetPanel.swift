import AppKit
import SpriteKit

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

	init(
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
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
		// Right-click "Force Idle" affordance, shown only while non-idle.
		badgeView.onForceIdleRequested = { [weak self] in
			self?.onForceIdle?()
		}
		// Right-click "Rename…" affordance, offered only while a session number
		// is assigned. This panel never writes the sidecar itself.
		badgeView.renameHandler = { [weak self] newLabel in
			self?.applySessionLabel(newLabel)
			self?.onRenameRequested?(newLabel)
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

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		currentAttention = payload?.isExpired() == true ? nil : payload
		currentSourceEvent = sourceEvent
		applyBubble()
	}

	func applyPromptSummary(_ summary: String) {
		// Prompt summary is not shown for platform-linked minimalist panels.
	}

	func applyBadgeScale(_ scale: Double) {
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
			// The badge already shows the platform chip directly above the bubble.
			b.showsPlatformChip = false
			bubblePanel = b
			return b
		}()
		bubble.update(payload: payload, sourceEvent: currentSourceEvent)
		repositionBubble(badgeFrame: badgePanel?.frame ?? .zero)
		bubble.orderFrontRegardless()
	}

	private func repositionBubble(badgeFrame: CGRect) {
		guard currentAttention != nil, let bubble = bubblePanel else { return }
		bubble.reposition(relativeTo: badgeFrame, visibleFrame: visibleFrameProvider())
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
			conflictBubblePanel = b
			return b
		}()
		bubble.configureConflict(origin: payload.origin)
		repositionConflictBubble(badgeFrame: badgePanel?.frame ?? .zero)
		bubble.orderFrontRegardless()
	}

	private func repositionConflictBubble(badgeFrame: CGRect) {
		guard currentConflictPayload != nil, let bubble = conflictBubblePanel else { return }
		bubble.reposition(relativeTo: badgeFrame, visibleFrame: visibleFrameProvider())
	}

	private func handleBubbleDismiss() {
		currentAttention = nil
		currentActivity = .idle
		bubblePanel?.orderOut(nil)
		applyBadge()
		onAttentionDismissed?()
	}
}

/// Content view for the minimalist badge panel: hosts the `AnimationBadgeView`
/// and owns the panel drag. Deliberately knows nothing about the attention
/// bubble — that lives in its own panel.
private final class MinimalistBadgeView: NSView {
	private static let hPad: CGFloat = 10
	private static let rowSpacing: CGFloat = 4

	private let animationBadge = AnimationBadgeView(frame: .zero)
	private let sessionBadge = PlatformSessionBadge(frame: .zero)
	private let badgeStack = NSStackView()
	private let outerStack = NSStackView()
	private var currentMetrics = GateBadgeLayout.metrics(scale: 1.0)

	var clampedFrameProvider: ((CGPoint) -> CGRect)?
	/// Fires on every drag step with the live window frame so the controller can
	/// keep the bubble anchored to the badge.
	var onDragMoved: ((CGRect) -> Void)?
	/// Fires once on mouse-up with the final frame for persistence.
	var frameChangeHandler: ((CGRect) -> Void)?
	/// Fires when the user activates the right-click "Hide panel" pill.
	var onHidePanelRequested: (() -> Void)?
	/// Fires when the user activates the right-click "Force Idle" pill. Only shown
	/// while the badge represents a non-idle activity (see `currentActivity`).
	var onForceIdleRequested: (() -> Void)?
	/// Fires with the trimmed/capped label the user commits via the right-click
	/// "Rename…" affordance. Not fired when the user cancels or commits an
	/// empty/whitespace-only label. Mirrors Own mode's `renameHandler`.
	var renameHandler: ((String) -> Void)?
	/// Latest activity the badge is displaying, mirrored so the right-click prompt
	/// can decide whether to offer "Force Idle".
	private var currentActivity: ActivityState = .idle
	private var dragOffsetInScreen: CGPoint?

	private var hidePromptPanel: FloatingPetHidePromptPanel?
	private var hidePromptObservers: [NSObjectProtocol] = []
	private var hidePromptGlobalMouseMonitor: Any?
	private var hidePromptGlobalKeyboardMonitor: Any?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		buildUI()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	deinit {
		removeHidePromptDismissObservers()
	}

	func configureBadge(
		platform: PlatformAttribution?,
		activity: ActivityState,
		metrics: GateBadgeLayout.Metrics
	) {
		currentActivity = activity
		currentMetrics = metrics
		animationBadge.configure(
			text: activity.displayLabel,
			platform: platform,
			inFlight: activity.isInFlight,
			metrics: metrics
		)
		sessionBadge.configure(
			number: currentSessionNumber, label: currentSessionLabel, tooltip: currentSessionTooltip,
			metrics: metrics)
	}

	/// Latest session number/label/tooltip applied via `configureSessionNumber`.
	/// Mirrored so a later `configureBadge` (metrics/activity refresh) can
	/// re-apply them without the caller having to resend them every tick.
	private var currentSessionNumber: Int?
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N". Also prefills the rename alert's text field.
	private var currentSessionLabel: String?
	private var currentSessionTooltip: String?

	/// Shows/hides and labels the session badge row. `nil` number hides the row
	/// entirely (session-pets off, or a plain-origin/combined window). `label`,
	/// when present, replaces "Session N" with the user's rename; `tooltip` is
	/// the delayed hover tooltip showing the session's last submitted prompt.
	func configureSessionNumber(_ number: Int?, label: String? = nil, tooltip: String? = nil) {
		currentSessionNumber = number
		currentSessionLabel = label
		currentSessionTooltip = tooltip
		sessionBadge.configure(number: number, label: label, tooltip: tooltip, metrics: currentMetrics)
	}

	/// Width the badge content needs plus horizontal padding. When the session
	/// row is visible, the wider of the two rows drives the panel width.
	var badgePreferredWidth: CGFloat {
		var width = animationBadge.preferredSize.width
		if !sessionBadge.isHidden {
			width = max(width, sessionBadge.intrinsicContentSize.width)
		}
		return width + Self.hPad * 2
	}

	// MARK: - Drag

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		dismissHidePrompt()
		let point = NSEvent.mouseLocation
		dragOffsetInScreen = CGPoint(
			x: point.x - window.frame.origin.x,
			y: point.y - window.frame.origin.y
		)
	}

	override func mouseDragged(with event: NSEvent) {
		guard let window, let dragOffsetInScreen else { return }
		let point = NSEvent.mouseLocation
		let origin = CGPoint(
			x: point.x - dragOffsetInScreen.x,
			y: point.y - dragOffsetInScreen.y
		)
		let frame = clampedFrameProvider?(origin) ?? CGRect(origin: origin, size: window.frame.size)
		window.setFrame(frame, display: true)
		onDragMoved?(frame)
	}

	override func mouseUp(with event: NSEvent) {
		dragOffsetInScreen = nil
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
	}

	// MARK: - Hide-panel affordance

	/// Right-click anywhere on the badge (platform chip or activity pill) surfaces
	/// the same frosted "Hide" pill Own mode uses, retitled "Hide panel" since it
	/// hides the whole minimalist strip.
	override func rightMouseDown(with event: NSEvent) {
		guard window != nil else { return }
		if hidePromptPanel != nil {
			dismissHidePrompt()
		}
		presentHidePrompt(for: event)
	}

	func dismissHidePromptIfPresent() {
		dismissHidePrompt()
	}

	private func presentHidePrompt(for event: NSEvent) {
		guard let window else { return }
		dismissHidePrompt()
		let offersForceIdle = FloatingPetHidePrompt.offersForceIdle(for: currentActivity)
		FloatingPetPromptCoordinator.shared.willPresent(owner: self) { [weak self] in
			self?.dismissHidePrompt()
		}
		let anchorInScreen = window.convertPoint(toScreen: event.locationInWindow)
		var items: [FloatingPetPromptItem] = []
		// Escape hatch when the pet is stuck mid-animation (rate-limited or
		// manually-stopped prompt): sits above "Hide panel" as the primary action.
		if offersForceIdle {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.forceIdleTitle) { [weak self] in
					self?.dismissHidePrompt()
					self?.onForceIdleRequested?()
				})
		}
		// Rename is only meaningful for a session-keyed strip (one that
		// currently carries a session number); sits above "Hide panel",
		// mirroring Own mode's placement.
		if currentSessionNumber != nil {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.renameTitle) { [weak self] in
					self?.dismissHidePrompt()
					self?.presentRenameAlert()
				})
		}
		items.append(
			FloatingPetPromptItem(title: FloatingPetHidePrompt.panelTitle) { [weak self] in
				self?.dismissHidePrompt()
				self?.onHidePanelRequested?()
			})
		let promptSize = FloatingPetHidePrompt.stackSize(titles: items.map(\.title))
		let visibleFrame = window.screen?.visibleFrame
			?? NSScreen.main?.visibleFrame
			?? CGRect(x: 0, y: 0, width: 800, height: 600)
		let screenFrame = FloatingPetHidePrompt.screenFrame(
			anchor: anchorInScreen,
			promptSize: promptSize,
			visibleFrame: visibleFrame
		)
		let panel = FloatingPetHidePromptPanel(frame: screenFrame, items: items)
		panel.orderFrontRegardless()
		hidePromptPanel = panel
		installHidePromptDismissObservers()
	}

	/// Presents a modal text-entry alert for renaming this session. Trims and
	/// caps the result at `SessionLabelStore.maxLength`; an empty/whitespace
	/// result (or Cancel) is treated as "no rename" and `renameHandler` is not
	/// fired. Mirrors Own mode's `presentRenameAlert`.
	private func presentRenameAlert() {
		let alert = NSAlert()
		alert.messageText = "Rename Session"
		alert.informativeText = "Up to \(SessionLabelStore.maxLength) characters."
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")
		let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = currentSessionLabel ?? ""
		alert.accessoryView = field
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let normalized = SessionLabelStore.normalize(field.stringValue)
		guard !normalized.isEmpty else { return }
		renameHandler?(normalized)
	}

	private func dismissHidePrompt() {
		FloatingPetPromptCoordinator.shared.didDismiss(owner: self)
		guard hidePromptPanel != nil else { return }
		hidePromptPanel?.orderOut(nil)
		hidePromptPanel = nil
		removeHidePromptDismissObservers()
	}

	private func installHidePromptDismissObservers() {
		removeHidePromptDismissObservers()

		hidePromptObservers.append(
			NotificationCenter.default.addObserver(
				forName: NSApplication.didResignActiveNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor in self?.dismissHidePrompt() }
			}
		)

		// Any click outside the pill dismisses it. Clicks landing on the pill are
		// handled by the pill's own view before this monitor sees them.
		hidePromptGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown]
		) { [weak self] _ in
			Task { @MainActor in self?.dismissHidePrompt() }
		}

		// Dismiss on any keyboard input (including app switchers) so the pill never
		// lingers over the UI while the user changes apps or windows.
		hidePromptGlobalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.keyDown, .keyUp, .flagsChanged]
		) { [weak self] _ in
			Task { @MainActor in self?.dismissHidePrompt() }
		}
	}

	private func removeHidePromptDismissObservers() {
		for observer in hidePromptObservers {
			NotificationCenter.default.removeObserver(observer)
		}
		hidePromptObservers.removeAll()
		if let hidePromptGlobalMouseMonitor {
			NSEvent.removeMonitor(hidePromptGlobalMouseMonitor)
			self.hidePromptGlobalMouseMonitor = nil
		}
		if let hidePromptGlobalKeyboardMonitor {
			NSEvent.removeMonitor(hidePromptGlobalKeyboardMonitor)
			self.hidePromptGlobalKeyboardMonitor = nil
		}
	}

	// MARK: - Layout

	private func buildUI() {
		wantsLayer = true
		badgeStack.orientation = .horizontal
		badgeStack.alignment = .centerY
		badgeStack.spacing = 8
		badgeStack.addArrangedSubview(animationBadge)

		sessionBadge.isHidden = true

		outerStack.orientation = .vertical
		// `.leading` (not `.centerX`) keeps the chip+pill row pinned at `hPad` from
		// the panel's left edge regardless of the session badge row's width — see
		// the matching note on `AnimationBadgeView.outerStack`.
		outerStack.alignment = .leading
		outerStack.spacing = Self.rowSpacing
		outerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(outerStack)
		outerStack.addArrangedSubview(badgeStack)
		outerStack.addArrangedSubview(sessionBadge)
		NSLayoutConstraint.activate([
			outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
			outerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.hPad),
			outerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}
}

@MainActor
final class FloatingPetPanelController: FloatingPetPanelManaging {
	private var codexPet: CodexPet
	private var codogotchiPet: CodogotchiPet?
	private let demoFrameInterval: TimeInterval?
	private var idleEscalationConfig: IdleEscalationConfig
	private let initialIdleAge: TimeInterval
	private let clock: () -> Date
	private let visibleFrameProvider: () -> CGRect
	private var panel: NSPanel?
	private var scene: FloatingPetScene?
	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentSicknessLevel: SicknessLevel = .none
	private var frameChangeHandler: ((CGRect) -> Void)?
	var onHideFloatingPet: (() -> Void)?
	/// Called when the user activates the right-click "Force Idle" affordance
	/// (only offered while non-idle). The app wires this to rewrite this pet's
	/// `state.d/` slice back to idle — an escape hatch for a stuck animation.
	var onForceIdle: (() -> Void)?
	/// Called when the user dismisses or focuses away from the attention bubble.
	/// Intended for the caller to persist the idle state back to state.json so a
	/// relaunch does not re-show the bubble.
	var onAttentionDismissed: (() -> Void)?
	/// Called when the user clicks the P15.08 conflict bubble's action button.
	/// Wired by the caller to open Settings > Customization.
	var onOpenSettingsRequested: (() -> Void)?

	// Attention bubble — shown below the pet when a non-expired attention payload is active.
	private var attentionBubble: AttentionBubblePanel?
	/// Separate bubble panel for P15.08's conflict notice — distinct from
	/// `attentionBubble` so the two presentations never contend for the same
	/// field (a blocked origin's rendered sessions are, by definition, active
	/// and unlikely to also carry a real attention payload, but keeping them
	/// independent avoids relying on that).
	private var conflictBubble: SpeechBubblePanel?
	private var gateBadgePanel: GateBadgePanel?
	// Animation badge — always shown while the pet is visible; labels the current
	// activity-state animation, anchored bottom-left inside the pet frame.
	private var animationBadgePanel: AnimationBadgePanel?
	private var lastPanelFrame: CGRect = .zero
	private var isPanelShown = false
	private var attentionActive = false
	/// Mirrors `attentionActive` for the P15.08 conflict bubble: true while
	/// `applyConflictBubble` last received a non-nil payload, so drag/resize
	/// re-anchoring (`reanchorChrome`) keeps the conflict bubble glued to the
	/// panel the same way it does the real attention bubble.
	private var conflictActive = false
	private var gateBadgeContent: GateBadgeContent?
	/// Mirror of the scene's idle-escalation level, used for the badge label.
	private var currentEscalation: IdleEscalation = .none
	/// Platform attribution from the latest `source_event.origin`, resolved to a
	/// logo chip shown immediately left of the animation badge. `nil` when the
	/// origin is absent or non-platform, in which case no chip is drawn.
	private var currentPlatform: PlatformAttribution?
	/// Session number assigned to this window by `FloatingPetWindowPool`, or
	/// `nil` for a plain-origin/combined window. Drives the `PlatformSessionBadge`
	/// row beneath the platform chip + animation badge.
	private var currentSessionNumber: Int?
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N".
	private var currentSessionLabel: String?
	/// Last submitted prompt for this session, shown as a delayed hover
	/// tooltip on the session badge.
	private var currentSessionTooltip: String?
	/// Fired with the trimmed/capped label the user commits via the
	/// right-click rename affordance. Wired by the caller (`MenubarApp`) to
	/// persist to `SessionLabelStore` — this panel never writes the sidecar.
	var onRenameRequested: ((String) -> Void)?
	/// Fired when the user confirms the right-click "Prune Session" affordance
	/// (P15.07). Wired by the caller (`MenubarApp`) to destroy the session's
	/// slice, free-list number, and label — this panel never touches those
	/// stores directly, it only reports the user's confirmed intent.
	var onPruneRequested: (() -> Void)?

	// RPG HUD — shown on hover, and transiently revealed on animation moments
	// (lose/gain a half-heart, level up) when not hovering.
	private var rpgHUDPanel: RPGHUDPanel?
	private let rpgHUDViewModel = RPGHUDViewModel()
	private var isHoveringPet = false
	/// Local event monitor installed when the pointer leaves the pet frame while
	/// the HUD is visible — keeps the HUD alive until the pointer also exits the
	/// HUD panel itself.
	private var hudHoverMonitor: Any?
	// Ghosted (0 hearts): the pet renders grayscale and a persistent tombstone is
	// shown to the right of the pet. Both are part of the RPG HUD — they clear
	// when at least a half-heart returns *or* the HUD is disabled. The active
	// decision lives in `rpgHUDViewModel.showsGhostPresentation`.
	private var tombstonePanel: TombstonePanel?
	/// Regeneration meter shown beside the tombstone while ghosted, visualizing how
	/// close the pet is to reviving (active-minute carry toward the first
	/// half-heart). Shares the tombstone's lifecycle via `showsReviveMeter`.
	private var regenMeterPanel: RegenMeterPanel?
	/// Pending auto-hide for a transient (non-hover) reveal.
	private var hudAutoHideWork: DispatchWorkItem?
	/// Set by the view-model's flash callback during `update`, signalling that
	/// the current snapshot crossed an animation threshold worth revealing.
	private var hudFlashPending = false
	/// Seconds a transient reveal stays on screen before fading out.
	private static let hudTransientSeconds: TimeInterval = 4.0
	/// When true (HUD demo), the HUD is pinned visible regardless of hover.
	private var hudDemoActive = false
	/// When true (runtime `hud-pin` sentinel), the HUD stays visible regardless of
	/// hover. Unlike `hudDemoActive` this does NOT suppress live RPG updates, so a
	/// scripted demo (e.g. `tcha`) can keep feeding hearts/level while the HUD is
	/// forced on.
	private var hudPinned = false
	/// HUD forced visible (sweep demo or runtime pin) regardless of hover.
	private var hudForcedVisible: Bool { hudDemoActive || hudPinned }
	/// True while the user is actively dragging the pet. The RPG HUD (hearts,
	/// heart-regen bar, XP ring + its content) and the ghost chrome (tombstone +
	/// revival meter) are fully ordered out for the duration so they neither render
	/// nor re-anchor each drag tick — repositioning them per `mouseDragged` was the
	/// main source of drag lag. The correct presentation is restored on mouse-up.
	private var isDraggingPet = false

	init(
		codexPet: CodexPet,
		codogotchiPet: CodogotchiPet?,
		demoFrameInterval: TimeInterval? = nil,
		idleEscalationConfig: IdleEscalationConfig = .production,
		initialIdleAge: TimeInterval = 0,
		clock: @escaping () -> Date = Date.init,
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
		}
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.demoFrameInterval = demoFrameInterval
		self.idleEscalationConfig = idleEscalationConfig
		self.initialIdleAge = initialIdleAge
		self.clock = clock
		self.visibleFrameProvider = visibleFrameProvider
	}

	func show(frame: CGRect) {
		let panel = self.panel ?? makePanel(frame: frame)
		panel.setFrame(frame, display: true)

		if scene == nil {
			let scene = FloatingPetScene(
				size: frame.size,
				codexPet: codexPet,
				codogotchiPet: codogotchiPet,
				demoFrameInterval: demoFrameInterval,
				idleEscalationConfig: idleEscalationConfig,
				initialIdleAge: initialIdleAge,
				clock: clock
			)
			scene.onIdleEscalationChange = { [weak self] level in
				guard let self else { return }
				self.currentEscalation = level
				self.repositionAndShowAnimationBadge()
			}
			scene.update(state: currentState, visualMode: currentMode)
			scene.setSicknessLevel(currentSicknessLevel)
			self.scene = scene
			(panel.contentView as? FloatingPetInteractionView)?.presentScene(scene)
		} else {
			scene?.size = frame.size
			scene?.update(state: currentState, visualMode: currentMode)
			scene?.setSicknessLevel(currentSicknessLevel)
		}

		panel.orderFrontRegardless()
		self.panel = panel
		if let interactionView = panel.contentView as? FloatingPetInteractionView {
			interactionView.frame = NSRect(origin: .zero, size: frame.size)
			interactionView.setSpriteKitPaused(false)
			interactionView.prepareForDisplay()
		}
		scene?.resumeAnimation()

		isPanelShown = true
		lastPanelFrame = frame
		if attentionActive {
			repositionAndShowBubble()
		}
		if conflictActive {
			repositionAndShowConflictBubble()
		}
		if gateBadgeContent != nil {
			repositionAndShowGateBadge()
		}
		repositionAndShowAnimationBadge()
		updateGhostPresentation()
	}

	func hide() {
		(panel?.contentView as? FloatingPetInteractionView)?.dismissHidePromptIfPresent()
		scene?.pauseAnimation()
		(panel?.contentView as? FloatingPetInteractionView)?.setSpriteKitPaused(true)
		panel?.orderOut(nil)
		isPanelShown = false
		attentionBubble?.orderOut(nil)
		conflictBubble?.orderOut(nil)
		gateBadgePanel?.orderOut(nil)
		animationBadgePanel?.orderOut(nil)
		tombstonePanel?.orderOut(nil)
		regenMeterPanel?.orderOut(nil)
		cancelHUDAutoHide()
		cancelHUDHoverMonitor()
		rpgHUDPanel?.hideImmediately()
	}

	/// Swap in new pet loaders and immediately repaint the current state.
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		// Rebuild the scene with new pets when it's already visible.
		scene?.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		guard let payload else {
			conflictActive = false
			conflictBubble?.orderOut(nil)
			return
		}
		conflictActive = true
		let bubble = conflictBubble ?? {
			let b = SpeechBubblePanel()
			b.onAction = { [weak self] in self?.onOpenSettingsRequested?() }
			conflictBubble = b
			return b
		}()
		bubble.configureConflict(origin: payload.origin)
		if isPanelShown {
			repositionAndShowConflictBubble()
		}
	}

	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {
		idleEscalationConfig = config
		scene?.updateIdleEscalationConfig(config)
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		guard let payload, !payload.isExpired() else {
			attentionActive = false
			attentionBubble?.orderOut(nil)
			// Bubble cleared — the animation badge can take the below-pet slot again.
			repositionAndShowAnimationBadge()
			return
		}
		attentionActive = true
		// Bubble is taking over the below-pet slot — hide the redundant badge.
		repositionAndShowAnimationBadge()
		let bubble = attentionBubble ?? {
			let b = AttentionBubblePanel()
			b.onDismiss = { [weak self] in self?.handleBubbleDismiss() }
			attentionBubble = b
			return b
		}()
		bubble.update(payload: payload, sourceEvent: sourceEvent)
		if isPanelShown {
			repositionAndShowBubble()
		}
	}

	func applyGateBadge(content: GateBadgeContent?) {
		gateBadgeContent = content
		guard let content else {
			gateBadgePanel?.orderOut(nil)
			return
		}
		let badge = gateBadgePanel ?? {
			let panel = GateBadgePanel()
			gateBadgePanel = panel
			return panel
		}()
		badge.update(content: content, relativeTo: lastPanelFrame)
		if isPanelShown {
			repositionAndShowGateBadge()
		}
	}

	func applyPlatform(origin: String?) {
		let platform = PlatformAttribution(origin: origin)
		guard platform != currentPlatform else { return }
		currentPlatform = platform
		// Origin can change without the activity state changing (e.g. claude_code
		// idle → cursor idle), so refresh the badge directly here rather than
		// relying on an `apply(state:)` tick.
		repositionAndShowAnimationBadge()
	}

	func applySessionNumber(_ number: Int?) {
		guard currentSessionNumber != number else { return }
		currentSessionNumber = number
		(panel?.contentView as? FloatingPetInteractionView)?.hasActiveSessionBadge = number != nil
		repositionAndShowAnimationBadge()
	}

	func applySessionLabel(_ label: String?) {
		guard currentSessionLabel != label else { return }
		currentSessionLabel = label
		(panel?.contentView as? FloatingPetInteractionView)?.currentSessionLabel = label
		repositionAndShowAnimationBadge()
	}

	func applySessionTooltip(_ summary: String?) {
		guard currentSessionTooltip != summary else { return }
		currentSessionTooltip = summary
		repositionAndShowAnimationBadge()
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		rpgHUDViewModel.onFlash = { [weak self] event in
			guard let self else { return }
			self.hudFlashPending = true
			self.rpgHUDPanel?.flash(event)
			if event == .levelUp {
				self.scene?.playLevelUpEffect()
			}
		}
		hudFlashPending = false
		currentSicknessLevel = SicknessLevel(halfHearts: halfHearts)
		scene?.setSicknessLevel(currentSicknessLevel)
		rpgHUDViewModel.update(
			halfHearts: halfHearts,
			levelFraction: levelFraction,
			level: level,
			activeMinutes: activeMinutes,
			hudEnabled: hudEnabled
		)
		updateGhostPresentation()
		guard isPanelShown else { return }
		guard rpgHUDViewModel.isHUDEnabled else {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			rpgHUDPanel?.hideImmediately()
			return
		}
		if isHoveringPet || hudForcedVisible {
			showHUDForHover()
		} else if hudFlashPending {
			revealHUDTransiently()
		}
	}

	/// Apply a live change to the HUD-enabled setting (Settings → RPG toggle)
	/// without waiting for the next RPG state poll. Disabling hides the HUD
	/// immediately; enabling restores the normal hover-driven reveal (the HUD
	/// pops back on the next hover, or right away if the pet is hovered).
	func setRPGHUDEnabled(_ enabled: Bool) {
		rpgHUDViewModel.setHUDEnabled(enabled)
		// The tombstone + grayscale are part of the HUD: disabling recolors the pet
		// and drops the tombstone even mid-ghost; re-enabling restores them if ghosted.
		updateGhostPresentation()
		guard isPanelShown else { return }
		guard rpgHUDViewModel.isHUDEnabled else {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			rpgHUDPanel?.hideImmediately()
			return
		}
		if isHoveringPet || hudForcedVisible {
			showHUDForHover()
		}
	}

	func setHUDDemoActive(_ active: Bool) {
		hudDemoActive = active
		refreshForcedHUDVisibility()
	}

	func setHUDPinned(_ pinned: Bool) {
		hudPinned = pinned
		refreshForcedHUDVisibility()
	}

	/// Reconcile the HUD's pinned/demo "always visible" intent with the panel.
	/// Shows the HUD when either force is active; otherwise lets a non-hovered
	/// HUD fade back to the normal hover-driven behavior.
	private func refreshForcedHUDVisibility() {
		if hudForcedVisible {
			showHUDForHover()
		} else if !isHoveringPet {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			rpgHUDPanel?.fadeOut()
		}
	}

	private func handleBubbleDismiss() {
		attentionActive = false
		apply(state: .idle, visualMode: currentMode)
		onAttentionDismissed?()
	}

	private func repositionAndShowConflictBubble() {
		guard let bubble = conflictBubble else { return }
		bubble.reposition(
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		bubble.orderFrontRegardless()
	}

	private func repositionAndShowBubble() {
		guard let bubble = attentionBubble else { return }
		bubble.reposition(
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		bubble.orderFrontRegardless()
	}

	private func repositionAndShowGateBadge() {
		guard let content = gateBadgeContent else { return }
		let badge = gateBadgePanel ?? {
			let panel = GateBadgePanel()
			gateBadgePanel = panel
			return panel
		}()
		badge.reposition(
			content: content,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		badge.orderFrontRegardless()
	}

	/// Apply the 0-HP ghost presentation: grayscale the sprite and show a persistent
	/// tombstone to the right of the pet, or clear both when alive or when the
	/// HUD is disabled (the tombstone + grayscale belong to the RPG HUD).
	/// The sprite grayscale is applied even while hidden so it is correct on the
	/// next show; the tombstone panel is only ordered in while the pet is visible.
	private func updateGhostPresentation() {
		let active = rpgHUDViewModel.showsGhostPresentation
		scene?.setGhosted(active)
		guard isPanelShown, active else {
			tombstonePanel?.orderOut(nil)
			regenMeterPanel?.orderOut(nil)
			return
		}
		let tomb = tombstonePanel ?? {
			let p = TombstonePanel()
			tombstonePanel = p
			return p
		}()
		tomb.reposition(
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
		tomb.orderFrontRegardless()

		// Revival meter rides alongside the tombstone, gated on the same flag.
		let meter = regenMeterPanel ?? {
			let p = RegenMeterPanel()
			regenMeterPanel = p
			return p
		}()
		meter.reposition(
			progress: rpgHUDViewModel.reviveProgress,
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
		meter.orderFrontRegardless()
	}

	/// Lazily create the HUD panel and push the latest state + position into it.
	private func refreshHUDContent() -> RPGHUDPanel? {
		guard rpgHUDViewModel.isHUDEnabled else { return nil }
		let hud = rpgHUDPanel ?? {
			let p = RPGHUDPanel()
			rpgHUDPanel = p
			return p
		}()
		hud.reposition(
			hearts: rpgHUDViewModel.hearts,
			ringFraction: rpgHUDViewModel.ringFraction,
			level: rpgHUDViewModel.level,
			regenProgress: rpgHUDViewModel.heartRegenProgress,
			showsRegenBar: rpgHUDViewModel.showsHeartRegenBar,
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
		return hud
	}

	/// The pet's opaque silhouette in global screen coordinates, used to anchor
	/// the HUD beside the real sprite. `nil` when no sprite is loaded.
	private func currentSpriteAnchorGlobal() -> CGRect? {
		guard let local = scene?.currentSpriteOpaqueRect() else { return nil }
		return local.offsetBy(dx: lastPanelFrame.minX, dy: lastPanelFrame.minY)
	}

	/// Steady reveal while hovering: cancel any transient timer, hold visible.
	/// Skipped mid-drag — an RPG-state poll tick can land while the pointer is
	/// still over the pet (true for the whole drag), and reposition here would
	/// glue the HUD to a stale frame despite the drag's own order-out/guard.
	private func showHUDForHover() {
		guard !isDraggingPet else { return }
		guard isPanelShown, rpgHUDViewModel.isHUDEnabled else { return }
		cancelHUDAutoHide()
		cancelHUDHoverMonitor()
		refreshHUDContent()?.ensureVisible()
	}

	/// Hover ended: fade out unless a transient reveal is mid-flight, or the
	/// pointer has moved directly onto the HUD panel — in which case arm a monitor
	/// to wait until it leaves both the HUD and the pet frame.
	private func hideHUDForHoverEnd() {
		guard !hudDemoActive else { return }
		guard hudAutoHideWork == nil else { return }
		if rpgHUDPanel?.frame.contains(NSEvent.mouseLocation) == true {
			installHUDHoverMonitor()
			return
		}
		rpgHUDPanel?.fadeOut()
	}

	/// Brief reveal on an animation moment while not hovering: fade in, then fade
	/// out after `hudTransientSeconds` unless the pointer started hovering.
	/// Skipped mid-drag for the same reason as `showHUDForHover`.
	private func revealHUDTransiently() {
		guard !isDraggingPet else { return }
		guard isPanelShown, rpgHUDViewModel.isHUDEnabled else { return }
		refreshHUDContent()?.fadeIn()
		cancelHUDAutoHide()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.hudAutoHideWork = nil
			if !self.isHoveringPet {
				self.rpgHUDPanel?.fadeOut()
			}
		}
		hudAutoHideWork = work
		DispatchQueue.main.asyncAfter(
			deadline: .now() + Self.hudTransientSeconds, execute: work)
	}

	private func cancelHUDAutoHide() {
		hudAutoHideWork?.cancel()
		hudAutoHideWork = nil
	}

	private func cancelHUDHoverMonitor() {
		if let monitor = hudHoverMonitor {
			NSEvent.removeMonitor(monitor)
			hudHoverMonitor = nil
		}
	}

	/// Arm a local event monitor that fades the HUD once the pointer exits both
	/// the HUD panel frame and the pet panel frame. Used when hover leaves the pet
	/// but the pointer lands directly on the HUD — the appear trigger is unaffected
	/// (the HUD still only appears on pet-hover or animation flash).
	private func installHUDHoverMonitor() {
		cancelHUDHoverMonitor()
		hudHoverMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.mouseMoved, .leftMouseDragged]
		) { [weak self] event in
			Task { @MainActor in
				guard let self else { return }
				let pt = NSEvent.mouseLocation
				let inHUD = self.rpgHUDPanel?.frame.contains(pt) == true
				let inPet = self.lastPanelFrame.contains(pt)
				guard !inHUD, !inPet else { return }
				self.cancelHUDHoverMonitor()
				if !self.isHoveringPet, !self.hudDemoActive, self.hudAutoHideWork == nil {
					self.rpgHUDPanel?.fadeOut()
				}
			}
			return event
		}
	}

	private func repositionAndShowAnimationBadge() {
		guard isPanelShown else { return }
		guard AnimationBadgeLayout.isVisible(attentionActive: attentionActive) else {
			animationBadgePanel?.orderOut(nil)
			return
		}
		let badge = animationBadgePanel ?? {
			let panel = AnimationBadgePanel()
			animationBadgePanel = panel
			return panel
		}()
		badge.reposition(
			label: animationBadgeLabel,
			platform: currentPlatform,
			inFlight: animationBadgeInFlight,
			sessionNumber: currentSessionNumber,
			sessionLabel: currentSessionLabel,
			sessionTooltip: currentSessionTooltip,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		badge.orderFrontRegardless()
	}

	/// Badge copy: the escalated idle label ("Impatient"/"Frustrated") when the
	/// agent is idle and has escalated, otherwise the current state's label.
	private var animationBadgeLabel: String {
		if currentState == .idle, let escalated = currentEscalation.badgeLabel {
			return escalated
		}
		return currentState.displayLabel
	}

	/// Whether the animation badge label should run the scanning shimmer. Tracks
	/// the underlying activity state: escalated-idle stays `.idle` and so reads
	/// static, while every active working state shimmers. See `ActivityState.isInFlight`.
	private var animationBadgeInFlight: Bool {
		currentState.isInFlight
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		currentState = state
		currentMode = visualMode
		scene?.update(state: state, visualMode: visualMode)
		// Keep the right-click prompt's "Force Idle" gate in sync with the live
		// state so the escape hatch only appears while the pet is non-idle.
		(panel?.contentView as? FloatingPetInteractionView)?.isForceIdleAvailable =
			FloatingPetHidePrompt.offersForceIdle(for: state)
		// Refresh the animation badge label; no-op while the pet is hidden.
		repositionAndShowAnimationBadge()
	}

	func setInteraction(_ interaction: FloatingInteraction?) {
		scene?.setInteraction(interaction)
	}

	func decrementIdleEscalation() {
		scene?.decrementIdleEscalation()
	}

	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
		frameChangeHandler = handler
		if let view = panel?.contentView as? FloatingPetInteractionView {
			wireFrameHandlers(on: view)
		}
	}

	/// Wire both the live (per-drag-tick) and committed (mouseUp) frame sinks.
	private func wireFrameHandlers(on view: FloatingPetInteractionView) {
		view.liveFrameChangeHandler = { [weak self] frame in
			self?.reanchorChrome(to: frame)
		}
		view.frameChangeHandler = { [weak self] frame in
			self?.handleCommittedFrameChange(frame)
		}
		view.onDragStateChange = { [weak self] dragging in
			self?.setPetDragging(dragging)
		}
	}

	/// Drag begin/end notification from the interaction view. Hides the RPG HUD and
	/// ghost chrome for the duration of a drag (a pure perf win — see `isDraggingPet`)
	/// and restores the correct presentation on mouse-up.
	private func setPetDragging(_ dragging: Bool) {
		guard isDraggingPet != dragging else { return }
		isDraggingPet = dragging
		if dragging {
			// Order the HUD chrome fully out so it stops rendering and re-anchoring.
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			rpgHUDPanel?.hideImmediately()
			tombstonePanel?.orderOut(nil)
			regenMeterPanel?.orderOut(nil)
		} else {
			// Restore whatever should be on screen now that the drag has ended.
			updateGhostPresentation()
			if isHoveringPet || hudForcedVisible {
				showHUDForHover()
			}
		}
	}

	/// Live re-anchor: keep `lastPanelFrame` current and glue the attention
	/// bubble to the pet on every drag/resize tick. No persistence — runs hot.
	private func reanchorChrome(to frame: CGRect) {
		lastPanelFrame = frame
		guard isPanelShown else { return }
		if attentionActive {
			attentionBubble?.reposition(
				relativeTo: lastPanelFrame,
				visibleFrame: visibleFrameProvider()
			)
		}
		if conflictActive {
			conflictBubble?.reposition(
				relativeTo: lastPanelFrame,
				visibleFrame: visibleFrameProvider()
			)
		}
		if let content = gateBadgeContent {
			gateBadgePanel?.reposition(
				content: content,
				relativeTo: lastPanelFrame,
				visibleFrame: visibleFrameProvider()
			)
		}
		animationBadgePanel?.reposition(
			label: animationBadgeLabel,
			platform: currentPlatform,
			inFlight: animationBadgeInFlight,
			sessionNumber: currentSessionNumber,
			sessionLabel: currentSessionLabel,
			sessionTooltip: currentSessionTooltip,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		// While dragging the pet, the HUD + ghost chrome are ordered out for perf
		// (see `isDraggingPet`); skip re-anchoring them entirely until mouse-up.
		guard !isDraggingPet else { return }
		// Keep the HUD glued to the pet on non-drag live moves (e.g. resize) while
		// it is visible — steady (hover), pinned (demo), or mid transient reveal.
		if rpgHUDViewModel.isHUDEnabled, isHoveringPet || hudDemoActive || hudAutoHideWork != nil {
			rpgHUDPanel?.reposition(
				hearts: rpgHUDViewModel.hearts,
				ringFraction: rpgHUDViewModel.ringFraction,
				level: rpgHUDViewModel.level,
				regenProgress: rpgHUDViewModel.heartRegenProgress,
				showsRegenBar: rpgHUDViewModel.showsHeartRegenBar,
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
		}
		// The tombstone is persistent while ghosted — keep it glued to the pet too.
		if rpgHUDViewModel.showsGhostPresentation {
			tombstonePanel?.reposition(
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
			regenMeterPanel?.reposition(
				progress: rpgHUDViewModel.reviveProgress,
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
		}
	}

	/// Committed frame change (mouseUp): re-anchor once more, then forward to the
	/// external persistence handler.
	private func handleCommittedFrameChange(_ frame: CGRect) {
		reanchorChrome(to: frame)
		frameChangeHandler?(frame)
	}

	private func syncSceneSizeToPanel(_ panelSize: CGSize) {
		guard let scene else { return }
		let previous = scene.size
		guard previous != panelSize else { return }
		scene.size = panelSize
	}

	private func makePanel(frame: CGRect) -> NSPanel {
		let panel = NSPanel(
			contentRect: frame,
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
		panel.acceptsMouseMovedEvents = true
		let interactionView = makeContentView(frame: frame, panel: panel)
		interactionView.autoresizingMask = [.width, .height]
		panel.contentView = interactionView
		return panel
	}

	private func makeContentView(frame: CGRect, panel: NSPanel) -> FloatingPetInteractionView {
		let view = FloatingPetInteractionView(
			frame: CGRect(origin: .zero, size: frame.size),
			visibleFrameProvider: { [weak panel, visibleFrameProvider] in
				panel?.screen?.visibleFrame ?? visibleFrameProvider()
			},
			interactionHandler: { [weak self] interaction in
				self?.scene?.setInteraction(interaction)
			},
			sceneSizeHandler: { [weak self] size in
				self?.syncSceneSizeToPanel(size)
			}
		)
		wireFrameHandlers(on: view)
		view.hideFloatingPetHandler = { [weak self] in
			self?.onHideFloatingPet?()
		}
		view.isForceIdleAvailable = FloatingPetHidePrompt.offersForceIdle(for: currentState)
		view.forceIdleHandler = { [weak self] in
			self?.onForceIdle?()
		}
		view.hasActiveSessionBadge = currentSessionNumber != nil
		view.currentSessionLabel = currentSessionLabel
		view.renameHandler = { [weak self] newLabel in
			self?.currentSessionLabel = newLabel
			self?.onRenameRequested?(newLabel)
			self?.repositionAndShowAnimationBadge()
		}
		view.pruneHandler = { [weak self] in
			self?.onPruneRequested?()
		}
		view.holdDeEscalationHandler = { [weak self] in
			self?.scene?.decrementIdleEscalation()
		}
		view.onHoverChange = { [weak self] isHovering in
			guard let self else { return }
			self.isHoveringPet = isHovering
			if isHovering {
				self.showHUDForHover()
			} else {
				self.hideHUDForHoverEnd()
				self.rpgHUDPanel?.setRingHovered(false)
			}
		}
		view.onPointerUpdate = { [weak self] in
			guard let self else { return }
			let screenPt = NSEvent.mouseLocation
			self.rpgHUDPanel?.setRingHovered(
				self.rpgHUDPanel?.ringScreenRect()?.contains(screenPt) == true
			)
		}
		return view
	}
}

enum GateBadgeLayout {
	static let margin: CGFloat = 4
	static let baselinePetWidth: CGFloat = 220

	struct Metrics: Equatable {
		let horizontalPadding: CGFloat
		let verticalPadding: CGFloat
		let interBadgeSpacing: CGFloat
		let cornerRadius: CGFloat
		let badgeHeight: CGFloat
		let fontSize: CGFloat
	}

	/// Hard floor/ceiling accepted by `metrics(scale:)`. Wider than the range
	/// Own mode can actually reach (see `achievableMinScale`/`achievableMaxScale`)
	/// so this stays a safety clamp, not a UI bound.
	static let minScale: CGFloat = 0.75
	static let maxScale: CGFloat = 1.5

	/// Smallest/largest scale Own mode can actually reach, derived from
	/// `FloatingFramePolicy`'s pet-panel size bounds. The Minimalist badge-size
	/// slider in Settings uses this narrower range — not `minScale`/`maxScale` —
	/// so "Large" never exceeds what an Own-mode badge ever renders at.
	static let achievableMinScale: CGFloat = max(
		minScale, FloatingFramePolicy.minimumSize.width / baselinePetWidth
	)
	static let achievableMaxScale: CGFloat = min(
		maxScale, FloatingFramePolicy.maximumSize.width / baselinePetWidth
	)

	static func metrics(for petFrame: CGRect) -> Metrics {
		metrics(scale: petFrame.width / baselinePetWidth)
	}

	static func metrics(scale rawScale: CGFloat) -> Metrics {
		let scale = max(minScale, min(maxScale, rawScale))
		// Base values net +14% over the original 8/4/5/7/20/8.7 set (+20% then
		// -5%) so the whole badge family (platform chip, animation/session
		// badges, ticket and gate tokens — all single-sourced from this
		// function) reads larger across the entire scale range, not just at
		// one end.
		return Metrics(
			horizontalPadding: round(9.12 * scale),
			verticalPadding: round(4.56 * scale),
			interBadgeSpacing: round(5.7 * scale),
			cornerRadius: round(7.98 * scale),
			badgeHeight: round(22.8 * scale),
			fontSize: round(9.918 * scale * 10) / 10
		)
	}

	static func frame(relativeTo petFrame: CGRect, badgeSize: CGSize, visibleFrame: CGRect) -> CGRect {
		// Centered on the pet's horizontal midpoint, just above the top border —
		// vertically symmetric with the bottom-centered animation badge.
		let rect = CGRect(
			x: petFrame.midX - badgeSize.width / 2,
			y: petFrame.maxY,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}
}

@MainActor
final class GateBadgePanel: NSPanel {
	private let badgeView = GateBadgeView(frame: .zero)

	init() {
		super.init(
			contentRect: .zero,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		level = .floating
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = true
		contentView = badgeView
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func update(content: GateBadgeContent, relativeTo petFrame: CGRect) {
		badgeView.configure(content: content, metrics: GateBadgeLayout.metrics(for: petFrame))
	}

	/// Own-mode entry point: metrics scale off the pet frame's own width.
	func reposition(content: GateBadgeContent, relativeTo petFrame: CGRect, visibleFrame: CGRect) {
		reposition(
			content: content,
			metrics: GateBadgeLayout.metrics(for: petFrame),
			relativeTo: petFrame,
			visibleFrame: visibleFrame
		)
	}

	/// Minimalist-mode entry point: the anchor frame is a chromeless badge strip,
	/// not a pet sprite, so its width cannot drive `GateBadgeLayout.metrics(for:)`
	/// (baselined against a ~220pt pet). Callers pass the user's chosen badge
	/// scale directly instead.
	func reposition(
		content: GateBadgeContent,
		metrics: GateBadgeLayout.Metrics,
		relativeTo anchorFrame: CGRect,
		visibleFrame: CGRect
	) {
		badgeView.configure(content: content, metrics: metrics)
		// Hug the stacked tokens (ticket over gate, both left-aligned).
		let size = badgeView.preferredSize
		let frame = GateBadgeLayout.frame(
			relativeTo: anchorFrame,
			badgeSize: size,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		badgeView.frame = NSRect(origin: .zero, size: frame.size)
	}
}

final class GateBadgeView: NSView {
	/// Dark-navy tint for the ticket token — keeps a blue hue but much darker
	/// than the old bright blue, layered over the frosted material.
	private static let ticketTint = NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.33, alpha: 0.90)

	private let stackView = NSStackView()
	private let ticketBadge = GateBadgeTokenView(
		tintColor: GateBadgeView.ticketTint,
		textColor: .white,
		weight: .semibold
	)
	private let gateBadge = GateBadgeTokenView(
		tintColor: nil,
		textColor: NSColor(calibratedWhite: 0.95, alpha: 1.0),
		weight: .medium
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		// Vertical, centered: ticket token on top, gate token below, each centered
		// on the stack's midline (and the stack is centered on the pet).
		stackView.orientation = .vertical
		stackView.alignment = .centerX
		stackView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stackView)
		stackView.addArrangedSubview(ticketBadge)
		stackView.addArrangedSubview(gateBadge)
		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(content: GateBadgeContent, metrics: GateBadgeLayout.Metrics) {
		stackView.spacing = metrics.interBadgeSpacing
		ticketBadge.configure(text: content.ticketId, metrics: metrics)
		gateBadge.configure(text: GateBadgeView.gateLabel(content.gate), metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	var preferredSize: CGSize {
		layoutSubtreeIfNeeded()
		return stackView.fittingSize
	}

	/// Human-readable, concise gate label. Reuses `ActivityState.displayLabel`
	/// (the gate states map 1:1 to activity states), falling back to the raw
	/// string for any unknown gate.
	static func gateLabel(_ rawGate: String) -> String {
		ActivityState(rawValue: rawGate)?.displayLabel ?? rawGate
	}
}

/// Frosted badge token matching the attention bubble / animation badge chrome:
/// a `hudWindow` visual-effect material, hairline white border, soft shadow.
/// `tintColor` layers a translucent hue over the material (used for the ticket
/// token's dark navy); pass `nil` for the neutral dark gate token.
private final class GateBadgeTokenView: NSView {
	private let effectView = NSVisualEffectView(frame: .zero)
	private let tintView = NSView(frame: .zero)
	private let label = NSTextField(labelWithString: "")
	private let textColor: NSColor
	private let weight: NSFont.Weight
	private let tintColor: NSColor?
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var heightConstraint: NSLayoutConstraint?
	private var leadingConstraint: NSLayoutConstraint?
	private var trailingConstraint: NSLayoutConstraint?

	init(tintColor: NSColor?, textColor: NSColor, weight: NSFont.Weight) {
		self.tintColor = tintColor
		self.textColor = textColor
		self.weight = weight
		super.init(frame: .zero)
		wantsLayer = true
		layer?.masksToBounds = false

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		tintView.wantsLayer = true
		tintView.layer?.backgroundColor = (tintColor ?? .clear).cgColor
		tintView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tintView)

		label.textColor = textColor
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		let heightConstraint = heightAnchor.constraint(equalToConstant: metrics.badgeHeight)
		let leadingConstraint = label.leadingAnchor.constraint(
			equalTo: leadingAnchor,
			constant: metrics.horizontalPadding
		)
		let trailingConstraint = label.trailingAnchor.constraint(
			equalTo: trailingAnchor,
			constant: -metrics.horizontalPadding
		)
		self.heightConstraint = heightConstraint
		self.leadingConstraint = leadingConstraint
		self.trailingConstraint = trailingConstraint
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			heightConstraint,
			leadingConstraint,
			trailingConstraint,
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(text: String, metrics: GateBadgeLayout.Metrics) {
		label.stringValue = text
		self.metrics = metrics
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	override var intrinsicContentSize: NSSize {
		let textSize = label.intrinsicContentSize
		return NSSize(
			width: textSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	private func applyMetrics() {
		effectView.layer?.cornerRadius = metrics.cornerRadius
		effectView.layer?.masksToBounds = true
		tintView.layer?.cornerRadius = metrics.cornerRadius
		tintView.layer?.masksToBounds = true
		layer?.cornerRadius = metrics.cornerRadius
		layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0.32
		layer?.shadowRadius = 8
		layer?.shadowOffset = CGSize(width: 0, height: -2)
		label.font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: weight)
		label.textColor = textColor
		heightConstraint?.constant = metrics.badgeHeight
		leadingConstraint?.constant = metrics.horizontalPadding
		trailingConstraint?.constant = -metrics.horizontalPadding
	}
}

enum AnimationBadgeLayout {
	/// Gap between the badge and the pet frame's bottom-left corner so the badge
	/// sits *just inside* the border rather than flush against it. Matches the
	/// gate badge's fixed `margin` so both chrome elements share one spacing feel.
	static let inset: CGFloat = GateBadgeLayout.margin

	/// Reuse the gate badge metrics verbatim so the animation badge scales with
	/// the pet frame identically (single source of scaling truth).
	static func metrics(for petFrame: CGRect) -> GateBadgeLayout.Metrics {
		GateBadgeLayout.metrics(for: petFrame)
	}

	/// Below the pet, with the badge's *top* edge sitting `inset` above the
	/// frame's bottom border so the sprite appears to stand on the badge (the
	/// badge body hangs below the feet rather than overlapping the character).
	/// `anchorX` is the badge-local x that lands on the pet's midX — the label
	/// pill's center, so the pill owns the dead-center position and the platform
	/// chip extends to its left. Then clamps to the visible display.
	static func frame(
		relativeTo petFrame: CGRect,
		badgeSize: CGSize,
		anchorX: CGFloat,
		visibleFrame: CGRect
	) -> CGRect {
		let rect = CGRect(
			x: petFrame.midX - anchorX,
			y: petFrame.minY + inset - badgeSize.height,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: GateBadgeLayout.margin, dy: GateBadgeLayout.margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}

	/// The animation badge is suppressed while the attention bubble is visible:
	/// the bubble is the 1:1 signal for standby/errored and occupies the same
	/// below-pet region the badge anchors to, so showing both is redundant and
	/// would collide.
	static func isVisible(attentionActive: Bool) -> Bool {
		!attentionActive
	}
}

@MainActor
final class AnimationBadgePanel: NSPanel {
	private let badgeView = AnimationBadgeView(frame: .zero)

	init() {
		super.init(
			contentRect: .zero,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		level = .floating
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = true
		contentView = badgeView
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func reposition(
		label: String,
		platform: PlatformAttribution?,
		inFlight: Bool,
		sessionNumber: Int? = nil,
		sessionLabel: String? = nil,
		sessionTooltip: String? = nil,
		relativeTo petFrame: CGRect,
		visibleFrame: CGRect
	) {
		badgeView.configure(
			text: label,
			platform: platform,
			inFlight: inFlight,
			metrics: AnimationBadgeLayout.metrics(for: petFrame)
		)
		badgeView.configureSessionNumber(sessionNumber, label: sessionLabel, tooltip: sessionTooltip)
		// `NSView.toolTip` only fires while its window actually receives mouse
		// events — with `ignoresMouseEvents` true (the default, so the badge
		// stays click-through when idle) AppKit never delivers the
		// mouse-entered notification the tooltip mechanism depends on, so the
		// string would be set but silently never shown. Accept mouse events
		// only while there is a tooltip to display; the badge has no click
		// handler of its own either way, so this never intercepts a click the
		// user meant for something else.
		ignoresMouseEvents = (sessionTooltip?.isEmpty ?? true)
		let size = badgeView.preferredSize
		let frame = AnimationBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: size,
			anchorX: badgeView.pillCenterX,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		badgeView.frame = NSRect(origin: .zero, size: frame.size)
	}
}

/// Frosted chrome shared by the animation badge's label pill and platform chip:
/// a dark `hudWindow` material matching the attention bubble, with a hairline
/// white border and soft drop shadow. The frosted body doubles as the contrast
/// backdrop that lets a single white glyph / mono label read over any window
/// behind the transparent pet frame.
enum AnimationBadgeChrome {
	static let textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
	/// Dark overlay layered above the frosted material to guarantee a readable
	/// dark floor when the pet sits over a light desktop or app background.
	/// Matches the opacity level of the SoA gate badge's neutral dark pill.
	static let badgeTint = NSColor(calibratedWhite: 0.0, alpha: 0.55)

	static func makeEffectView() -> NSVisualEffectView {
		let view = NSVisualEffectView(frame: .zero)
		view.material = .hudWindow
		view.blendingMode = .behindWindow
		view.state = .active
		view.appearance = NSAppearance(named: .darkAqua)
		view.wantsLayer = true
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}

	static func makeTintView() -> NSView {
		let view = NSView(frame: .zero)
		view.wantsLayer = true
		view.layer?.backgroundColor = badgeTint.cgColor
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}

	static func apply(
		to host: NSView,
		effect: NSVisualEffectView,
		tint: NSView? = nil,
		cornerRadius: CGFloat
	) {
		effect.layer?.cornerRadius = cornerRadius
		effect.layer?.masksToBounds = true
		tint?.layer?.cornerRadius = cornerRadius
		tint?.layer?.masksToBounds = true
		host.layer?.cornerRadius = cornerRadius
		host.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		host.layer?.borderWidth = 1
		host.layer?.shadowColor = NSColor.black.cgColor
		host.layer?.shadowOpacity = 0.32
		host.layer?.shadowRadius = 8
		host.layer?.shadowOffset = CGSize(width: 0, height: -2)
	}
}

/// Square frosted chip carrying the driving platform's logo, shown immediately
/// left of the animation badge. The logo is a template (monochrome) asset tinted
/// to the badge text color so it reads on both light and dark backdrops.
final class PlatformChipView: NSView {
	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let imageView = NSImageView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var sideConstraint: NSLayoutConstraint?
	private var glyphInsetConstraints: [NSLayoutConstraint] = []

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.contentTintColor = AnimationBadgeChrome.textColor
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)

		let side = widthAnchor.constraint(equalToConstant: metrics.badgeHeight)
		let height = heightAnchor.constraint(equalTo: widthAnchor)
		let inset = metrics.verticalPadding
		glyphInsetConstraints = [
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			imageView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
		]
		sideConstraint = side
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			side,
			height,
		] + glyphInsetConstraints)
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(platform: PlatformAttribution, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		let image = NSImage(named: platform.assetName)
		image?.isTemplate = true
		imageView.image = image
		applyMetrics()
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	private func applyMetrics() {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}

/// Frosted label pill: the activity-state name on the same chrome as the
/// platform chip. Sizing/scaling follows the gate badge metrics.
final class AnimationLabelPillView: NSView {
	/// Base label opacity while the agent is working: dimmed so the bright sweep
	/// reads as a highlight passing through. Restored to `restColor` at rest.
	private static let inFlightColor = NSColor(calibratedWhite: 0.58, alpha: 1.0)
	private static let restColor = AnimationBadgeChrome.textColor
	/// Width of the bright band as a fraction of the label width. The band is a
	/// clear→white→clear gradient, so the strongly-lit core reads as ~half of this.
	private static let shimmerBandFraction: CGFloat = 0.8
	/// Seconds for one full left→right pass across the text.
	private static let shimmerDuration: CFTimeInterval = 1.3
	private static let shimmerAnimationKey = "codogotchi.badge.shimmer"

	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let label = NSTextField(labelWithString: "")
	/// Overlay clipped to the glyph shapes (`glyphMask`). It hosts the moving
	/// `shimmerBand`; everything outside the band reads through to the dimmed base
	/// `label`, so a bright highlight appears only where the band crosses letters.
	private let shimmerContainer = CALayer()
	/// The bright band that physically translates across the text. A *normal*
	/// sublayer (not a mask), so its position animation runs reliably — animating a
	/// mask layer's geometry, by contrast, is silently dropped by Core Animation.
	private let shimmerBand = CAGradientLayer()
	/// Static glyph stencil used as `shimmerContainer.mask`. Mirrors the label's
	/// string/font/alignment/frame so the highlight registers on the letters.
	private let glyphMask = CATextLayer()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var isShimmering = false
	/// Band width the running animation was built for; lets us restart only when
	/// the label resizes, not on every layout pass.
	private var shimmerBandWidth: CGFloat = 0
	private var occlusionObserver: NSObjectProtocol?
	/// Watchdog that re-arms the sweep if it ever stops advancing. Core Animation
	/// culls animations on a range of events (Space switch, app deactivation,
	/// window occlusion) and does not always restore them or fire a notification,
	/// which previously left the highlight frozen mid-text. The heartbeat samples
	/// the band's presentation layer and restarts the animation the instant it
	/// detects no movement, so the sweep cannot stay stuck.
	private var shimmerHeartbeat: Timer?
	private var lastShimmerSampleX: CGFloat = .nan

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.alignment = .center
		label.textColor = Self.restColor
		label.wantsLayer = true
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		// Glyph-masked overlay hosting a narrow bright band. Hidden until a working
		// state arrives. Hosted in the pill's own layer (above the label) rather
		// than the text field's AppKit-owned layer.
		glyphMask.alignmentMode = .center
		glyphMask.truncationMode = .end
		glyphMask.foregroundColor = NSColor.white.cgColor
		shimmerContainer.mask = glyphMask
		shimmerContainer.masksToBounds = true
		shimmerContainer.isHidden = true
		shimmerContainer.zPosition = 1

		shimmerBand.startPoint = CGPoint(x: 0, y: 0.5)
		shimmerBand.endPoint = CGPoint(x: 1, y: 0.5)
		shimmerBand.colors = [
			NSColor.clear.cgColor,
			NSColor.white.cgColor,
			NSColor.clear.cgColor,
		]
		shimmerBand.locations = [0, 0.5, 1]
		shimmerContainer.addSublayer(shimmerBand)
		layer?.addSublayer(shimmerContainer)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	deinit {
		if let occlusionObserver {
			NotificationCenter.default.removeObserver(occlusionObserver)
		}
		shimmerHeartbeat?.invalidate()
	}

	func configure(text: String, inFlight: Bool, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		let font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: .medium)
		label.stringValue = text
		label.font = font
		label.textColor = inFlight ? Self.inFlightColor : Self.restColor
		glyphMask.string = text
		glyphMask.font = font
		glyphMask.fontSize = metrics.fontSize
		setShimmering(inFlight)
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: label.intrinsicContentSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		let scale = window?.backingScaleFactor ?? 2
		glyphMask.contentsScale = scale
		shimmerBand.contentsScale = scale
		// A move between displays drops layer animations; force a re-arm.
		forceShimmerRearm()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		observeWindowVisibility()
		// Re-attaching to a window drops any prior animation; re-arm.
		forceShimmerRearm()
	}

	/// Core Animation culls running animations whenever the hosting window is
	/// occluded or moved off the active Space, and they are *not* restored when it
	/// returns. For a long-lived state (e.g. "Reading") nothing else would re-arm
	/// the sweep, so it would freeze. Re-arm whenever the window becomes visible.
	private func observeWindowVisibility() {
		if let occlusionObserver {
			NotificationCenter.default.removeObserver(occlusionObserver)
			self.occlusionObserver = nil
		}
		guard let window else { return }
		occlusionObserver = NotificationCenter.default.addObserver(
			forName: NSWindow.didChangeOcclusionStateNotification,
			object: window,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
				self.forceShimmerRearm()
			}
		}
	}

	private func setShimmering(_ shimmering: Bool) {
		shimmerContainer.isHidden = !shimmering
		isShimmering = shimmering
		if shimmering {
			startShimmerHeartbeat()
		} else {
			shimmerHeartbeat?.invalidate()
			shimmerHeartbeat = nil
			shimmerBand.removeAnimation(forKey: Self.shimmerAnimationKey)
			shimmerBandWidth = 0
		}
		// `refreshShimmerGeometry` (driven from `applyMetrics`) arms the animation
		// once the label has a resolved width.
	}

	private func startShimmerHeartbeat() {
		guard shimmerHeartbeat == nil else { return }
		lastShimmerSampleX = .nan
		// Sample a few times per sweep. Added to `.common` modes so it keeps firing
		// during tracking runloops (menu/drag), and on the main runloop it fires
		// even while the app is in the background.
		let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.shimmerHeartbeatTick() }
		}
		RunLoop.main.add(timer, forMode: .common)
		shimmerHeartbeat = timer
	}

	private func shimmerHeartbeatTick() {
		// Only police the sweep when it should actually be running and visible.
		guard isShimmering, window?.occlusionState.contains(.visible) == true else {
			lastShimmerSampleX = .nan
			return
		}
		let sample = shimmerBand.presentation()?.position.x ?? .nan
		defer { lastShimmerSampleX = sample }
		// Frozen if there is no in-flight presentation, or the band has not advanced
		// since the previous sample. A spurious match at the sweep wrap just restarts
		// the sweep — visually harmless.
		let frozen = sample.isNaN || (!lastShimmerSampleX.isNaN && abs(sample - lastShimmerSampleX) < 0.5)
		if frozen { forceShimmerRearm() }
	}

	private func forceShimmerRearm() {
		shimmerBandWidth = 0
		shimmerBand.removeAnimation(forKey: Self.shimmerAnimationKey)
		refreshShimmerGeometry()
	}

	/// Size the band to the current label width and (re)arm the sweep. Restarts
	/// only when the band width actually changes so steady-state layout passes do
	/// not reset the animation phase mid-stroke.
	private func refreshShimmerGeometry() {
		let width = label.bounds.width
		let height = label.bounds.height
		guard isShimmering, width > 0, height > 0 else { return }
		let bandWidth = max(8, width * Self.shimmerBandFraction)
		let needsRestart =
			abs(bandWidth - shimmerBandWidth) > 0.5
			|| shimmerBand.animation(forKey: Self.shimmerAnimationKey) == nil
		guard needsRestart else { return }
		shimmerBandWidth = bandWidth

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shimmerBand.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: height)
		shimmerBand.position = CGPoint(x: -bandWidth / 2, y: height / 2)
		CATransaction.commit()

		let animation = CABasicAnimation(keyPath: "position.x")
		// Center of the band travels from just off the left edge to just off the
		// right edge — one continuous left→right pass per cycle.
		animation.fromValue = -bandWidth / 2
		animation.toValue = width + bandWidth / 2
		animation.duration = Self.shimmerDuration
		animation.repeatCount = .infinity
		animation.timingFunction = CAMediaTimingFunction(name: .linear)
		shimmerBand.add(animation, forKey: Self.shimmerAnimationKey)
	}

	private func applyMetrics() {
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
		// Mirror the label's resolved frame so the overlay glyph stencil registers
		// exactly on top of the dimmed base glyphs. Disable implicit animation so
		// the overlay does not lag the pill during drag/reposition.
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shimmerContainer.frame = label.frame
		glyphMask.frame = shimmerContainer.bounds
		CATransaction.commit()
		refreshShimmerGeometry()
	}
}

/// Session-label pill shown as a second row beneath the platform chip +
/// animation badge, centered horizontally. Renders the user's rename label
/// (from `SessionLabelStore`, via `configure(number:label:tooltip:metrics:)`)
/// when set, else falls back to "Session N" for the number assigned by
/// `SessionNumberAllocator`. `tooltip` exposes the session's last submitted
/// prompt as a native `NSView.toolTip` (P15.06). Reuses the same frosted
/// chrome and `GateBadgeLayout.Metrics` scaling as the animation badge pill —
/// single source of scaling truth.
final class PlatformSessionBadge: NSView {
	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let label = NSTextField(labelWithString: "")
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.alignment = .center
		label.textColor = AnimationBadgeChrome.textColor
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	/// Configures the badge for session `number` and returns whether it should
	/// be visible at all — `nil` (no session assigned, e.g. session-pets off or
	/// a plain-origin/combined window) hides the row entirely. `label`, when
	/// present, replaces the "Session N" text with the user's rename (P15.06).
	/// `tooltip` — the session's last submitted prompt — is shown by AppKit's
	/// native delayed hover tooltip; empty/`nil` clears it.
	func configure(number: Int?, label: String? = nil, tooltip: String? = nil, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		if let number {
			self.label.stringValue = (label?.isEmpty == false) ? label! : "Session \(number)"
			isHidden = false
			toolTip = (tooltip?.isEmpty == false) ? tooltip : nil
		} else {
			isHidden = true
			toolTip = nil
		}
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: label.intrinsicContentSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	private func applyMetrics() {
		let font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: .medium)
		label.font = font
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}

/// Transparent container laying out an optional platform chip immediately left
/// of the activity-state label pill. When no platform is attributed the chip is
/// detached and the pill stands alone, preserving the prior single-pill look.
final class AnimationBadgeView: NSView {
	private let chipView = PlatformChipView(frame: .zero)
	private let pillView = AnimationLabelPillView(frame: .zero)
	private let stackView = NSStackView()
	private let sessionBadge = PlatformSessionBadge(frame: .zero)
	private let outerStack = NSStackView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var currentSessionNumber: Int?
	private var currentSessionLabel: String?
	private var currentSessionTooltip: String?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		stackView.orientation = .horizontal
		stackView.alignment = .centerY
		stackView.addArrangedSubview(pillView)

		sessionBadge.isHidden = true

		outerStack.orientation = .vertical
		// `.leading` (not `.centerX`) pins the session badge row's leading edge to
		// the chip+pill row's leading edge (the platform chip, when present)
		// regardless of which row is wider. `.centerX` would let a wide session
		// label re-center the narrower chip+pill row within the view, shifting it
		// off the `pillCenterX` anchor the panel uses to keep the pill centered
		// on the pet — see `AnimationBadgeLayout.frame`.
		outerStack.alignment = .leading
		outerStack.spacing = 4
		outerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(outerStack)
		outerStack.addArrangedSubview(stackView)
		outerStack.addArrangedSubview(sessionBadge)
		NSLayoutConstraint.activate([
			outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
			outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
			outerStack.topAnchor.constraint(equalTo: topAnchor),
			outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(
		text: String,
		platform: PlatformAttribution?,
		inFlight: Bool,
		metrics: GateBadgeLayout.Metrics
	) {
		self.metrics = metrics
		stackView.spacing = metrics.interBadgeSpacing
		pillView.configure(text: text, inFlight: inFlight, metrics: metrics)
		if let platform {
			chipView.configure(platform: platform, metrics: metrics)
			if chipView.superview == nil {
				stackView.insertArrangedSubview(chipView, at: 0)
			}
		} else if chipView.superview != nil {
			stackView.removeArrangedSubview(chipView)
			chipView.removeFromSuperview()
		}
		sessionBadge.configure(
			number: currentSessionNumber, label: currentSessionLabel, tooltip: currentSessionTooltip,
			metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	/// Shows/hides and labels the session badge row beneath the chip + pill
	/// row. `nil` number hides the row entirely (session-pets off, or a
	/// plain-origin/combined window). `label`/`tooltip` are the rename text
	/// and last-prompt hover tooltip (P15.06); both are `nil` until the pool
	/// applies them on the same tick.
	func configureSessionNumber(_ number: Int?, label: String? = nil, tooltip: String? = nil) {
		currentSessionNumber = number
		currentSessionLabel = label
		currentSessionTooltip = tooltip
		sessionBadge.configure(number: number, label: label, tooltip: tooltip, metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	var preferredSize: CGSize {
		layoutSubtreeIfNeeded()
		var size = stackView.fittingSize
		if !sessionBadge.isHidden {
			size.width = max(size.width, sessionBadge.intrinsicContentSize.width)
			size.height += 4 + sessionBadge.intrinsicContentSize.height
		}
		return size
	}

	/// X-coordinate (in badge-local space) of the label pill's horizontal center.
	/// The pill is the rightmost element, so its center sits `pillWidth / 2` in
	/// from the trailing edge. The panel anchors *this* point on the pet's midX so
	/// the pill owns the dead-center position and the chip hangs off to its left;
	/// with no chip it collapses to `width / 2` (centered, as before).
	var pillCenterX: CGFloat {
		layoutSubtreeIfNeeded()
		return stackView.fittingSize.width - pillView.intrinsicContentSize.width / 2
	}
}

/// Layout for the in-frame “Hide pet” pill shown on right-click (Codex-style).
enum FloatingPetHidePrompt {
	static let title = "Hide pet"
	/// Title for the minimalist badge's right-click affordance, which hides the
	/// whole platform strip rather than an Own-mode pet sprite.
	static let panelTitle = "Hide panel"
	/// Title for the right-click "Force Idle" escape hatch. Surfaced only when the
	/// pet is stuck in a non-idle animation (see `offersForceIdle(for:)`); resets
	/// the pet to idle by rewriting its `state.d/` slice.
	static let forceIdleTitle = "Force Idle"
	/// Title for the right-click "Rename" affordance, offered only on a
	/// session-keyed window (P15.06).
	static let renameTitle = "Rename…"
	/// Title for the right-click "Prune Session" affordance, offered only on a
	/// session-keyed window (P15.07). Destroys the panel and its backing state
	/// (slice, free-list number, rename label) — the same end-state as
	/// automatic TTL expiry.
	static let pruneTitle = "Prune Session"
	static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
	static let horizontalPadding: CGFloat = 14
	static let verticalPadding: CGFloat = 7
	/// Vertical gap between stacked pill rows when the prompt shows more than one
	/// action (e.g. "Force Idle" above "Hide pet").
	static let rowSpacing: CGFloat = 6

	static func preferredSize(title: String = FloatingPetHidePrompt.title) -> CGSize {
		let textSize = (title as NSString).size(withAttributes: [.font: font])
		let height = ceil(textSize.height) + verticalPadding * 2
		let width = ceil(textSize.width) + horizontalPadding * 2
		return CGSize(width: width, height: height)
	}

	/// Size of a vertical stack of pill rows: width fits the widest title, height
	/// sums the equal-height rows plus `rowSpacing` between them. A single title
	/// reduces to `preferredSize(title:)`.
	static func stackSize(titles: [String]) -> CGSize {
		guard !titles.isEmpty else { return .zero }
		let rowSizes = titles.map { preferredSize(title: $0) }
		let width = rowSizes.map(\.width).max() ?? 0
		let rowHeight = rowSizes.first?.height ?? 0
		let height = rowHeight * CGFloat(titles.count)
			+ rowSpacing * CGFloat(titles.count - 1)
		return CGSize(width: width, height: height)
	}

	/// Whether the right-click prompt should offer the "Force Idle" escape hatch
	/// for `state`. Offered for every state except `idle` — the idle "set"
	/// (idle / impatient / frustrated) all share the `.idle` wire state, since
	/// escalation is renderer-internal, so this single check covers all three.
	static func offersForceIdle(for state: ActivityState) -> Bool {
		state != .idle
	}

	/// Frame for row `index` (0 = top) within a prompt panel of `panelSize` that
	/// holds `count` equal-height rows separated by `rowSpacing`. AppKit's origin
	/// is bottom-left, so index 0 is pinned to the top edge and the last row sits
	/// on the bottom edge. Shared by the panel's row layout and its tests so the
	/// stacking geometry has one source of truth.
	static func rowFrame(index: Int, count: Int, panelSize: CGSize) -> CGRect {
		let rowHeight = preferredSize().height
		let minY = panelSize.height
			- CGFloat(index + 1) * rowHeight
			- CGFloat(index) * rowSpacing
		return CGRect(x: 0, y: minY, width: panelSize.width, height: rowHeight)
	}

	/// Places the pill so the right-click point is its top-left corner (AppKit
	/// coordinates: `origin` is the rect’s bottom-left, so `maxY` is the top edge).
	/// Keeps `minX` / `maxY` pinned to the click when possible; only nudges the
	/// anchor when the pill would cross the left/bottom inset (never slides left
	/// just because it would extend past the right edge — that looked “top-middle”).
	static func frame(anchor: CGPoint, promptSize: CGSize, in bounds: CGRect) -> CGRect {
		let margin: CGFloat = 4
		let inset = bounds.insetBy(dx: margin, dy: margin)
		var minX = anchor.x
		var maxY = anchor.y
		if minX < inset.minX {
			minX = inset.minX
		}
		if maxY > inset.maxY {
			maxY = inset.maxY
		}
		var minY = maxY - promptSize.height
		if minY < inset.minY {
			minY = inset.minY
			maxY = minY + promptSize.height
		}
		return CGRect(
			x: minX,
			y: minY,
			width: promptSize.width,
			height: promptSize.height
		)
	}

	static func shouldPresent(
		at localPoint: CGPoint,
		in bounds: CGRect,
		hasActivePointerInteraction: Bool
	) -> Bool {
		bounds.contains(localPoint) && !hasActivePointerInteraction
	}
}

enum FloatingInteractionHitTarget: Equatable {
	case dragRegion
	case resizeAffordance
}

enum FloatingInteractionPolicy {
	static let resizeAffordanceSize = CGSize(width: 28, height: 28)
	/// Enlarged hover/reveal zone (frame bottom-right anchored). Grab hit-testing
	/// stays on `resizeAffordanceRect` so accidental resizes near the corner are
	/// unlikely.
	static let resizeAffordanceRevealMultiplier: CGFloat = 2

	static func hitTest(point: CGPoint, in bounds: CGRect) -> FloatingInteractionHitTarget {
		if resizeAffordanceRect(in: bounds).contains(point) {
			return .resizeAffordance
		}
		return .dragRegion
	}

	static func resizeAffordanceRect(in bounds: CGRect) -> CGRect {
		CGRect(
			x: bounds.maxX - resizeAffordanceSize.width,
			y: bounds.minY,
			width: resizeAffordanceSize.width,
			height: resizeAffordanceSize.height
		)
	}

	/// Bottom-right anchored zone used for hover/reveal and affordance tracking.
	/// Larger than `resizeAffordanceRect` so the handle lights up when the cursor
	/// is nearby; does not widen the grab target.
	static func resizeAffordanceRevealRect(in bounds: CGRect) -> CGRect {
		let revealWidth = resizeAffordanceSize.width * resizeAffordanceRevealMultiplier
		let revealHeight = resizeAffordanceSize.height * resizeAffordanceRevealMultiplier
		return CGRect(
			x: bounds.maxX - revealWidth,
			y: bounds.minY,
			width: revealWidth,
			height: revealHeight
		)
	}

	/// Positions the panel so the `mouseDown` grab point stays under the cursor.
	/// `grabOffsetInScreen` is the vector from the window origin to the click in
	/// screen space (bottom-left origin, same as `NSWindow.frame`).
	static func draggedFrame(
		mouseLocationInScreen: CGPoint,
		grabOffsetInScreen: CGPoint,
		windowSize: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		FloatingFramePolicy.clamp(
			CGRect(
				x: mouseLocationInScreen.x - grabOffsetInScreen.x,
				y: mouseLocationInScreen.y - grabOffsetInScreen.y,
				width: windowSize.width,
				height: windowSize.height
			),
			to: visibleFrame
		)
	}

	/// Cumulative screen delta from a fixed start (resize drags).
	static func draggedFrame(
		from frame: CGRect,
		dragDelta: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		FloatingFramePolicy.clamp(
			CGRect(
				x: frame.origin.x + dragDelta.width,
				y: frame.origin.y + dragDelta.height,
				width: frame.width,
				height: frame.height
			),
			to: visibleFrame
		)
	}

	/// Horizontal screen delta that drives resize. Pure vertical drags return 0
	/// (Codex-style: only left/right motion changes scale).
	static func resizeHorizontalDelta(from rawDelta: CGSize) -> CGFloat {
		rawDelta.width
	}

	/// Uniform width/height growth applied to interaction feedback from the
	/// horizontal resize delta (zero when the drag has no horizontal component).
	static func resizeDragDelta(from rawDelta: CGSize) -> CGSize {
		let horizontal = resizeHorizontalDelta(from: rawDelta)
		guard horizontal != 0 else { return .zero }
		return CGSize(width: horizontal, height: horizontal)
	}

	static func resizedFrame(
		from frame: CGRect,
		dragDelta: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		let horizontalDelta = resizeHorizontalDelta(from: dragDelta)
		guard horizontalDelta != 0, frame.width > 0, frame.height > 0 else {
			return FloatingFramePolicy.clamp(frame, to: visibleFrame)
		}

		let aspect = frame.width / frame.height
		let newWidth = frame.width + horizontalDelta
		let newHeight = newWidth / aspect
		return FloatingFramePolicy.clamp(
			CGRect(
				x: frame.origin.x,
				y: frame.origin.y,
				width: newWidth,
				height: newHeight
			),
			to: visibleFrame
		)
	}

	/// Whether the resize affordance icon should paint for the current pointer
	/// and interaction state.
	static func shouldShowResizeAffordance(
		pointerInAffordance: Bool,
		isResizing: Bool
	) -> Bool {
		pointerInAffordance || isResizing
	}

	/// Avoid tearing down `NSTrackingArea` on every layout pass — only when the
	/// content bounds actually change (resize drags call `layout` every frame).
	static func shouldRefreshTrackingAreas(previousBounds: CGRect, newBounds: CGRect) -> Bool {
		previousBounds.size != newBounds.size
	}

	/// AppKit default (non-flipped) view coordinates: origin at bottom-left.
	static func pointerInBounds(_ point: CGPoint, bounds: CGRect) -> Bool {
		bounds.contains(point)
	}

	/// Reserved-row interaction for a primary (left) click on the pet body.
	/// Resize drags use `interaction(forStepDelta:…)` instead.
	static func clickInteraction(hitTarget: FloatingInteractionHitTarget) -> FloatingInteraction? {
		switch hitTarget {
		case .dragRegion:
			return .jumping
		case .resizeAffordance:
			return nil
		}
	}

	/// Maps a single drag event's screen-space step (not cumulative delta from
	/// `mouseDown`) to the reserved-row interaction. Vertical-only steps keep
	/// the previous running direction so frame translation stays smooth.
	static func interaction(
		forStepDelta delta: CGSize,
		hitTarget: FloatingInteractionHitTarget,
		previous: FloatingInteraction? = nil
	) -> FloatingInteraction? {
		switch hitTarget {
		case .resizeAffordance:
			// Resizing must not animate the pet: clear any interaction so the
			// activity-state animation that was already playing stays put.
			return nil
		case .dragRegion:
			if delta.width > 0 { return .runningRight }
			if delta.width < 0 { return .runningLeft }
			// Vertical-only steps must not drop back to activity frames mid-drag
			// (common on the first `mouseDragged` tick while a click set `.jumping`).
			if previous == .runningLeft || previous == .runningRight || previous == .jumping {
				return previous
			}
			return nil
		}
	}
}

private final class FloatingPetInteractionView: NSView {
	private enum ActiveInteraction {
		case drag(grabOffsetInScreen: CGPoint)
		case resize(startFrame: CGRect, startScreenPoint: CGPoint)
	}

	private static let trackingKindBounds = "bounds"
	private static let trackingKindAffordance = "affordance"

	private let skView = SKView(frame: .zero)
	private let overlayView = FloatingPetOverlayView(frame: .zero)
	private let visibleFrameProvider: () -> CGRect
	private let interactionHandler: (FloatingInteraction?) -> Void
	private let sceneSizeHandler: (CGSize) -> Void
	private var activeInteraction: ActiveInteraction?
	private var lastEmittedInteraction: FloatingInteraction?
	private var holdTimer: Timer?
	private var boundsTrackingArea: NSTrackingArea?
	private var affordanceTrackingArea: NSTrackingArea?
	private var lastTrackingBoundsSize: CGSize = .zero
	private var lastLayoutBoundsSize: CGSize = .zero
	private var isReconfiguringTracking = false
	private var resizeCursorPushed = false
	private var localMouseMonitor: Any?
	private var globalMouseMonitor: Any?
	private var globalKeyboardMonitor: Any?
	private var hidePromptDismissObservers: [NSObjectProtocol] = []
	private var pointerInsideFrame = false
	private var affordanceHoverActive = false
	private var hidePromptPanel: FloatingPetHidePromptPanel?
	var frameChangeHandler: ((CGRect) -> Void)?
	/// Fired on every in-flight drag/resize tick (not just mouseUp) so attached
	/// chrome (the attention bubble) can re-anchor live. Must stay cheap — it
	/// runs per `mouseDragged`; persistence stays on `frameChangeHandler`.
	var liveFrameChangeHandler: ((CGRect) -> Void)?
	/// Fired when a pet drag begins (`true`) and ends (`false`). Lets the panel
	/// suppress the RPG HUD + ghost chrome for the duration of the drag. Resize
	/// drags do not fire this — only translation of the pet body.
	var onDragStateChange: ((Bool) -> Void)?
	/// Fired when the user holds a stationary click on the pet body for ≥5 s.
	var holdDeEscalationHandler: (() -> Void)?
	var hideFloatingPetHandler: (() -> Void)?
	/// Fired when the user activates the right-click "Force Idle" pill. Only
	/// offered while `isForceIdleAvailable` (the pet is not idle).
	var forceIdleHandler: (() -> Void)?
	/// Whether the right-click prompt should offer "Force Idle". Kept in sync by
	/// the controller from the latest applied `ActivityState`.
	var isForceIdleAvailable = false
	/// Whether this window currently holds a session number (P15.06). Gates
	/// the right-click "Rename" affordance — only session-keyed windows can
	/// be renamed. Kept in sync by the controller from the latest applied
	/// session number.
	var hasActiveSessionBadge = false
	/// This session's current rename label, if any — prefills the rename
	/// alert's text field.
	var currentSessionLabel: String?
	/// Fired with the trimmed/capped label the user commits via the
	/// right-click "Rename" affordance. Not fired when the user cancels or
	/// commits an empty/whitespace-only label.
	var renameHandler: ((String) -> Void)?
	/// Fired when the user confirms the right-click "Prune Session" affordance
	/// (P15.07). Not fired if the user cancels the confirmation alert. Only
	/// offered while `hasActiveSessionBadge`, same gate as Rename.
	var pruneHandler: (() -> Void)?
	/// Fired when the pointer enters or leaves the pet frame. `true` = entered.
	var onHoverChange: ((Bool) -> Void)?
	/// Fired on every pointer event while tracking (moved, entered, exited).
	var onPointerUpdate: (() -> Void)?

	init(
		frame: CGRect,
		visibleFrameProvider: @escaping () -> CGRect,
		interactionHandler: @escaping (FloatingInteraction?) -> Void,
		sceneSizeHandler: @escaping (CGSize) -> Void
	) {
		self.visibleFrameProvider = visibleFrameProvider
		self.interactionHandler = interactionHandler
		self.sceneSizeHandler = sceneSizeHandler
		super.init(frame: frame)

		autoresizingMask = [.width, .height]
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		skView.allowsTransparency = true
		skView.ignoresSiblingOrder = true
		skView.autoresizingMask = [.width, .height]
		skView.wantsLayer = true
		skView.layer?.zPosition = 0
		addSubview(skView)
		overlayView.autoresizingMask = [.width, .height]
		overlayView.wantsLayer = true
		overlayView.layer?.zPosition = 20
		addSubview(overlayView, positioned: .above, relativeTo: skView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		nil
	}

	func presentScene(_ scene: SKScene) {
		skView.presentScene(scene)
		elevateOverlayAboveSpriteKit()
	}

	func setSpriteKitPaused(_ paused: Bool) {
		skView.isPaused = paused
	}

	/// Re-arm mouse-move tracking and sync affordance visibility after the panel
	/// is shown or its frame changes outside an in-flight drag.
	func prepareForDisplay() {
		window?.acceptsMouseMovedEvents = true
		installLocalMouseMonitorIfNeeded()
		reconfigureTrackingAreasIfNeeded(force: true)
		syncPointerState(reason: "prepareForDisplay")
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil {
			prepareForDisplay()
		} else {
			dismissHidePrompt()
			removeLocalMouseMonitor()
		}
	}

	deinit {
		removeLocalMouseMonitor()
		removeHidePromptDismissObservers()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		reconfigureTrackingAreasIfNeeded(force: false)
	}

	override var isFlipped: Bool { false }

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }
		return self
	}

	override func layout() {
		super.layout()
		skView.frame = bounds
		overlayView.frame = bounds
		let sizeChanged = bounds.size != lastLayoutBoundsSize
		lastLayoutBoundsSize = bounds.size
		if sizeChanged {
			sceneSizeHandler(bounds.size)
			reconfigureTrackingAreasIfNeeded(force: false)
		}
		elevateOverlayAboveSpriteKit()
		// Translate drags only move origin; skip pointer/tracking churn each frame.
		if activeInteraction == nil || isResizing {
			syncPointerState(reason: "layout")
		}
	}

	override func mouseMoved(with event: NSEvent) {
		handlePointerEvent(at: convert(event.locationInWindow, from: nil), reason: "mouseMoved")
	}

	override func mouseEntered(with event: NSEvent) {
		let kind = event.trackingArea?.userInfo?["kind"] as? String
		let localPoint = convert(event.locationInWindow, from: nil)
		if kind == Self.trackingKindAffordance {
			affordanceHoverActive = true
		}
		handlePointerEvent(at: localPoint, reason: "mouseEntered(\(kind ?? "bounds"))")
	}

	override func mouseExited(with event: NSEvent) {
		guard !isReconfiguringTracking else {
			return
		}
		let kind = event.trackingArea?.userInfo?["kind"] as? String
		if kind == Self.trackingKindAffordance {
			affordanceHoverActive = false
		}
		// Do NOT pre-assign pointerInsideFrame = false here. handlePointerEvent
		// owns all reads and writes of pointerInsideFrame so the wasInBounds delta
		// check fires correctly and onHoverChange?(false) propagates to the HUD.
		handlePointerEvent(
			at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil),
			reason: "mouseExited(\(kind ?? "bounds"))"
		)
	}

	override func rightMouseDown(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		let shouldPresent = FloatingPetHidePrompt.shouldPresent(
			at: localPoint,
			in: bounds,
			hasActivePointerInteraction: activeInteraction != nil
		)
		guard shouldPresent else {
			dismissHidePrompt()
			return
		}
		presentHidePrompt(anchorInScreen: screenLocation(for: event), localPoint: localPoint)
	}

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		let localPoint = convert(event.locationInWindow, from: nil)
		if hidePromptPanel != nil {
			dismissHidePrompt()
		}
		let startScreenPoint = NSEvent.mouseLocation
		switch FloatingInteractionPolicy.hitTest(point: localPoint, in: bounds) {
		case .dragRegion:
			let clickInScreen = screenLocation(for: event)
			let grabOffset = CGPoint(
				x: clickInScreen.x - window.frame.origin.x,
				y: clickInScreen.y - window.frame.origin.y
			)
			activeInteraction = .drag(grabOffsetInScreen: grabOffset)
			overlayView.showsResizeAffordance = false
			onDragStateChange?(true)
			emitInteraction(
				FloatingInteractionPolicy.clickInteraction(hitTarget: .dragRegion),
				reason: "mouseDown-click"
			)
			startHoldTimer()
		case .resizeAffordance:
			activeInteraction = .resize(startFrame: window.frame, startScreenPoint: startScreenPoint)
			pushResizeCursor()
			handlePointerEvent(at: localPoint, reason: "mouseDown-resize")
		}
	}

	override func mouseDragged(with event: NSEvent) {
		// Intentionally does NOT cancel the hold timer: any continuous click-hold
		// on the pet body de-escalates after 5 s, whether the user holds still
		// (jumping) or drags (running-left/right). The timer is only cancelled on
		// mouseUp. Resize never arms the timer, so dragging the affordance is a
		// no-op here.
		guard let window, let activeInteraction else { return }
		let currentPoint = NSEvent.mouseLocation
		let nextFrame: CGRect
		let hitTarget: FloatingInteractionHitTarget

		switch activeInteraction {
		case let .drag(grabOffsetInScreen):
			let stepDelta = CGSize(width: event.deltaX, height: event.deltaY)
			hitTarget = .dragRegion
			let mouseInScreen = screenLocation(for: event)
			let before = window.frame
			nextFrame = FloatingInteractionPolicy.draggedFrame(
				mouseLocationInScreen: mouseInScreen,
				grabOffsetInScreen: grabOffsetInScreen,
				windowSize: before.size,
				visibleFrame: visibleFrameProvider()
			)
			applyPanelFrame(nextFrame, isTranslate: true)
			let interaction = FloatingInteractionPolicy.interaction(
				forStepDelta: stepDelta,
				hitTarget: hitTarget,
				previous: lastEmittedInteraction
			)
			emitInteraction(interaction, reason: "mouseDragged-\(hitTarget)")
			return
		case let .resize(startFrame, startScreenPoint):
			let rawDelta = CGSize(
				width: currentPoint.x - startScreenPoint.x,
				height: currentPoint.y - startScreenPoint.y
			)
			hitTarget = .resizeAffordance
			nextFrame = FloatingInteractionPolicy.resizedFrame(
				from: startFrame,
				dragDelta: rawDelta,
				visibleFrame: visibleFrameProvider()
			)
			applyPanelFrame(nextFrame, isTranslate: false)
			let stepDelta = CGSize(width: event.deltaX, height: event.deltaY)
			let interaction = FloatingInteractionPolicy.interaction(
				forStepDelta: stepDelta,
				hitTarget: hitTarget,
				previous: lastEmittedInteraction
			)
			emitInteraction(interaction, reason: "mouseDragged-\(hitTarget)")
		}
	}

	override func mouseUp(with event: NSEvent) {
		cancelHoldTimer()
		let wasResizing = isResizing
		let wasDragging = isTranslating
		window?.displayIfNeeded()
		activeInteraction = nil
		if wasDragging { onDragStateChange?(false) }
		emitInteraction(nil, reason: "mouseUp-clear")
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
		popResizeCursorIfNeeded()
		let localPoint = convert(event.locationInWindow, from: nil)
		handlePointerEvent(at: localPoint, reason: wasResizing ? "mouseUp-resize" : "mouseUp")
	}

	override func cursorUpdate(with event: NSEvent) {
		applyAffordanceCursor(for: convert(event.locationInWindow, from: nil))
	}

	private var isResizing: Bool {
		if case .resize = activeInteraction { return true }
		return false
	}

	private func startHoldTimer() {
		holdTimer?.invalidate()
		// Repeats so a sustained hold steps down one level every 5 s ("5 s for
		// each bump"). Added in `.common` mode rather than scheduled in `.default`
		// so it keeps firing while a drag puts the run loop in event-tracking mode.
		let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
			self?.holdDeEscalationHandler?()
		}
		RunLoop.main.add(timer, forMode: .common)
		holdTimer = timer
	}

	private func cancelHoldTimer() {
		holdTimer?.invalidate()
		holdTimer = nil
	}

	private var isTranslating: Bool {
		if case .drag = activeInteraction { return true }
		return false
	}

	/// Screen location for the event cursor, using the window's base coordinate
	/// system so it stays consistent with `NSWindow.frame` (bottom-left screen).
	private func screenLocation(for event: NSEvent) -> CGPoint {
		guard let window else { return NSEvent.mouseLocation }
		return window.convertPoint(toScreen: event.locationInWindow)
	}

	private func applyPanelFrame(_ frame: CGRect, isTranslate: Bool) {
		guard let window else { return }
		let before = window.frame
		guard frame != before else { return }

		if isTranslate, frame.size == before.size {
			window.setFrameOrigin(frame.origin)
		} else {
			window.setFrame(frame, display: false)
		}

		if frame.size != before.size {
			sceneSizeHandler(frame.size)
		}

		// Re-anchor attached chrome (attention bubble) live, every tick. Cheap
		// in-memory reposition only; state persistence stays on mouseUp.
		liveFrameChangeHandler?(frame)
	}

	private func elevateOverlayAboveSpriteKit() {
		addSubview(overlayView, positioned: .above, relativeTo: skView)
	}

	private func installLocalMouseMonitorIfNeeded() {
		guard localMouseMonitor == nil else { return }
		localMouseMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [
				.mouseMoved,
				.leftMouseDragged,
				.leftMouseUp,
				.leftMouseDown,
				.rightMouseDown,
			]
		) { [weak self] event in
			guard let self, let window = self.window, event.window === window else { return event }
			let localPoint = self.convert(event.locationInWindow, from: nil)
			if self.hidePromptPanel != nil {
				switch event.type {
				case .leftMouseDown, .rightMouseDown:
					self.dismissHidePrompt()
				default:
					break
				}
			}
			// `mouseDragged` on this view already moves the panel; skip duplicate overlay work.
			if self.isTranslating, event.type == .leftMouseDragged {
				return event
			}
			self.handlePointerEvent(at: localPoint, reason: "localMonitor-\(event.type.rawValue)")
			return event
		}
	}

	private func presentHidePrompt(anchorInScreen: CGPoint, localPoint: CGPoint) {
		dismissHidePrompt()
		guard let window else { return }
		FloatingPetPromptCoordinator.shared.willPresent(owner: self) { [weak self] in
			self?.dismissHidePrompt()
		}
		var items: [FloatingPetPromptItem] = []
		// Escape hatch when the pet is stuck mid-animation (rate-limited or
		// manually-stopped prompt): sits above "Hide pet" as the primary action.
		if isForceIdleAvailable {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.forceIdleTitle) { [weak self] in
					self?.dismissHidePrompt()
					self?.forceIdleHandler?()
				})
		}
		// Rename is only meaningful for a session-keyed window (one that
		// currently carries a session number); sits above "Hide pet".
		if hasActiveSessionBadge {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.renameTitle) { [weak self] in
					self?.dismissHidePrompt()
					self?.presentRenameAlert()
				})
			// Destructive, so it sits above "Hide pet" but requires a confirmation
			// alert rather than firing immediately on click.
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.pruneTitle) { [weak self] in
					self?.dismissHidePrompt()
					self?.presentPruneConfirmation()
				})
		}
		items.append(
			FloatingPetPromptItem(title: FloatingPetHidePrompt.title) { [weak self] in
				self?.dismissHidePrompt()
				self?.hideFloatingPetHandler?()
			})
		let promptSize = FloatingPetHidePrompt.stackSize(titles: items.map(\.title))
		let visibleFrame = window.screen?.visibleFrame ?? visibleFrameProvider()
		let screenFrame = FloatingPetHidePrompt.screenFrame(
			anchor: anchorInScreen,
			promptSize: promptSize,
			visibleFrame: visibleFrame
		)
		let panel = FloatingPetHidePromptPanel(frame: screenFrame, items: items)
		panel.orderFrontRegardless()
		hidePromptPanel = panel
		installHidePromptDismissObservers()
	}

	/// Presents a modal text-entry alert for renaming this session. Trims and
	/// caps the result at `SessionLabelStore.maxLength`; an empty/whitespace
	/// result (or Cancel) is treated as "no rename" and `renameHandler` is not
	/// fired.
	private func presentRenameAlert() {
		let alert = NSAlert()
		alert.messageText = "Rename Session"
		alert.informativeText = "Up to \(SessionLabelStore.maxLength) characters."
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")
		let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = currentSessionLabel ?? ""
		alert.accessoryView = field
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let normalized = SessionLabelStore.normalize(field.stringValue)
		guard !normalized.isEmpty else { return }
		renameHandler?(normalized)
	}

	/// Presents a destructive-action confirmation alert for pruning this
	/// session. `pruneHandler` fires only when the user confirms; Cancel is a
	/// no-op, matching the rename alert's "no commit on cancel" contract.
	private func presentPruneConfirmation() {
		let alert = NSAlert()
		alert.messageText = "Prune Session"
		alert.informativeText =
			"This destroys the panel and its session data. This cannot be undone."
		alert.addButton(withTitle: "Prune")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		pruneHandler?()
	}

	func dismissHidePromptIfPresent() {
		dismissHidePrompt()
	}

	private func dismissHidePrompt() {
		FloatingPetPromptCoordinator.shared.didDismiss(owner: self)
		hidePromptPanel?.orderOut(nil)
		hidePromptPanel = nil
		removeHidePromptDismissObservers()
	}

	private func installHidePromptDismissObservers() {
		removeHidePromptDismissObservers()
		guard let window else { return }

		hidePromptDismissObservers.append(
			NotificationCenter.default.addObserver(
				forName: NSWindow.didResignKeyNotification,
				object: window,
				queue: .main
			) { [weak self] _ in
				self?.dismissHidePrompt()
			}
		)
		hidePromptDismissObservers.append(
			NotificationCenter.default.addObserver(
				forName: NSApplication.didResignActiveNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				self?.dismissHidePrompt()
			}
		)

		globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown]
		) { [weak self] event in
			Task { @MainActor in
				self?.handleGlobalMouseDownWhileHidePromptVisible(event)
			}
		}

		// Dismiss on any keyboard input (including Cmd+Tab / Alt+Tab system
		// switchers) so the pill never lingers over the UI while the user is
		// changing apps/windows.
		globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.keyDown, .keyUp, .flagsChanged]
		) { [weak self] _ in
			Task { @MainActor in
				self?.dismissHidePrompt()
			}
		}
	}

	private func removeHidePromptDismissObservers() {
		for observer in hidePromptDismissObservers {
			NotificationCenter.default.removeObserver(observer)
		}
		hidePromptDismissObservers.removeAll()
		if let globalMouseMonitor {
			NSEvent.removeMonitor(globalMouseMonitor)
			self.globalMouseMonitor = nil
		}
		if let globalKeyboardMonitor {
			NSEvent.removeMonitor(globalKeyboardMonitor)
			self.globalKeyboardMonitor = nil
		}
	}

	private func handleGlobalMouseDownWhileHidePromptVisible(_ event: NSEvent) {
		guard let hidePromptPanel else { return }
		if event.window === hidePromptPanel {
			return
		}
		dismissHidePrompt()
	}

	private func removeLocalMouseMonitor() {
		guard let localMouseMonitor else { return }
		NSEvent.removeMonitor(localMouseMonitor)
		self.localMouseMonitor = nil
	}

	private func reconfigureTrackingAreasIfNeeded(force: Bool) {
		let needsRefresh = force
			|| FloatingInteractionPolicy.shouldRefreshTrackingAreas(
				previousBounds: CGRect(origin: .zero, size: lastTrackingBoundsSize),
				newBounds: bounds
			)
		guard needsRefresh else { return }

		isReconfiguringTracking = true
		defer { isReconfiguringTracking = false }

		if let boundsTrackingArea {
			removeTrackingArea(boundsTrackingArea)
		}
		if let affordanceTrackingArea {
			removeTrackingArea(affordanceTrackingArea)
		}

		let boundsArea = NSTrackingArea(
			rect: bounds,
			options: [
				.activeAlways,
				.mouseMoved,
				.mouseEnteredAndExited,
				.enabledDuringMouseDrag,
				.inVisibleRect,
			],
			owner: self,
			userInfo: ["kind": Self.trackingKindBounds]
		)
		addTrackingArea(boundsArea)
		boundsTrackingArea = boundsArea

		let affordanceRevealRect = FloatingInteractionPolicy.resizeAffordanceRevealRect(in: bounds)
		let affordanceArea = NSTrackingArea(
			rect: affordanceRevealRect,
			options: [
				.activeAlways,
				.mouseEnteredAndExited,
				.enabledDuringMouseDrag,
				.inVisibleRect,
			],
			owner: self,
			userInfo: ["kind": Self.trackingKindAffordance]
		)
		addTrackingArea(affordanceArea)
		affordanceTrackingArea = affordanceArea

		lastTrackingBoundsSize = bounds.size
	}

	private func syncPointerState(reason: String) {
		guard let window else { return }
		let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		handlePointerEvent(at: localPoint, reason: reason)
	}

	private func handlePointerEvent(at localPoint: CGPoint, reason: String) {
		if isTranslating {
			return
		}
		let inBounds = FloatingInteractionPolicy.pointerInBounds(localPoint, bounds: bounds)
		let inRevealRect = FloatingInteractionPolicy.resizeAffordanceRevealRect(in: bounds)
			.contains(localPoint)
		let wasInBounds = pointerInsideFrame
		pointerInsideFrame = inBounds
		if inBounds != wasInBounds {
			onHoverChange?(inBounds)
		}
		if inRevealRect {
			affordanceHoverActive = true
		} else if !isResizing {
			affordanceHoverActive = false
		}
		updateOverlayVisuals(
			localPoint: localPoint,
			pointerInAffordance: affordanceHoverActive || inRevealRect,
			reason: reason
		)
		onPointerUpdate?()
	}

	private func pushResizeCursor() {
		guard !resizeCursorPushed else { return }
		NSCursor.closedHand.push()
		resizeCursorPushed = true
	}

	private func popResizeCursorIfNeeded() {
		guard resizeCursorPushed else { return }
		NSCursor.pop()
		resizeCursorPushed = false
	}

	private func applyAffordanceCursor(for localPoint: CGPoint) {
		if isResizing {
			NSCursor.closedHand.set()
			return
		}
		let inAffordance = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds).contains(localPoint)
		if inAffordance {
			NSCursor.openHand.set()
		} else {
			NSCursor.arrow.set()
		}
	}

	private func updateOverlayVisuals(
		localPoint: CGPoint,
		pointerInAffordance: Bool,
		reason: String
	) {
		let shouldShowAffordance = FloatingInteractionPolicy.shouldShowResizeAffordance(
			pointerInAffordance: pointerInAffordance,
			isResizing: isResizing
		)
		let affordanceRect = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
		let affordanceChanged = overlayView.showsResizeAffordance != shouldShowAffordance
		overlayView.showsResizeAffordance = shouldShowAffordance
		overlayView.resizeAffordanceRect = affordanceRect
		if affordanceChanged || pointerInAffordance {
			elevateOverlayAboveSpriteKit()
			overlayView.needsDisplay = true
		}

		if pointerInsideFrame || isResizing {
			applyAffordanceCursor(for: localPoint)
		} else {
			NSCursor.arrow.set()
		}

		syncPointerIdleInteraction(reason: reason)
	}

	private func emitInteraction(_ interaction: FloatingInteraction?, reason: String) {
		guard interaction != lastEmittedInteraction else { return }
		lastEmittedInteraction = interaction
		interactionHandler(interaction)
	}

	/// Clears interaction overlays when the pointer leaves the frame (no hover
	/// jumping). Skipped while `mouseDragged` owns interaction selection.
	private func syncPointerIdleInteraction(reason: String) {
		guard activeInteraction == nil, !pointerInsideFrame else { return }
		emitInteraction(nil, reason: "pointer-left-\(reason)")
	}
}

/// Draws the resize affordance icon in a layer above SpriteKit so subview
/// hiding / Metal compositing cannot swallow it.
private final class FloatingPetOverlayView: NSView {
	var showsResizeAffordance = false
	var resizeAffordanceRect: CGRect = .zero

	override var isOpaque: Bool { false }

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override func draw(_ dirtyRect: NSRect) {
		guard showsResizeAffordance else { return }
		let drawRect = resizeAffordanceRect.isEmpty
			? FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
			: resizeAffordanceRect
		FloatingPetOverlayView.drawResizeAffordance(in: drawRect)
	}

	static func drawResizeAffordance(in affordanceBounds: CGRect) {
		let bgRect = affordanceBounds.insetBy(dx: 3, dy: 3)
		guard bgRect.width > 4, bgRect.height > 4 else {
			return
		}

		let background = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.20, alpha: 0.94)
		let rounded = NSBezierPath(roundedRect: bgRect, xRadius: 5, yRadius: 5)
		background.setFill()
		rounded.fill()

		if let symbol = NSImage(
			systemSymbolName: "arrow.up.left.and.arrow.down.right",
			accessibilityDescription: nil
		) {
			let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
				.applying(.init(hierarchicalColor: .white))
			let icon = symbol.withSymbolConfiguration(config) ?? symbol
			let iconSide = min(bgRect.width, bgRect.height) - 4
			icon.size = NSSize(width: iconSide, height: iconSide)
			let origin = NSPoint(
				x: bgRect.midX - iconSide / 2,
				y: bgRect.midY - iconSide / 2
			)
			icon.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
			return
		}

		drawFallbackArrows(in: bgRect)
	}

	private static func drawFallbackArrows(in bgRect: NSRect) {
		NSColor.white.withAlphaComponent(0.9).setStroke()
		let path = NSBezierPath()
		path.lineWidth = 1.5
		let inset: CGFloat = 5
		path.move(to: CGPoint(x: bgRect.minX + inset, y: bgRect.maxY - inset))
		path.line(to: CGPoint(x: bgRect.maxX - inset, y: bgRect.minY + inset))
		path.move(to: CGPoint(x: bgRect.minX + inset + 3, y: bgRect.maxY - inset))
		path.line(to: CGPoint(x: bgRect.minX + inset, y: bgRect.maxY - inset - 3))
		path.move(to: CGPoint(x: bgRect.maxX - inset, y: bgRect.minY + inset + 3))
		path.line(to: CGPoint(x: bgRect.maxX - inset - 3, y: bgRect.minY + inset))
		path.stroke()
	}
}

extension FloatingPetHidePrompt {
	/// Screen-space frame for the prompt window, anchored like `frame(...)` but
	/// clamped to the visible display bounds (not the floating pet window), so
	/// the pill can extend beyond the pet frame without clipping.
	static func screenFrame(anchor: CGPoint, promptSize: CGSize, visibleFrame: CGRect) -> CGRect {
		let margin: CGFloat = 6
		let inset = visibleFrame.insetBy(dx: margin, dy: margin)
		var minX = anchor.x
		var maxY = anchor.y
		if minX < inset.minX { minX = inset.minX }
		if maxY > inset.maxY { maxY = inset.maxY }
		var minY = maxY - promptSize.height
		if minY < inset.minY {
			minY = inset.minY
			maxY = minY + promptSize.height
		}
		if minX > inset.maxX - 12 {
			minX = inset.maxX - 12
		}
		return CGRect(x: minX, y: minY, width: promptSize.width, height: promptSize.height)
	}
}

/// One activatable row in the right-click prompt. A prompt with a single item is
/// the classic single "Hide" pill; multiple items stack vertically (e.g. a
/// "Force Idle" escape hatch above "Hide pet").
struct FloatingPetPromptItem {
	let title: String
	let onActivate: () -> Void
}

/// Ensures only one right-click prompt (Force Idle / Hide) is visible across
/// every floating panel at once. `NSEvent.addGlobalMonitorForEvents` only
/// reports events from *other* applications, so a right-click on a different
/// in-app panel is invisible to the previous panel's own dismiss-on-click-away
/// monitor — without this coordinator, that previous prompt is stranded on
/// screen (each panel can only dismiss its own). Every presenter asks the
/// coordinator to take over before showing its prompt, which dismisses
/// whichever other panel is currently active, mirroring the same-panel
/// re-right-click behavior the rest of the UI already has.
///
/// Internal (not file-private) so `FloatingInteractionTests` can exercise the
/// owner-handoff logic directly with fake owners — no live window session
/// needed since this class holds no AppKit state of its own.
final class FloatingPetPromptCoordinator {
	static let shared = FloatingPetPromptCoordinator()

	private weak var activeOwner: AnyObject?
	private var activeDismiss: (() -> Void)?

	/// Not `private` so tests can construct isolated instances rather than
	/// sharing mutable state through `.shared` across test methods.
	init() {}

	/// Call immediately before presenting a new prompt. Dismisses any other
	/// panel's currently active prompt, then registers `owner` as active.
	func willPresent(owner: AnyObject, dismiss: @escaping () -> Void) {
		if activeOwner !== owner {
			activeDismiss?()
		}
		activeOwner = owner
		activeDismiss = dismiss
	}

	/// Call whenever `owner` dismisses its own prompt, for any reason, so a
	/// stale dismiss closure is never retained once that prompt is gone.
	func didDismiss(owner: AnyObject) {
		guard activeOwner === owner else { return }
		activeOwner = nil
		activeDismiss = nil
	}
}

private final class FloatingPetHidePromptPanel: NSPanel {
	private var rowViews: [FloatingPetHidePromptView] = []

	init(frame: CGRect, items: [FloatingPetPromptItem]) {
		super.init(
			contentRect: frame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		// A right-click context menu must sit ABOVE the pet chrome (platform chip,
		// animation badge, attention bubble — all `.floating`). Those panels are
		// re-ordered front on every ~1s poll tick, which would otherwise bury this
		// prompt seconds after it appears, so left-clicks on "Force Idle" / "Hide"
		// landed on the buried-under chrome instead of the pill. `.popUpMenu`
		// (level 101 vs `.floating` = 3) keeps the prompt reliably on top.
		level = .popUpMenu
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true

		let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
		container.autoresizingMask = [.width, .height]
		// All rows share the same font/padding, so each is one preferred-height
		// tall. Lay them top-to-bottom (AppKit origin is bottom-left) so items[0]
		// renders at the top of the stack.
		for (index, item) in items.enumerated() {
			let rowFrame = FloatingPetHidePrompt.rowFrame(
				index: index,
				count: items.count,
				panelSize: frame.size
			)
			let row = FloatingPetHidePromptView(
				frame: rowFrame,
				title: item.title,
				onActivate: item.onActivate
			)
			container.addSubview(row)
			rowViews.append(row)
		}
		contentView = container
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}

/// Frosted pill shown on right-click; matches the Codex “Close pet” control.
private final class FloatingPetHidePromptView: NSView {
	private let onActivate: () -> Void
	private var trackingArea: NSTrackingArea?
	private var isHighlighted = false

	private let effectView = NSVisualEffectView(frame: .zero)
	private let tintView = FloatingPetHidePromptTintView(frame: .zero)
	private let label: NSTextField

	init(frame frameRect: NSRect, title: String = FloatingPetHidePrompt.title, onActivate: @escaping () -> Void) {
		self.onActivate = onActivate
		self.label = NSTextField(labelWithString: title)
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.isEmphasized = false
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		tintView.wantsLayer = true
		tintView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tintView)

		label.font = FloatingPetHidePrompt.font
		label.textColor = .white
		label.alignment = .center
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		label.layer?.zPosition = 2
		addSubview(label)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyChromeStyles()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		nil
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea {
			removeTrackingArea(trackingArea)
		}
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) {
		setHighlighted(true)
	}

	override func mouseExited(with event: NSEvent) {
		setHighlighted(false)
	}

	override func layout() {
		super.layout()
		let radius = bounds.height / 2
		effectView.layer?.cornerRadius = radius
		effectView.layer?.masksToBounds = true
		tintView.layer?.cornerRadius = radius
		tintView.layer?.masksToBounds = true
		applyChromeStyles()
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		// `point` arrives in our SUPERVIEW's coordinate system; convert to our own
		// bounds before testing. When this row is a stacked subview (frame origin
		// != 0,0 — e.g. the top "Force Idle" row) comparing the raw superview-space
		// point against local `bounds` misses entirely, so the click falls through
		// to the container and nothing fires. This bug only spared the bottom row,
		// whose origin happens to be (0,0).
		let local = superview.map { convert(point, from: $0) } ?? point
		return bounds.contains(local) ? self : nil
	}

	override func mouseDown(with event: NSEvent) {
		activate()
	}

	func setHighlighted(_ highlighted: Bool) {
		guard isHighlighted != highlighted else { return }
		isHighlighted = highlighted
		applyChromeStyles()
	}

	func activate() {
		onActivate()
	}

	private func applyChromeStyles() {
		let radius = bounds.height / 2
		layer?.cornerRadius = radius
		effectView.isEmphasized = isHighlighted
		if isHighlighted {
			// Codex hover: solid blue, fully opaque.
			tintView.setGradient(
				top: NSColor(calibratedRed: 0.19, green: 0.44, blue: 0.98, alpha: 0.98),
				bottom: NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.92, alpha: 0.98)
			)
			layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
			layer?.shadowOpacity = 0.38
		} else {
			// Codex idle: dark charcoal over vibrancy so the pet blurs but the pill reads clearly.
			tintView.setGradient(
				top: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.19, alpha: 0.92),
				bottom: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 0.90)
			)
			layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
			layer?.shadowOpacity = 0.28
		}
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowRadius = 6
		layer?.shadowOffset = CGSize(width: 0, height: -2)
	}
}

private final class FloatingPetHidePromptTintView: NSView {
	override func makeBackingLayer() -> CALayer {
		let layer = CAGradientLayer()
		layer.startPoint = CGPoint(x: 0.5, y: 1)
		layer.endPoint = CGPoint(x: 0.5, y: 0)
		return layer
	}

	private var gradientLayer: CAGradientLayer? { layer as? CAGradientLayer }

	func setGradient(top: NSColor, bottom: NSColor) {
		gradientLayer?.colors = [bottom.cgColor, top.cgColor]
	}
}

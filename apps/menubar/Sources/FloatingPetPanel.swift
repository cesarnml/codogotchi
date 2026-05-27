import AppKit
import SpriteKit

@MainActor
final class FloatingPetPanelController: FloatingPetPanelManaging {
	private let codexPet: CodexPet
	private let codogotchiPet: CodogotchiPet?
	private let demoFrameInterval: TimeInterval?
	private let visibleFrameProvider: () -> CGRect
	private var panel: NSPanel?
	private var scene: FloatingPetScene?
	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var frameChangeHandler: ((CGRect) -> Void)?
	var onHideFloatingPet: (() -> Void)?

	init(
		codexPet: CodexPet,
		codogotchiPet: CodogotchiPet?,
		demoFrameInterval: TimeInterval? = nil,
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
		}
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.demoFrameInterval = demoFrameInterval
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
				demoFrameInterval: demoFrameInterval
			)
			scene.update(state: currentState, visualMode: currentMode)
			self.scene = scene
			(panel.contentView as? FloatingPetInteractionView)?.presentScene(scene)
		} else {
			scene?.size = frame.size
			scene?.update(state: currentState, visualMode: currentMode)
		}

		panel.orderFrontRegardless()
		self.panel = panel
		if let interactionView = panel.contentView as? FloatingPetInteractionView {
			interactionView.frame = NSRect(origin: .zero, size: frame.size)
			interactionView.prepareForDisplay()
		}
	}

	func hide() {
		(panel?.contentView as? FloatingPetInteractionView)?.dismissHidePromptIfPresent()
		panel?.orderOut(nil)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		currentState = state
		currentMode = visualMode
		scene?.update(state: state, visualMode: visualMode)
	}

	func setInteraction(_ interaction: FloatingInteraction?) {
		scene?.setInteraction(interaction)
	}

	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
		frameChangeHandler = handler
		(panel?.contentView as? FloatingPetInteractionView)?.frameChangeHandler = handler
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
		view.frameChangeHandler = frameChangeHandler
		view.hideFloatingPetHandler = { [weak self] in
			self?.onHideFloatingPet?()
		}
		return view
	}
}

/// Layout for the in-frame “Hide pet” pill shown on right-click (Codex-style).
enum FloatingPetHidePrompt {
	static let title = "Hide pet"
	static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
	static let horizontalPadding: CGFloat = 14
	static let verticalPadding: CGFloat = 7

	static func preferredSize(title: String = FloatingPetHidePrompt.title) -> CGSize {
		let textSize = (title as NSString).size(withAttributes: [.font: font])
		let height = ceil(textSize.height) + verticalPadding * 2
		let width = ceil(textSize.width) + horizontalPadding * 2
		return CGSize(width: width, height: height)
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

	/// Reserved-row interaction while the pointer is over the frame but not
	/// dragging (P4.07 hover feedback).
	static func hoverInteraction(pointerInBounds: Bool, isDragging: Bool) -> FloatingInteraction? {
		guard pointerInBounds, !isDragging else { return nil }
		return .jumping
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
			return .jumping
		case .dragRegion:
			if delta.width > 0 { return .runningRight }
			if delta.width < 0 { return .runningLeft }
			// Vertical-only steps must not drop back to activity frames mid-drag
			// (common on the first `mouseDragged` tick while hover is `.jumping`).
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
	var hideFloatingPetHandler: (() -> Void)?

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
		if kind == Self.trackingKindBounds || kind == nil {
			pointerInsideFrame = false
		}
		handlePointerEvent(
			at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil),
			reason: "mouseExited(\(kind ?? "bounds"))"
		)
	}

	override func rightMouseDown(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		guard FloatingPetHidePrompt.shouldPresent(
			at: localPoint,
			in: bounds,
			hasActivePointerInteraction: activeInteraction != nil
		) else {
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
		case .resizeAffordance:
			activeInteraction = .resize(startFrame: window.frame, startScreenPoint: startScreenPoint)
			pushResizeCursor()
			handlePointerEvent(at: localPoint, reason: "mouseDown-resize")
		}
	}

	override func mouseDragged(with event: NSEvent) {
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
			let dragDelta: CGSize
			let rawDelta = CGSize(
				width: currentPoint.x - startScreenPoint.x,
				height: currentPoint.y - startScreenPoint.y
			)
			dragDelta = FloatingInteractionPolicy.resizeDragDelta(from: rawDelta)
			hitTarget = .resizeAffordance
			let startAspect = startFrame.height > 0 ? startFrame.width / startFrame.height : 1
			nextFrame = FloatingInteractionPolicy.resizedFrame(
				from: startFrame,
				dragDelta: rawDelta,
				visibleFrame: visibleFrameProvider()
			)
			let endAspect = nextFrame.height > 0 ? nextFrame.width / nextFrame.height : 1
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
		let wasResizing = isResizing
		window?.displayIfNeeded()
		activeInteraction = nil
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
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let visibleFrame = window.screen?.visibleFrame ?? visibleFrameProvider()
		let screenFrame = FloatingPetHidePrompt.screenFrame(
			anchor: anchorInScreen,
			promptSize: promptSize,
			visibleFrame: visibleFrame
		)
		let panel = FloatingPetHidePromptPanel(frame: screenFrame) { [weak self] in
			self?.dismissHidePrompt()
			self?.hideFloatingPetHandler?()
		}
		panel.orderFrontRegardless()
		hidePromptPanel = panel
		installHidePromptDismissObservers()
	}

	func dismissHidePromptIfPresent() {
		dismissHidePrompt()
	}

	private func dismissHidePrompt() {
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

		let affordanceRect = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
		let affordanceArea = NSTrackingArea(
			rect: affordanceRect,
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
		let inAffordanceRect = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
			.contains(localPoint)
		pointerInsideFrame = inBounds
		if inAffordanceRect {
			affordanceHoverActive = true
		} else if !isResizing {
			affordanceHoverActive = false
		}
		updateOverlayVisuals(
			localPoint: localPoint,
			pointerInAffordance: affordanceHoverActive || inAffordanceRect,
			reason: reason
		)
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

		syncHoverInteraction(reason: reason)
	}

	private func emitInteraction(_ interaction: FloatingInteraction?, reason: String) {
		guard interaction != lastEmittedInteraction else { return }
		lastEmittedInteraction = interaction
		interactionHandler(interaction)
	}

	/// Hover feedback when no drag is active; skipped while `mouseDragged` owns
	/// interaction selection.
	private func syncHoverInteraction(reason: String) {
		guard activeInteraction == nil else { return }
		let hover = FloatingInteractionPolicy.hoverInteraction(
			pointerInBounds: pointerInsideFrame,
			isDragging: false
		)
		emitInteraction(hover, reason: "hover-\(reason)")
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

private final class FloatingPetHidePromptPanel: NSPanel {
	private let promptView: FloatingPetHidePromptView

	init(frame: CGRect, onActivate: @escaping () -> Void) {
		self.promptView = FloatingPetHidePromptView(
			frame: CGRect(origin: .zero, size: frame.size),
			onActivate: onActivate
		)
		super.init(
			contentRect: frame,
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
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true
		contentView = promptView
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
	private let label = NSTextField(labelWithString: FloatingPetHidePrompt.title)

	init(frame frameRect: NSRect, onActivate: @escaping () -> Void) {
		self.onActivate = onActivate
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
		bounds.contains(point) ? self : nil
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

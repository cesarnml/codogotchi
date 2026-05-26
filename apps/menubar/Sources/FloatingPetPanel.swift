import AppKit
import SpriteKit

@MainActor
final class FloatingPetPanelController: FloatingPetPanelManaging {
	private let codexPet: MaliPet
	private let codogotchiPet: CodogotchiPet?
	private let visibleFrameProvider: () -> CGRect
	private var panel: NSPanel?
	private var scene: FloatingPetScene?
	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var frameChangeHandler: ((CGRect) -> Void)?

	init(
		codexPet: MaliPet,
		codogotchiPet: CodogotchiPet?,
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
		}
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.visibleFrameProvider = visibleFrameProvider
	}

	func show(frame: CGRect) {
		let panel = self.panel ?? makePanel(frame: frame)
		panel.setFrame(frame, display: true)

		if scene == nil {
			let scene = FloatingPetScene(
				size: frame.size,
				codexPet: codexPet,
				codogotchiPet: codogotchiPet
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
	}

	func hide() {
		panel?.orderOut(nil)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		currentState = state
		currentMode = visualMode
		scene?.update(state: state, visualMode: visualMode)
	}

	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
		frameChangeHandler = handler
		(panel?.contentView as? FloatingPetInteractionView)?.frameChangeHandler = handler
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
		panel.contentView = makeContentView(frame: frame, panel: panel)
		return panel
	}

	private func makeContentView(frame: CGRect, panel: NSPanel) -> FloatingPetInteractionView {
		let view = FloatingPetInteractionView(
			frame: CGRect(origin: .zero, size: frame.size),
			visibleFrameProvider: { [weak panel, visibleFrameProvider] in
				panel?.screen?.visibleFrame ?? visibleFrameProvider()
			}
		)
		view.frameChangeHandler = frameChangeHandler
		return view
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

	static func resizedFrame(
		from frame: CGRect,
		dragDelta: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		FloatingFramePolicy.clamp(
			CGRect(
				x: frame.origin.x,
				y: frame.origin.y,
				width: frame.width + dragDelta.width,
				height: frame.height + dragDelta.height
			),
			to: visibleFrame
		)
	}
}

private final class FloatingPetInteractionView: NSView {
	private enum ActiveInteraction {
		case drag(startFrame: CGRect, startScreenPoint: CGPoint)
		case resize(startFrame: CGRect, startScreenPoint: CGPoint)
	}

	private let skView = SKView(frame: .zero)
	private let resizeAffordanceView = FloatingResizeAffordanceView(frame: .zero)
	private let visibleFrameProvider: () -> CGRect
	private var activeInteraction: ActiveInteraction?
	var frameChangeHandler: ((CGRect) -> Void)?

	init(frame: CGRect, visibleFrameProvider: @escaping () -> CGRect) {
		self.visibleFrameProvider = visibleFrameProvider
		super.init(frame: frame)

		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		skView.allowsTransparency = true
		skView.ignoresSiblingOrder = true
		skView.autoresizingMask = [.width, .height]
		addSubview(skView)
		addSubview(resizeAffordanceView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		nil
	}

	func presentScene(_ scene: SKScene) {
		skView.presentScene(scene)
	}

	override var isFlipped: Bool { false }

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }
		return self
	}

	override func layout() {
		super.layout()
		skView.frame = bounds
		resizeAffordanceView.frame = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
	}

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		let localPoint = convert(event.locationInWindow, from: nil)
		let startScreenPoint = NSEvent.mouseLocation
		switch FloatingInteractionPolicy.hitTest(point: localPoint, in: bounds) {
		case .dragRegion:
			activeInteraction = .drag(startFrame: window.frame, startScreenPoint: startScreenPoint)
		case .resizeAffordance:
			activeInteraction = .resize(startFrame: window.frame, startScreenPoint: startScreenPoint)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		guard let window, let activeInteraction else { return }
		let currentPoint = NSEvent.mouseLocation
		let nextFrame: CGRect

		switch activeInteraction {
		case let .drag(startFrame, startScreenPoint):
			nextFrame = FloatingInteractionPolicy.draggedFrame(
				from: startFrame,
				dragDelta: CGSize(
					width: currentPoint.x - startScreenPoint.x,
					height: currentPoint.y - startScreenPoint.y
				),
				visibleFrame: visibleFrameProvider()
			)
		case let .resize(startFrame, startScreenPoint):
			nextFrame = FloatingInteractionPolicy.resizedFrame(
				from: startFrame,
				dragDelta: CGSize(
					width: currentPoint.x - startScreenPoint.x,
					height: currentPoint.y - startScreenPoint.y
				),
				visibleFrame: visibleFrameProvider()
			)
		}

		window.setFrame(nextFrame, display: true)
	}

	override func mouseUp(with event: NSEvent) {
		activeInteraction = nil
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(
			FloatingInteractionPolicy.resizeAffordanceRect(in: bounds),
			cursor: .resizeLeftRight
		)
	}
}

private final class FloatingResizeAffordanceView: NSView {
	override var isOpaque: Bool { false }

	override func draw(_ dirtyRect: NSRect) {
		NSColor.white.withAlphaComponent(0.42).setStroke()
		let path = NSBezierPath()
		path.lineWidth = 1.5
		let inset: CGFloat = 7

		path.move(to: CGPoint(x: bounds.maxX - inset, y: bounds.minY + inset))
		path.line(to: CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
		path.move(to: CGPoint(x: bounds.maxX - inset, y: bounds.minY + inset))
		path.line(to: CGPoint(x: bounds.minX + inset, y: bounds.minY + inset))
		path.stroke()
	}
}

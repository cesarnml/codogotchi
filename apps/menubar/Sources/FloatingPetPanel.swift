import AppKit
import SpriteKit

@MainActor
final class FloatingPetPanelController: FloatingPetPanelManaging {
	private let codexPet: MaliPet
	private let codogotchiPet: CodogotchiPet?
	private var panel: NSPanel?
	private var scene: FloatingPetScene?
	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal

	init(codexPet: MaliPet, codogotchiPet: CodogotchiPet?) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
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
			(panel.contentView as? SKView)?.presentScene(scene)
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
		panel.contentView = makeContentView(frame: frame)
		return panel
	}

	private func makeContentView(frame: CGRect) -> SKView {
		let view = SKView(frame: CGRect(origin: .zero, size: frame.size))
		view.autoresizingMask = [.width, .height]
		view.allowsTransparency = true
		view.ignoresSiblingOrder = true
		return view
	}
}

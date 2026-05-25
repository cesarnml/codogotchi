import CoreGraphics
import Foundation

@MainActor
protocol FloatingPetVisibilityControlling: AnyObject {
	var isFloatingPetVisible: Bool { get }
	func setFloatingPetVisible(_ visible: Bool)
}

@MainActor
protocol FloatingPetPanelManaging: AnyObject {
	func show(frame: CGRect)
	func hide()
}

@MainActor
final class FloatingPetController: FloatingPetVisibilityControlling {
	private let panel: FloatingPetPanelManaging
	private let visibleFrameProvider: () -> CGRect
	private var state: FloatingAppState

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }

	init(
		panel: FloatingPetPanelManaging,
		visibleFrameProvider: @escaping () -> CGRect
	) {
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.state = AppStateStore.load(visibleFrame: visibleFrameProvider())

		if state.isFloatingPetVisible {
			panel.show(frame: state.frame)
		}
	}

	func setFloatingPetVisible(_ visible: Bool) {
		let visibleFrame = visibleFrameProvider()
		let nextState = FloatingAppState(
			isFloatingPetVisible: visible,
			frame: FloatingFramePolicy.clamp(state.frame, to: visibleFrame)
		)
		state = nextState
		try? AppStateStore.save(nextState)

		if visible {
			panel.show(frame: nextState.frame)
		} else {
			panel.hide()
		}
	}
}

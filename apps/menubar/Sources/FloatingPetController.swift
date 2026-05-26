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
	func apply(state: ActivityState, visualMode: VisualMode)
}

@MainActor
final class FloatingPetController: FloatingPetVisibilityControlling {
	private let panel: FloatingPetPanelManaging
	private let visibleFrameProvider: () -> CGRect
	private let saveState: (FloatingAppState) throws -> Void
	private var state: FloatingAppState

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }

	init(
		panel: FloatingPetPanelManaging,
		visibleFrameProvider: @escaping () -> CGRect,
		saveState: @escaping (FloatingAppState) throws -> Void = AppStateStore.save
	) {
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.saveState = saveState
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
		do {
			try saveState(nextState)
		} catch {
			NSLog("FloatingPetController: failed to persist floating visibility: \(error.localizedDescription)")
			return
		}

		state = nextState

		if visible {
			panel.show(frame: nextState.frame)
		} else {
			panel.hide()
		}
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		panel.apply(state: state, visualMode: visualMode)
	}
}

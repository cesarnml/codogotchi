import AppKit
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
	func setInteraction(_ interaction: FloatingInteraction?)
	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void)
}

@MainActor
final class FloatingPetController: NSObject, FloatingPetVisibilityControlling {
	private let panel: FloatingPetPanelManaging
	private let visibleFrameProvider: () -> CGRect
	private let saveState: (FloatingAppState) throws -> Void
	private var state: FloatingAppState
	private let notificationCenter: NotificationCenter

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }

	init(
		panel: FloatingPetPanelManaging,
		visibleFrameProvider: @escaping () -> CGRect,
		saveState: @escaping (FloatingAppState) throws -> Void = AppStateStore.save,
		notificationCenter: NotificationCenter = .default
	) {
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.saveState = saveState
		self.notificationCenter = notificationCenter
		self.state = AppStateStore.load(visibleFrame: visibleFrameProvider())
		super.init()

		panel.setFrameChangeHandler { [weak self] frame in
			self?.persistFrameChange(frame)
		}
		notificationCenter.addObserver(
			self,
			selector: #selector(displayParametersDidChange(_:)),
			name: NSApplication.didChangeScreenParametersNotification,
			object: nil
		)

		if state.isFloatingPetVisible {
			panel.show(frame: state.frame)
		}
	}

	deinit {
		notificationCenter.removeObserver(self)
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

	func persistFrameChange(_ frame: CGRect) {
		saveClampedFrame(frame, visibleFrame: visibleFrameProvider(), logLabel: "frame change")
	}

	func reclampForVisibleFrameChange() {
		saveClampedFrame(
			state.frame,
			visibleFrame: visibleFrameProvider(),
			logLabel: "display change"
		)
	}

	@objc private func displayParametersDidChange(_ notification: Notification) {
		reclampForVisibleFrameChange()
	}

	private func saveClampedFrame(_ frame: CGRect, visibleFrame: CGRect, logLabel: String) {
		let nextState = FloatingAppState(
			isFloatingPetVisible: state.isFloatingPetVisible,
			frame: FloatingFramePolicy.clamp(frame, to: visibleFrame)
		)
		do {
			try saveState(nextState)
		} catch {
			NSLog("FloatingPetController: failed to persist floating \(logLabel): \(error.localizedDescription)")
			return
		}

		state = nextState
		if nextState.isFloatingPetVisible {
			panel.show(frame: nextState.frame)
		}
	}
}

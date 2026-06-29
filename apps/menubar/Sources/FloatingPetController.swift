import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol FloatingPetVisibilityControlling: AnyObject {
	var isFloatingPetVisible: Bool { get }
	func setFloatingPetVisible(_ visible: Bool)
}

/// Unified interface for a single floating-pet window managed by `FloatingPetWindowPool`.
/// `FloatingPetController` conforms; tests inject lightweight stubs.
@MainActor
protocol FloatingPetWindowControlling: FloatingPetVisibilityControlling {
	func apply(state: ActivityState, visualMode: VisualMode)
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?)
	func applyGateBadge(content: GateBadgeContent?)
	func applyPlatform(origin: String?)
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?)
}

@MainActor
protocol FloatingPetPanelManaging: AnyObject {
	func show(frame: CGRect)
	func hide()
	func apply(state: ActivityState, visualMode: VisualMode)
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?)
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?)
	func applyGateBadge(content: GateBadgeContent?)
	func applyPlatform(origin: String?)
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)
	func setRPGHUDEnabled(_ enabled: Bool)
	func setHUDDemoActive(_ active: Bool)
	func setHUDPinned(_ pinned: Bool)
	func setInteraction(_ interaction: FloatingInteraction?)
	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void)
}

extension FloatingPetPanelManaging {
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
	func applyGateBadge(content: GateBadgeContent?) {}
	func applyPlatform(origin: String?) {}
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
	func setRPGHUDEnabled(_ enabled: Bool) {}
	func setHUDDemoActive(_ active: Bool) {}
	func setHUDPinned(_ pinned: Bool) {}
}

@MainActor
final class FloatingPetController: NSObject, FloatingPetVisibilityControlling, FloatingPetWindowControlling {
	private let panel: FloatingPetPanelManaging
	private let visibleFrameProvider: () -> CGRect
	private let saveState: (FloatingAppState) throws -> Void
	private var state: FloatingAppState
	private let notificationCenter: NotificationCenter

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }

	/// Called after visibility is persisted and the panel is shown or hidden.
	var onVisibilityChanged: ((Bool) -> Void)?

	init(
		panel: FloatingPetPanelManaging,
		visibleFrameProvider: @escaping () -> CGRect,
		saveState: @escaping (FloatingAppState) throws -> Void = AppStateStore.save,
		notificationCenter: NotificationCenter = .default,
		initialState: FloatingAppState? = nil
	) {
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.saveState = saveState
		self.notificationCenter = notificationCenter
		self.state = initialState ?? AppStateStore.load(visibleFrame: visibleFrameProvider())
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
		onVisibilityChanged?(state.isFloatingPetVisible)
	}

	deinit {
		notificationCenter.removeObserver(self)
	}

	func setFloatingPetVisible(_ visible: Bool) {
		let visibleFrame = visibleFrameProvider()
		let nextState = FloatingAppState(
			isFloatingPetVisible: visible,
			frame: FloatingFramePolicy.clamp(state.frame, to: visibleFrame),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
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
		onVisibilityChanged?(visible)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		panel.apply(state: state, visualMode: visualMode)
	}

	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		panel.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		panel.applyAttention(payload: payload, sourceEvent: sourceEvent)
	}

	func applyGateBadge(content: GateBadgeContent?) {
		panel.applyGateBadge(content: content)
	}

	func applyPlatform(origin: String?) {
		panel.applyPlatform(origin: origin)
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		panel.applyRPGState(
			halfHearts: halfHearts,
			levelFraction: levelFraction,
			level: level,
			activeMinutes: activeMinutes,
			hudEnabled: hudEnabled
		)
	}

	func setRPGHUDEnabled(_ enabled: Bool) {
		panel.setRPGHUDEnabled(enabled)
	}

	func setHUDDemoActive(_ active: Bool) {
		panel.setHUDDemoActive(active)
	}

	func setHUDPinned(_ pinned: Bool) {
		panel.setHUDPinned(pinned)
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
			frame: FloatingFramePolicy.clamp(frame, to: visibleFrame),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
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

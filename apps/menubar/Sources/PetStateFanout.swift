import Foundation

@MainActor
final class PetStateFanout {
	typealias Apply = (ActivityState, VisualMode) -> Void

	private let applyToMenubar: Apply
	private let applyToFloatingPet: Apply

	init(
		applyToMenubar: @escaping Apply,
		applyToFloatingPet: @escaping Apply
	) {
		self.applyToMenubar = applyToMenubar
		self.applyToFloatingPet = applyToFloatingPet
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		applyToMenubar(state, visualMode)
		applyToFloatingPet(state, visualMode)
	}

	func applyDemo(state: ActivityState) {
		apply(state: state, visualMode: .normal)
	}
}

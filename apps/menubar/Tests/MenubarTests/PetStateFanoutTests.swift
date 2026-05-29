import XCTest

@testable import Codogotchi

@MainActor
final class PetStateFanoutTests: XCTestCase {
	func testApplySendsSameLiveStateToMenuBarAndFloatingTargets() {
		var menuEvents: [(ActivityState, VisualMode)] = []
		var floatingEvents: [(ActivityState, VisualMode)] = []
		let fanout = PetStateFanout(
			applyToMenubar: { state, mode in menuEvents.append((state, mode)) },
			applyToFloatingPet: { state, mode in floatingEvents.append((state, mode)) }
		)

		fanout.apply(state: .testing, visualMode: .desaturated)

		XCTAssertEqual(menuEvents.count, 1)
		XCTAssertEqual(floatingEvents.count, 1)
		XCTAssertEqual(menuEvents[0].0, .testing)
		XCTAssertEqual(menuEvents[0].1, .desaturated)
		XCTAssertEqual(floatingEvents[0].0, .testing)
		XCTAssertEqual(floatingEvents[0].1, .desaturated)
	}

	func testApplyDemoUsesSameFanoutPathWithNormalVisualMode() {
		var menuEvents: [(ActivityState, VisualMode)] = []
		var floatingEvents: [(ActivityState, VisualMode)] = []
		let fanout = PetStateFanout(
			applyToMenubar: { state, mode in menuEvents.append((state, mode)) },
			applyToFloatingPet: { state, mode in floatingEvents.append((state, mode)) }
		)

		fanout.applyDemo(state: .ticketCompleted)

		XCTAssertEqual(menuEvents.count, 1)
		XCTAssertEqual(floatingEvents.count, 1)
		XCTAssertEqual(menuEvents[0].0, .ticketCompleted)
		XCTAssertEqual(menuEvents[0].1, .normal)
		XCTAssertEqual(floatingEvents[0].0, .ticketCompleted)
		XCTAssertEqual(floatingEvents[0].1, .normal)
	}
}

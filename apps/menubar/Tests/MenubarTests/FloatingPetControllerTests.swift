import CoreGraphics
import XCTest

@testable import Codogotchi

@MainActor
final class FloatingPetControllerTests: XCTestCase {
	final class FloatingPetPanelSpy: FloatingPetPanelManaging {
		var shownFrames: [CGRect] = []
		var hideCount = 0
		var appliedStates: [(ActivityState, VisualMode)] = []

		func show(frame: CGRect) {
			shownFrames.append(frame)
		}

		func hide() {
			hideCount += 1
		}

		func apply(state: ActivityState, visualMode: VisualMode) {
			appliedStates.append((state, visualMode))
		}
	}

	struct SaveFailure: Error {}

	private let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

	private func withTempHome(_ body: (URL) throws -> Void) rethrows {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("floating-controller-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}

		try body(tmp)
	}

	func testHiddenInitialAppStateDoesNotRequestPanelDisplay() throws {
		try withTempHome { _ in
			let state = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(state)
			let panel = FloatingPetPanelSpy()

			_ = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })

			XCTAssertEqual(panel.shownFrames, [])
			XCTAssertEqual(panel.hideCount, 0)
		}
	}

	func testVisibleInitialAppStateRequestsPanelDisplayAtSavedFrame() throws {
		try withTempHome { _ in
			let state = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(state)
			let panel = FloatingPetPanelSpy()

			_ = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })

			XCTAssertEqual(panel.shownFrames, [state.frame])
			XCTAssertEqual(panel.hideCount, 0)
		}
	}

	func testSetFloatingPetVisiblePersistsVisibilityAndShowsOrHidesPanel() throws {
		try withTempHome { _ in
			let initial = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(initial)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })

			controller.setFloatingPetVisible(true)
			XCTAssertTrue(controller.isFloatingPetVisible)
			XCTAssertEqual(panel.shownFrames, [initial.frame])
			XCTAssertTrue(AppStateStore.load(visibleFrame: visibleFrame).isFloatingPetVisible)

			controller.setFloatingPetVisible(false)
			XCTAssertFalse(controller.isFloatingPetVisible)
			XCTAssertEqual(panel.hideCount, 1)
			XCTAssertFalse(AppStateStore.load(visibleFrame: visibleFrame).isFloatingPetVisible)
		}
	}

	func testSetFloatingPetVisibleDoesNotAdvancePanelOrMemoryWhenSaveFails() throws {
		try withTempHome { _ in
			let initial = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(initial)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(
				panel: panel,
				visibleFrameProvider: { self.visibleFrame },
				saveState: { _ in throw SaveFailure() }
			)

			controller.setFloatingPetVisible(true)

			XCTAssertFalse(controller.isFloatingPetVisible)
			XCTAssertEqual(panel.shownFrames, [])
			XCTAssertEqual(panel.hideCount, 0)
			XCTAssertFalse(AppStateStore.load(visibleFrame: visibleFrame).isFloatingPetVisible)
		}
	}

	func testApplyStateWhileHiddenDoesNotCrashAndReachesPanelRenderer() throws {
		try withTempHome { _ in
			let initial = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(initial)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })

			controller.apply(state: .errored, visualMode: .desaturated)

			XCTAssertEqual(panel.appliedStates.count, 1)
			XCTAssertEqual(panel.appliedStates[0].0, .errored)
			XCTAssertEqual(panel.appliedStates[0].1, .desaturated)
			XCTAssertEqual(panel.shownFrames, [])
		}
	}
}

import CoreGraphics
import XCTest

@testable import Codogotchi

@MainActor
final class FloatingPetControllerTests: XCTestCase {
	final class FloatingPetPanelSpy: FloatingPetPanelManaging {
		var shownFrames: [CGRect] = []
		var hideCount = 0
		var appliedStates: [(ActivityState, VisualMode)] = []
		var frameChangeHandler: ((CGRect) -> Void)?

		func show(frame: CGRect) {
			shownFrames.append(frame)
		}

		func hide() {
			hideCount += 1
		}

		func apply(state: ActivityState, visualMode: VisualMode) {
			appliedStates.append((state, visualMode))
		}

		func setInteraction(_ interaction: FloatingInteraction?) {
			appliedInteractions.append(interaction)
		}

		func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
			frameChangeHandler = handler
		}

		var appliedInteractions: [FloatingInteraction?] = []
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

	func testFloatingInteractionHitTestingDistinguishesResizeAffordanceFromDragRegion() {
		let bounds = CGRect(x: 0, y: 0, width: 160, height: 160)

		XCTAssertEqual(
			FloatingInteractionPolicy.hitTest(point: CGPoint(x: 148, y: 12), in: bounds),
			.resizeAffordance
		)
		XCTAssertEqual(
			FloatingInteractionPolicy.hitTest(point: CGPoint(x: 80, y: 80), in: bounds),
			.dragRegion
		)
	}

	func testPointerInBoundsUsesViewCoordinateSpace() {
		let bounds = CGRect(x: 0, y: 0, width: 160, height: 160)
		XCTAssertTrue(FloatingInteractionPolicy.pointerInBounds(CGPoint(x: 80, y: 80), bounds: bounds))
		XCTAssertFalse(FloatingInteractionPolicy.pointerInBounds(CGPoint(x: -1, y: 80), bounds: bounds))
	}

	func testTrackingAreasRefreshOnlyWhenBoundsSizeChanges() {
		let first = CGRect(x: 0, y: 0, width: 160, height: 160)
		let sameSizeMoved = CGRect(x: 10, y: 20, width: 160, height: 160)
		let resized = CGRect(x: 0, y: 0, width: 200, height: 180)

		XCTAssertFalse(
			FloatingInteractionPolicy.shouldRefreshTrackingAreas(
				previousBounds: first,
				newBounds: sameSizeMoved
			)
		)
		XCTAssertTrue(
			FloatingInteractionPolicy.shouldRefreshTrackingAreas(
				previousBounds: first,
				newBounds: resized
			)
		)
	}

	func testResizeAffordanceHiddenUntilPointerHovers() {
		XCTAssertFalse(
			FloatingInteractionPolicy.shouldShowResizeAffordance(
				pointerInAffordance: false,
				isResizing: false
			)
		)
		XCTAssertTrue(
			FloatingInteractionPolicy.shouldShowResizeAffordance(
				pointerInAffordance: true,
				isResizing: false
			)
		)
		XCTAssertTrue(
			FloatingInteractionPolicy.shouldShowResizeAffordance(
				pointerInAffordance: false,
				isResizing: true
			),
			"affordance stays visible for the duration of an active resize drag"
		)
	}

	func testHorizontalResizeDragUsesUniformScaleFromWidth() {
		let delta = FloatingInteractionPolicy.resizeDragDelta(
			from: CGSize(width: 40, height: 4)
		)
		XCTAssertEqual(delta.width, 40)
		XCTAssertEqual(delta.height, 40)
	}

	func testVerticalResizeDragDoesNotChangeFrame() {
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
		let startingFrame = CGRect(x: 100, y: 120, width: 160, height: 160)

		let unchanged = FloatingInteractionPolicy.resizedFrame(
			from: startingFrame,
			dragDelta: CGSize(width: 0, height: 200),
			visibleFrame: visibleFrame
		)

		XCTAssertEqual(unchanged.size.width, startingFrame.width, accuracy: 0.01)
		XCTAssertEqual(unchanged.size.height, startingFrame.height, accuracy: 0.01)
		XCTAssertEqual(
			FloatingInteractionPolicy.resizeDragDelta(from: CGSize(width: 0, height: 200)),
			.zero
		)
	}

	func testHorizontalResizePreservesAspectRatio() {
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
		let startingFrame = CGRect(x: 0, y: 0, width: 200, height: 100)

		let grown = FloatingInteractionPolicy.resizedFrame(
			from: startingFrame,
			dragDelta: CGSize(width: 40, height: 300),
			visibleFrame: visibleFrame
		)

		XCTAssertEqual(grown.width, 240, accuracy: 0.01)
		XCTAssertEqual(grown.height, 120, accuracy: 0.01)
	}

	func testDiagonalResizeUsesHorizontalComponentOnly() {
		let delta = FloatingInteractionPolicy.resizeDragDelta(
			from: CGSize(width: 30, height: 50)
		)
		XCTAssertEqual(delta.width, 30)
		XCTAssertEqual(delta.height, 30)
	}

	func testFloatingInteractionResizeDeltasClampToMinAndMaxSizes() {
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
		let startingFrame = CGRect(x: 100, y: 120, width: 160, height: 160)

		let minimumFrame = FloatingInteractionPolicy.resizedFrame(
			from: startingFrame,
			dragDelta: CGSize(width: -500, height: 0),
			visibleFrame: visibleFrame
		)
		let maximumFrame = FloatingInteractionPolicy.resizedFrame(
			from: startingFrame,
			dragDelta: CGSize(width: 1000, height: 0),
			visibleFrame: visibleFrame
		)

		XCTAssertEqual(minimumFrame.size, FloatingFramePolicy.minimumSize)
		XCTAssertEqual(maximumFrame.size, FloatingFramePolicy.maximumSize)
	}

	func testFrameChangeAfterDragOrResizePersistsUpdatedFrame() throws {
		try withTempHome { _ in
			let initial = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			let updatedFrame = CGRect(x: 240, y: 260, width: 240, height: 200)
			let clampedFrame = FloatingFramePolicy.clamp(updatedFrame, to: visibleFrame)
			try AppStateStore.save(initial)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })

			controller.persistFrameChange(updatedFrame)

			XCTAssertEqual(AppStateStore.load(visibleFrame: visibleFrame).frame, clampedFrame)
			XCTAssertEqual(panel.shownFrames.last, clampedFrame)
		}
	}

	func testDisplayChangeReclampsVisiblePanelAndPersistsSafeFrame() throws {
		try withTempHome { _ in
			var currentVisibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
			let offscreenAfterDisplayChange = CGRect(x: 820, y: 620, width: 220, height: 180)
			try AppStateStore.save(
				FloatingAppState(isFloatingPetVisible: true, frame: offscreenAfterDisplayChange)
			)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(
				panel: panel,
				visibleFrameProvider: { currentVisibleFrame }
			)
			currentVisibleFrame = CGRect(x: 0, y: 0, width: 500, height: 400)

			controller.reclampForVisibleFrameChange()

			let expectedFrame = FloatingFramePolicy.clamp(
				offscreenAfterDisplayChange,
				to: currentVisibleFrame
			)
			XCTAssertEqual(panel.shownFrames.last, expectedFrame)
			XCTAssertEqual(AppStateStore.load(visibleFrame: currentVisibleFrame).frame, expectedFrame)
		}
	}
}

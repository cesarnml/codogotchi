import CoreGraphics
import XCTest

@testable import Codogotchi

@MainActor
final class FloatingPetControllerTests: XCTestCase {
	final class FloatingPetPanelSpy: FloatingPetPanelManaging {
		var shownFrames: [CGRect] = []
		var hideCount = 0
		var appliedStates: [(ActivityState, VisualMode)] = []
		var appliedGateBadges: [GateBadgeContent?] = []
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

		func applyGateBadge(content: GateBadgeContent?) {
			appliedGateBadges.append(content)
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

	func testApplyGateBadgeWhileHiddenReachesPanelChromeSink() throws {
		try withTempHome { _ in
			let initial = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)
			try AppStateStore.save(initial)
			let panel = FloatingPetPanelSpy()
			let controller = FloatingPetController(panel: panel, visibleFrameProvider: { self.visibleFrame })
			let badge = GateBadgeContent(ticketId: "P8.01", gate: "open_pr")

			controller.applyGateBadge(content: badge)

			XCTAssertEqual(panel.appliedGateBadges, [badge])
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

	func testGateBadgeLayoutAnchorsToPetTopLeftAboveFrame() {
		let petFrame = CGRect(x: 120, y: 160, width: 220, height: 180)
		let badgeSize = CGSize(width: 180, height: 24)
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

		let frame = GateBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: badgeSize,
			visibleFrame: visibleFrame
		)

		XCTAssertEqual(frame.minX, petFrame.minX, accuracy: 0.01)
		XCTAssertEqual(frame.minY, petFrame.maxY, accuracy: 0.01)
	}

	func testGateBadgeLayoutClampsWithinVisibleFrame() {
		let petFrame = CGRect(x: 460, y: 390, width: 80, height: 40)
		let badgeSize = CGSize(width: 180, height: 24)
		let visibleFrame = CGRect(x: 0, y: 0, width: 500, height: 400)

		let frame = GateBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: badgeSize,
			visibleFrame: visibleFrame
		)

		XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + GateBadgeLayout.margin - 0.01)
		XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - GateBadgeLayout.margin + 0.01)
		XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - GateBadgeLayout.margin + 0.01)
	}

	func testGateBadgeMetricsScaleUpWithLargerPet() {
		let small = GateBadgeLayout.metrics(
			for: CGRect(x: 0, y: 0, width: 140, height: 140)
		)
		let large = GateBadgeLayout.metrics(
			for: CGRect(x: 0, y: 0, width: 320, height: 320)
		)

		XCTAssertGreaterThan(large.badgeHeight, small.badgeHeight)
		XCTAssertGreaterThan(large.fontSize, small.fontSize)
		XCTAssertGreaterThan(large.horizontalPadding, small.horizontalPadding)
		XCTAssertGreaterThan(large.interBadgeSpacing, small.interBadgeSpacing)
	}

	func testGateBadgeMetricsClampAtMinimumScale() {
		let tiny = GateBadgeLayout.metrics(
			for: CGRect(x: 0, y: 0, width: 40, height: 40)
		)
		let clamped = GateBadgeLayout.metrics(
			for: CGRect(x: 0, y: 0, width: 100, height: 100)
		)

		XCTAssertEqual(tiny, clamped, "very small pets clamp to the minimum badge scale")
	}

	func testAnimationBadgeLayoutAnchorsCenteredBelowPetFeet() {
		let petFrame = CGRect(x: 120, y: 160, width: 220, height: 180)
		let badgeSize = CGSize(width: 90, height: 24)
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

		let frame = AnimationBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: badgeSize,
			visibleFrame: visibleFrame
		)

		// Badge is horizontally centered on the pet frame.
		XCTAssertEqual(frame.midX, petFrame.midX, accuracy: 0.01)
		// Badge TOP edge sits inset above the pet's bottom border; the body hangs
		// below the feet so the sprite appears to stand on it.
		XCTAssertEqual(frame.maxY, petFrame.minY + AnimationBadgeLayout.inset, accuracy: 0.01)
		XCTAssertLessThan(frame.minY, petFrame.minY)
	}

	func testAnimationBadgeHiddenWhileAttentionBubbleActive() {
		// Suppressed when the bubble is up (standby/errored) — 1:1 redundant and
		// collides with the same below-pet slot.
		XCTAssertFalse(AnimationBadgeLayout.isVisible(attentionActive: true))
		XCTAssertTrue(AnimationBadgeLayout.isVisible(attentionActive: false))
	}

	func testIdleEscalationConfigThresholds() {
		let config = IdleEscalationConfig(impatientAfter: 60, frustratedAfter: 120)
		XCTAssertEqual(config.escalation(forElapsed: 0), .none)
		XCTAssertEqual(config.escalation(forElapsed: 59), .none)
		XCTAssertEqual(config.escalation(forElapsed: 60), .impatient)
		XCTAssertEqual(config.escalation(forElapsed: 119), .impatient)
		XCTAssertEqual(config.escalation(forElapsed: 120), .frustrated)
		XCTAssertEqual(config.escalation(forElapsed: 100_000), .frustrated)
	}

	func testIdleEscalationConfigProductionDefaultsAreFiveAndTenMinutes() {
		XCTAssertEqual(IdleEscalationConfig.production.impatientAfter, 5 * 60, accuracy: 0.001)
		XCTAssertEqual(IdleEscalationConfig.production.frustratedAfter, 10 * 60, accuracy: 0.001)
	}

	func testIdleEscalationConfigResolvesEnvOverridesInMilliseconds() {
		let config = IdleEscalationConfig.resolve(environment: [
			"CODOGOTCHI_IDLE_IMPATIENT_MS": "60000",
			"CODOGOTCHI_IDLE_FRUSTRATED_MS": "120000",
		])
		XCTAssertEqual(config.impatientAfter, 60, accuracy: 0.001)
		XCTAssertEqual(config.frustratedAfter, 120, accuracy: 0.001)
	}

	func testIdleEscalationConfigIgnoresInvalidEnvAndKeepsProductionDefaults() {
		let config = IdleEscalationConfig.resolve(environment: [
			"CODOGOTCHI_IDLE_IMPATIENT_MS": "0",
			"CODOGOTCHI_IDLE_FRUSTRATED_MS": "not-a-number",
		])
		XCTAssertEqual(config, .production)
	}

	func testIdleEscalationBadgeLabels() {
		XCTAssertNil(IdleEscalation.none.badgeLabel)
		XCTAssertEqual(IdleEscalation.impatient.badgeLabel, "Impatient")
		XCTAssertEqual(IdleEscalation.frustrated.badgeLabel, "Frustrated")
	}

	func testAnimationBadgeLayoutClampsWithinVisibleFrame() {
		let petFrame = CGRect(x: 460, y: 380, width: 80, height: 40)
		let badgeSize = CGSize(width: 120, height: 24)
		let visibleFrame = CGRect(x: 0, y: 0, width: 500, height: 400)

		let frame = AnimationBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: badgeSize,
			visibleFrame: visibleFrame
		)

		XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + GateBadgeLayout.margin - 0.01)
		XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - GateBadgeLayout.margin + 0.01)
		XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - GateBadgeLayout.margin + 0.01)
	}

	func testAnimationBadgeMetricsScaleWithPetLikeGateBadge() {
		let small = AnimationBadgeLayout.metrics(for: CGRect(x: 0, y: 0, width: 140, height: 140))
		let large = AnimationBadgeLayout.metrics(for: CGRect(x: 0, y: 0, width: 320, height: 320))

		XCTAssertGreaterThan(large.badgeHeight, small.badgeHeight)
		XCTAssertGreaterThan(large.fontSize, small.fontSize)
		// Shares the gate badge's scaling source of truth.
		XCTAssertEqual(
			small,
			GateBadgeLayout.metrics(for: CGRect(x: 0, y: 0, width: 140, height: 140))
		)
	}

	func testActivityStateDisplayLabelsAreUniqueNonEmptyAndConcise() {
		var seen = Set<String>()
		for state in ActivityState.allCases {
			let label = state.displayLabel
			XCTAssertFalse(label.isEmpty, "\(state.rawValue) must have a non-empty label")
			XCTAssertLessThanOrEqual(
				label.count, 14,
				"\(state.rawValue) label '\(label)' should stay concise"
			)
			XCTAssertTrue(
				seen.insert(label).inserted,
				"label '\(label)' is duplicated across states"
			)
		}
	}
}

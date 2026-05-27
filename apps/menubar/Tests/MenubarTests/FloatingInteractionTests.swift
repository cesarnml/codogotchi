import AppKit
import XCTest

@testable import Codogotchi

/// P4.07 — Mouse-reactive reserved Codex rows.
///
/// These tests assert that the reserved Codex rows (`running-right`,
/// `running-left`, `jumping`) are exposed by `CodexPet` independently of
/// `ActivityState`, that the `FloatingPetScene` honours them as a transient
/// interaction overlay above the activity-driven animation, that missing
/// reserved rows degrade gracefully to the current activity frames, and
/// that the menu-bar renderer never consumes the reserved rows because the
/// `ActivityState`-keyed row map does not reference them.
@MainActor
final class FloatingInteractionTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func maliFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	private func maewFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")
			.path
	}

	private func makeScene(
		size: CGSize = CGSize(width: 180, height: 140),
		codexPet: CodexPet? = nil,
		codogotchiPet: CodogotchiPet? = nil,
		interactionFramesProvider: ((FloatingInteraction) -> [CodexPet.Frame])? = nil
	) throws -> FloatingPetScene {
		try FloatingPetScene(
			size: size,
			codexPet: codexPet ?? CodexPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: codogotchiPet ?? CodogotchiPet(petDirectory: maewFixtureDirectory()),
			interactionFramesProvider: interactionFramesProvider
		)
	}

	// MARK: - CodexPet reserved-row exposure

	func testInteractionRowMapRunningRightRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.runningRight]?.rowIndex,
			1,
			"running-right must use Codex row 1 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapRunningLeftRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.runningLeft]?.rowIndex,
			2,
			"running-left must use Codex row 2 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapJumpingRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.jumping]?.rowIndex,
			4,
			"jumping must use Codex row 4 per the animation-state-vocabulary contract"
		)
	}

	func testReservedRowsAbsentFromActivityRowMap() {
		let reservedRowIndices: Set<Int> = [1, 2, 4]
		let activityRowIndices = Set(CodexPet.rowMap.values.map(\.rowIndex))
		XCTAssertTrue(
			activityRowIndices.isDisjoint(with: reservedRowIndices),
			"ActivityState row map must not consume reserved rows \(reservedRowIndices); found \(activityRowIndices)"
		)
	}

	func testInteractionFramesNonEmptyFromFixture() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for interaction in FloatingInteraction.allCases {
			let frames = pet.frames(forInteraction: interaction)
			XCTAssertFalse(
				frames.isEmpty,
				"\(interaction) must yield non-empty frames from the Codex fixture"
			)
		}
	}

	func testFloatingInteractionFramesReuseCachedBackingImages() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for interaction in FloatingInteraction.allCases {
			let first = pet.floatingFrames(forInteraction: interaction)
			let second = pet.floatingFrames(forInteraction: interaction)
			XCTAssertEqual(first.count, second.count)
			for (a, b) in zip(first, second) {
				XCTAssertTrue(
					a.cgImage === b.cgImage,
					"\(interaction) floating frames must come from the load-time cache"
				)
			}
		}
	}

	func testInteractionFramesNotExposedViaActivityState() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for activity in ActivityState.allCases {
			guard let spec = CodexPet.rowMap[activity] else { continue }
			XCTAssertFalse(
				[1, 2, 4].contains(spec.rowIndex),
				"ActivityState.\(activity) must not resolve to a reserved interaction row (got row \(spec.rowIndex))"
			)
			XCTAssertFalse(pet.frames(for: activity).isEmpty)
		}
	}

	// MARK: - Hide floating pet prompt (right-click pill)

	func testHidePromptTitleMatchesCodexLabel() {
		XCTAssertEqual(FloatingPetHidePrompt.title, "Hide pet")
	}

	func testHidePromptPreferredSizeFitsTitle() {
		let size = FloatingPetHidePrompt.preferredSize()
		XCTAssertGreaterThan(size.width, 70)
		XCTAssertGreaterThan(size.height, 24)
	}

	func testHidePromptFrameAnchorsTopLeftAtClick() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let anchor = CGPoint(x: 48, y: 120)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: anchor,
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertEqual(frame.minX, anchor.x, accuracy: 0.5)
		XCTAssertEqual(frame.maxY, anchor.y, accuracy: 0.5)
		XCTAssertTrue(bounds.contains(frame))
	}

	func testHidePromptFrameKeepsTopLeftAnchorWhenExtendingPastRightEdge() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let anchor = CGPoint(x: 170, y: 120)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: anchor,
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertEqual(frame.minX, anchor.x, accuracy: 0.5)
		XCTAssertEqual(frame.maxY, anchor.y, accuracy: 0.5)
		XCTAssertGreaterThan(frame.maxX, bounds.maxX)
	}

	func testHidePromptFrameClampsTopLeftWhenAgainstLeftEdge() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: CGPoint(x: 2, y: 120),
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertGreaterThanOrEqual(frame.minX, 4)
		XCTAssertTrue(bounds.contains(frame))
	}

	func testHidePromptShouldNotPresentDuringActivePointerInteraction() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		XCTAssertFalse(
			FloatingPetHidePrompt.shouldPresent(
				at: CGPoint(x: 100, y: 80),
				in: bounds,
				hasActivePointerInteraction: true
			)
		)
	}

	func testHidePromptShouldPresentInsideBoundsWhenIdle() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		XCTAssertTrue(
			FloatingPetHidePrompt.shouldPresent(
				at: CGPoint(x: 100, y: 80),
				in: bounds,
				hasActivePointerInteraction: false
			)
		)
	}

	// MARK: - FloatingPetScene interaction overlay

	func testSettingInteractionRunningRightSwapsFrames() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		let scene = try makeScene(codexPet: pet)
		scene.update(state: .idle, visualMode: .normal)
		let idleFirstFrame = try XCTUnwrap(pet.frames(for: .idle).first?.image.tiffRepresentation)

		scene.setInteraction(.runningRight)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
		let interactionFirstFrame = try XCTUnwrap(scene.currentFramesForTesting.first?.tiffRepresentation)
		XCTAssertNotEqual(
			interactionFirstFrame, idleFirstFrame,
			"running-right interaction frames must come from a different Codex row than .idle"
		)
		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)
	}

	func testSettingInteractionRunningLeftSwapsFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.runningLeft)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningLeft)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
	}

	func testSettingInteractionJumpingSwapsFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.jumping)

		XCTAssertEqual(scene.currentInteractionForTesting, .jumping)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
	}

	func testMissingInteractionFramesFallBackToActivityFrames() throws {
		let scene = try makeScene(interactionFramesProvider: { _ in [] })
		scene.update(state: .implementing, visualMode: .normal)
		let activityFrameCount = scene.currentFramesForTesting.count
		XCTAssertGreaterThan(activityFrameCount, 0)

		scene.setInteraction(.runningRight)

		XCTAssertNil(
			scene.currentInteractionForTesting,
			"missing reserved-row frames must drop the interaction back to nil so activity frames remain authoritative"
		)
		XCTAssertEqual(
			scene.currentFramesForTesting.count, activityFrameCount,
			"missing reserved rows must fall back to the current activity-state frame loop"
		)
	}

	func testClearingInteractionRestoresActivityFrames() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		let activityFrameCount = scene.currentFramesForTesting.count

		scene.setInteraction(.runningRight)
		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)

		scene.setInteraction(nil)

		XCTAssertNil(scene.currentInteractionForTesting)
		XCTAssertEqual(
			scene.currentFramesForTesting.count, activityFrameCount,
			"ending interaction must restore the ordinary activity-state animation"
		)
	}

	func testActivityStateUpdateWhileInteractingDefersUntilCleared() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.runningRight)
		let interactionFrameCount = scene.currentFramesForTesting.count

		// While an interaction is active, an incoming activity-state change must
		// not interrupt the interaction's frame loop — interaction wins for the
		// duration the user is manipulating the pet.
		scene.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(scene.currentFramesForTesting.count, interactionFrameCount)
		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)

		// On clear, the latest activity-state frames take over.
		scene.setInteraction(nil)
		XCTAssertEqual(scene.currentStateForTesting, .implementing)
		XCTAssertGreaterThan(scene.currentFramesForTesting.count, 0)
	}

	// MARK: - Interaction direction policy

	func testRightwardStepSelectsRunningRight() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningRight)
	}

	func testLeftwardStepSelectsRunningLeft() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: -12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningLeft)
	}

	func testVerticalStepWithNoPreviousRunningHasNoInteraction() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 0, height: 30),
			hitTarget: .dragRegion
		)
		XCTAssertNil(
			interaction,
			"vertical-only step with no prior running interaction stays nil"
		)
	}

	func testVerticalStepHoldsPreviousRunningDirection() {
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 0, height: 8),
				hitTarget: .dragRegion,
				previous: .runningLeft
			),
			.runningLeft
		)
	}

	func testVerticalStepHoldsJumpingDuringTranslate() {
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 0, height: 8),
				hitTarget: .dragRegion,
				previous: .jumping
			),
			.jumping,
			"first drag ticks are often vertical-only; must not clear hover jumping"
		)
	}

	func testDraggedFrameKeepsGrabPointUnderCursor() {
		let grabOffset = CGPoint(x: 40, y: 30)
		let windowSize = CGSize(width: 160, height: 160)
		let mouse = CGPoint(x: 500, y: 400)
		let visible = CGRect(x: 0, y: 0, width: 2000, height: 2000)
		let frame = FloatingInteractionPolicy.draggedFrame(
			mouseLocationInScreen: mouse,
			grabOffsetInScreen: grabOffset,
			windowSize: windowSize,
			visibleFrame: visible
		)
		XCTAssertEqual(frame.origin.x, mouse.x - grabOffset.x, accuracy: 0.001)
		XCTAssertEqual(frame.origin.y, mouse.y - grabOffset.y, accuracy: 0.001)
		XCTAssertEqual(frame.size, windowSize)
	}

	func testStepReversalFlipsRunningWithoutCumulativeUndo() {
		// Cumulative delta from mouseDown would still be leftward after a small
		// rightward reversal; per-event step must flip immediately.
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 4, height: 0),
				hitTarget: .dragRegion,
				previous: .runningLeft
			),
			.runningRight
		)
	}

	func testDiagonalStepWithHorizontalComponentSelectsRunning() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 12, height: 30),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(
			interaction, .runningRight,
			"any non-zero horizontal step selects a running row"
		)
	}

	func testHoverInBoundsSelectsJumping() {
		XCTAssertEqual(
			FloatingInteractionPolicy.hoverInteraction(pointerInBounds: true, isDragging: false),
			.jumping
		)
	}

	func testHoverOutsideBoundsHasNoInteraction() {
		XCTAssertNil(
			FloatingInteractionPolicy.hoverInteraction(pointerInBounds: false, isDragging: false)
		)
	}

	func testHoverSuppressedWhileDragging() {
		XCTAssertNil(
			FloatingInteractionPolicy.hoverInteraction(pointerInBounds: true, isDragging: true)
		)
	}

	func testResizeAffordanceSelectsJumping() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 12, height: 12),
			hitTarget: .resizeAffordance
		)
		XCTAssertEqual(
			interaction, .jumping,
			"resize affordance must pick the jumping reserved row regardless of drag direction"
		)
	}

	func testJumpingToRunningPreservesFrameIndex() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		scene.setInteraction(.jumping)
		for _ in 0 ..< 2 {
			scene.advanceFrameForTesting()
		}
		let indexBefore = scene.currentFrameIndexForTesting
		XCTAssertGreaterThan(indexBefore, 0)

		scene.setInteraction(.runningRight)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)
		XCTAssertEqual(
			scene.currentFrameIndexForTesting, indexBefore % 8,
			"jumping → running must not reset the frame cycle on drag start"
		)
	}

	func testRunningDirectionFlipPreservesFrameIndex() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		scene.setInteraction(.runningRight)
		for _ in 0 ..< 3 {
			scene.advanceFrameForTesting()
		}
		let indexBeforeFlip = scene.currentFrameIndexForTesting
		XCTAssertGreaterThan(indexBeforeFlip, 0)

		scene.setInteraction(.runningLeft)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningLeft)
		XCTAssertEqual(
			scene.currentFrameIndexForTesting, indexBeforeFlip,
			"running-left ↔ running-right must not reset the frame cycle"
		)
	}
}

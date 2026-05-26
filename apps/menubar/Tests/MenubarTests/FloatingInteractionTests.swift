import AppKit
import XCTest

@testable import Codogotchi

/// P4.07 — Mouse-reactive reserved Codex rows.
///
/// These tests assert that the reserved Codex rows (`running-right`,
/// `running-left`, `jumping`) are exposed by `MaliPet` independently of
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
		codexPet: MaliPet? = nil,
		codogotchiPet: CodogotchiPet? = nil,
		interactionFramesProvider: ((FloatingInteraction) -> [MaliPet.Frame])? = nil
	) throws -> FloatingPetScene {
		try FloatingPetScene(
			size: size,
			codexPet: codexPet ?? MaliPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: codogotchiPet ?? CodogotchiPet(petDirectory: maewFixtureDirectory()),
			interactionFramesProvider: interactionFramesProvider
		)
	}

	// MARK: - MaliPet reserved-row exposure

	func testInteractionRowMapRunningRightRowIndex() {
		XCTAssertEqual(
			MaliPet.interactionRowMap[.runningRight]?.rowIndex,
			1,
			"running-right must use Codex row 1 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapRunningLeftRowIndex() {
		XCTAssertEqual(
			MaliPet.interactionRowMap[.runningLeft]?.rowIndex,
			2,
			"running-left must use Codex row 2 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapJumpingRowIndex() {
		XCTAssertEqual(
			MaliPet.interactionRowMap[.jumping]?.rowIndex,
			4,
			"jumping must use Codex row 4 per the animation-state-vocabulary contract"
		)
	}

	func testReservedRowsAbsentFromActivityRowMap() {
		let reservedRowIndices: Set<Int> = [1, 2, 4]
		let activityRowIndices = Set(MaliPet.rowMap.values.map(\.rowIndex))
		XCTAssertTrue(
			activityRowIndices.isDisjoint(with: reservedRowIndices),
			"ActivityState row map must not consume reserved rows \(reservedRowIndices); found \(activityRowIndices)"
		)
	}

	func testInteractionFramesNonEmptyFromFixture() throws {
		let pet = try MaliPet(petDirectory: maliFixtureDirectory())
		for interaction in FloatingInteraction.allCases {
			let frames = pet.frames(forInteraction: interaction)
			XCTAssertFalse(
				frames.isEmpty,
				"\(interaction) must yield non-empty frames from the Codex fixture"
			)
		}
	}

	func testInteractionFramesNotExposedViaActivityState() throws {
		let pet = try MaliPet(petDirectory: maliFixtureDirectory())
		for activity in ActivityState.allCases {
			guard let spec = MaliPet.rowMap[activity] else { continue }
			XCTAssertFalse(
				[1, 2, 4].contains(spec.rowIndex),
				"ActivityState.\(activity) must not resolve to a reserved interaction row (got row \(spec.rowIndex))"
			)
			XCTAssertFalse(pet.frames(for: activity).isEmpty)
		}
	}

	// MARK: - FloatingPetScene interaction overlay

	func testSettingInteractionRunningRightSwapsFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		let idleCount = scene.currentFramesForTesting.count

		scene.setInteraction(.runningRight)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
		XCTAssertNotEqual(
			scene.currentFramesForTesting.count, idleCount,
			"running-right interaction frames should differ from .idle frames in this fixture"
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

	func testRightwardDragSelectsRunningRight() {
		let interaction = FloatingInteractionPolicy.interaction(
			forDragDelta: CGSize(width: 12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningRight)
	}

	func testLeftwardDragSelectsRunningLeft() {
		let interaction = FloatingInteractionPolicy.interaction(
			forDragDelta: CGSize(width: -12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningLeft)
	}

	func testPredominantlyVerticalDragHasNoInteraction() {
		let interaction = FloatingInteractionPolicy.interaction(
			forDragDelta: CGSize(width: 0, height: 30),
			hitTarget: .dragRegion
		)
		XCTAssertNil(
			interaction,
			"vertical-only drag must not pick a horizontal running animation"
		)
	}

	func testResizeAffordanceSelectsJumping() {
		let interaction = FloatingInteractionPolicy.interaction(
			forDragDelta: CGSize(width: 12, height: 12),
			hitTarget: .resizeAffordance
		)
		XCTAssertEqual(
			interaction, .jumping,
			"resize affordance must pick the jumping reserved row regardless of drag direction"
		)
	}
}

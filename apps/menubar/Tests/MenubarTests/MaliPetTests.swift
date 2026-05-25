import AppKit
import XCTest

@testable import Codogotchi

/// Behavior contract for `MaliPet` — the pet asset loader and per-state
/// frame extractor for Phase 02. Fixtures live at
/// `apps/menubar/Fixtures/mali/` so tests run on machines without
/// `~/.codex/pets/mali/` populated.
final class MaliPetTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func fixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	// MARK: - Load

	func testLoaderSucceedsFromFixtureDirectory() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		XCTAssertEqual(pet.id, "mali")
		XCTAssertEqual(pet.displayName, "Mali")
	}

	func testLoaderThrowsWhenDirectoryMissing() {
		let missing = "/tmp/codogotchi-missing-pet-\(UUID().uuidString)"
		XCTAssertThrowsError(try MaliPet(petDirectory: missing)) { error in
			guard let loadError = error as? MaliPetLoadError else {
				XCTFail("expected MaliPetLoadError, got \(error)")
				return
			}
			// Missing-directory must collapse to petJsonNotFound, not the
			// later spritesheetNotFound case — keep the assertion tight so
			// a future throw-site shift is caught here.
			XCTAssertEqual(
				loadError,
				.petJsonNotFound,
				"missing directory must throw petJsonNotFound, got \(loadError)"
			)
		}
	}

	// MARK: - Frame extraction

	func testFramesForImplementingReturnsExpectedShape() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		let frames = pet.frames(for: .implementing)
		XCTAssertFalse(frames.isEmpty, "implementing row must yield frames")

		// Frames are scaled to menubar display height (22 pt) at @2x pixel
		// density and preserve the source cell aspect ratio. The exact pixel
		// width depends on the source sheet's per-cell aspect, so assert the
		// invariants instead of a hardcoded pixel count.
		let first = try XCTUnwrap(frames.first)
		XCTAssertEqual(first.image.size.height, 22, accuracy: 0.001)
		XCTAssertEqual(first.cgImage.height, 44)

		let sheetCG = try XCTUnwrap(pet.spritesheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let sourceCellWidth = sheetCG.width / 8
		let sourceCellHeight = sheetCG.height / 9
		let expectedAspect = Double(sourceCellWidth) / Double(sourceCellHeight)
		let frameAspect = Double(first.cgImage.width) / Double(first.cgImage.height)
		XCTAssertEqual(frameAspect, expectedAspect, accuracy: 0.05, "frame aspect must match source cell aspect")
	}

	func testEveryCodexSheetStateHasNonEmptyFrames() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		// Phase 03 Codex-sheet states — celebrating is intentionally absent (wired in P3.04).
		for state in [ActivityState.idle, .implementing, .runningTests, .waiting, .requestingInput, .errored] {
			XCTAssertFalse(pet.frames(for: state).isEmpty, "\(state) must yield frames")
		}
	}
}

// MARK: - P3.03 Red tests: ActivityState 4→15 + Codex rowMap expansion

final class ActivityStateEnumTests: XCTestCase {
	func testRequestingInputRawValue() {
		XCTAssertEqual(ActivityState(rawValue: "requesting_input"), .requestingInput)
	}

	func testErroredRawValue() {
		XCTAssertEqual(ActivityState(rawValue: "errored"), .errored)
	}

	func testAllCasesCountIs15() {
		XCTAssertEqual(ActivityState.allCases.count, 15)
	}
}

final class MaliPetRowMapExpansionTests: XCTestCase {
	private func fixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	func testRowMapWaitingRowIndex() {
		XCTAssertEqual(MaliPet.rowMap[.waiting]?.rowIndex, 6)
	}

	func testRowMapRequestingInputRowIndex() {
		XCTAssertEqual(MaliPet.rowMap[.requestingInput]?.rowIndex, 3)
	}

	func testRowMapErroredRowIndex() {
		XCTAssertEqual(MaliPet.rowMap[.errored]?.rowIndex, 5)
	}

	func testCelebratingRemovedFromRowMap() {
		XCTAssertNil(MaliPet.rowMap[.celebrating])
	}

	func testWaitingFramesCountAndRow() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		let frames = pet.frames(for: .waiting)
		XCTAssertEqual(frames.count, 8, ".waiting must yield 8 frames from row 6")
	}

	func testIdleFramesRegressionIs8() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		XCTAssertEqual(pet.frames(for: .idle).count, 8, ".idle regression: must still yield 8 frames from row 0")
	}
}

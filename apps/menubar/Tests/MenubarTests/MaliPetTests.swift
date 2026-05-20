import AppKit
import XCTest

@testable import Menubar

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

		let sheet = try XCTUnwrap(pet.spritesheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let expectedFrameWidth = sheet.width / 8
		let expectedFrameHeight = sheet.height / 9

		let first = try XCTUnwrap(frames.first)
		let firstCG = try XCTUnwrap(first.cgImage(forProposedRect: nil, context: nil, hints: nil))
		XCTAssertEqual(firstCG.width, expectedFrameWidth)
		XCTAssertEqual(firstCG.height, expectedFrameHeight)
	}

	func testEveryFloorStateHasNonEmptyFrames() throws {
		let pet = try MaliPet(petDirectory: fixtureDirectory())
		for state in [ActivityState.idle, .implementing, .runningTests, .celebrating] {
			XCTAssertFalse(pet.frames(for: state).isEmpty, "\(state) must yield frames")
		}
	}
}

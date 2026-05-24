import AppKit
import XCTest

@testable import Menubar

/// Behavior contract for `CodogotchiPet` — the codogotchi-sheet loader for
/// the nine SoA-owned states (celebrating, hyped, focused, nervous, ascended,
/// callingForBackup, panicking, reviewing, pushing).
///
/// Fixtures live at `apps/menubar/Fixtures/maew/` so tests run on machines
/// without `~/.codogotchi/pets/maew/` populated.
final class CodogotchiPetTests: XCTestCase {
	// MARK: - Fixture helpers

	private func maewFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/maew")
			.path
	}

	// MARK: - Load

	func testLoaderSucceedsFromFixtureDirectory() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(pet.id, "maew")
		XCTAssertEqual(pet.displayName, "Maew")
	}

	// MARK: - rowMap coverage

	func testRowMapPanicking() {
		XCTAssertEqual(CodogotchiPet.rowMap[.panicking]?.rowIndex, 6)
		XCTAssertEqual(CodogotchiPet.rowMap[.panicking]?.frameCount, 24)
	}

	func testRowMapCelebrating() {
		XCTAssertEqual(CodogotchiPet.rowMap[.celebrating]?.rowIndex, 0)
		XCTAssertEqual(CodogotchiPet.rowMap[.celebrating]?.frameCount, 24)
	}

	func testRowMapHyped() {
		XCTAssertEqual(CodogotchiPet.rowMap[.hyped]?.rowIndex, 1)
		XCTAssertEqual(CodogotchiPet.rowMap[.hyped]?.frameCount, 24)
	}

	func testRowMapFocused() {
		XCTAssertEqual(CodogotchiPet.rowMap[.focused]?.rowIndex, 2)
		XCTAssertEqual(CodogotchiPet.rowMap[.focused]?.frameCount, 24)
	}

	func testRowMapNervous() {
		XCTAssertEqual(CodogotchiPet.rowMap[.nervous]?.rowIndex, 3)
		XCTAssertEqual(CodogotchiPet.rowMap[.nervous]?.frameCount, 24)
	}

	func testRowMapAscended() {
		XCTAssertEqual(CodogotchiPet.rowMap[.ascended]?.rowIndex, 4)
		XCTAssertEqual(CodogotchiPet.rowMap[.ascended]?.frameCount, 24)
	}

	func testRowMapCallingForBackup() {
		XCTAssertEqual(CodogotchiPet.rowMap[.callingForBackup]?.rowIndex, 5)
		XCTAssertEqual(CodogotchiPet.rowMap[.callingForBackup]?.frameCount, 24)
	}

	func testRowMapReviewing() {
		XCTAssertEqual(CodogotchiPet.rowMap[.reviewing]?.rowIndex, 7)
		XCTAssertEqual(CodogotchiPet.rowMap[.reviewing]?.frameCount, 24)
	}

	func testRowMapPushing() {
		XCTAssertEqual(CodogotchiPet.rowMap[.pushing]?.rowIndex, 8)
		XCTAssertEqual(CodogotchiPet.rowMap[.pushing]?.frameCount, 24)
	}

	func testRowMapHasExactlyNineEntries() {
		XCTAssertEqual(CodogotchiPet.rowMap.count, 9)
	}

	// MARK: - Frame extraction

	func testFramesForPanickingReturns24Frames() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let frames = pet.frames(for: .panicking)
		XCTAssertEqual(frames.count, 24, ".panicking must yield 24 frames from row 6")
	}

	func testFramesForPanickingHaveCorrectSourceRect() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let frames = pet.frames(for: .panicking)
		XCTAssertEqual(frames.count, 24)

		// Frames must be scaled to menubar height and match the source cell aspect ratio.
		let first = try XCTUnwrap(frames.first)
		XCTAssertEqual(first.image.size.height, 22, accuracy: 0.001)
		// Codogotchi sheet is 24 columns wide; confirm pixel aspect matches.
		let sheetCG = try XCTUnwrap(pet.spritesheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let sourceCellWidth = sheetCG.width / 24
		let sourceCellHeight = sheetCG.height / 9
		let expectedAspect = Double(sourceCellWidth) / Double(sourceCellHeight)
		let frameAspect = Double(first.cgImage.width) / Double(first.cgImage.height)
		XCTAssertEqual(
			frameAspect, expectedAspect, accuracy: 0.05,
			"frame aspect must match source cell aspect (24-col grid)")
	}

	// MARK: - Soft degrade: missing sheet

	func testMissingSheetSoftDegrades() throws {
		// A directory with pet.json but no spritesheet must not throw on init
		// and must return empty frames for all codogotchi-owned states.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-no-sheet-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"codogotchi-spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		// init must succeed (no throw)
		let pet = try CodogotchiPet(petDirectory: tmp.path)

		// All codogotchi states must return empty frames (not crash)
		for state in CodogotchiPet.rowMap.keys {
			XCTAssertTrue(
				pet.frames(for: state).isEmpty,
				"\(state) must degrade to empty frames when spritesheet is missing"
			)
		}
	}

	// MARK: - Hard fail: incompatible grid

	func testIncompatibleGridThrows() throws {
		// A spritesheet that is not divisible by 24 cols × 9 rows must throw
		// spritesheetIncompatibleGrid — same hard-fail policy as MaliPet.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-bad-sheet-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"codogotchi-spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		// 1×1 RGBA PNG — pixel dimensions are not divisible by 24×9.
		let stubPng = makeSinglePixelPNG()
		try stubPng.write(to: tmp.appendingPathComponent("codogotchi-spritesheet.webp"))

		XCTAssertThrowsError(try CodogotchiPet(petDirectory: tmp.path)) { error in
			guard let loadError = error as? MaliPetLoadError else {
				XCTFail("expected MaliPetLoadError, got \(error)")
				return
			}
			XCTAssertEqual(
				loadError, .spritesheetIncompatibleGrid,
				"incompatible grid must throw spritesheetIncompatibleGrid"
			)
		}
	}

	// MARK: - Helpers

	/// Build a minimal 1×1 RGBA PNG in memory without external tooling.
	private func makeSinglePixelPNG() -> Data {
		let bitmapRep = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 1,
			pixelsHigh: 1,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		)!
		return bitmapRep.representation(using: .png, properties: [:])!
	}
}

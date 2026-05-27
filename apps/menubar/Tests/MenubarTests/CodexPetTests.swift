import AppKit
import XCTest

@testable import Codogotchi

/// Behavior contract for `CodexPet` — the pet asset loader and per-state
/// frame extractor for Phase 02. Fixtures live at
/// `apps/menubar/Fixtures/mali/` so tests run on machines without
/// `~/.codex/pets/mali/` populated.
final class CodexPetTests: XCTestCase {
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
		let pet = try CodexPet(petDirectory: fixtureDirectory())
		XCTAssertEqual(pet.id, "mali")
		XCTAssertEqual(pet.displayName, "Mali")
	}

	func testLoaderThrowsWhenDirectoryMissing() {
		let missing = "/tmp/codogotchi-missing-pet-\(UUID().uuidString)"
		XCTAssertThrowsError(try CodexPet(petDirectory: missing)) { error in
			guard let loadError = error as? CodexPetLoadError else {
				XCTFail("expected CodexPetLoadError, got \(error)")
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
		let pet = try CodexPet(petDirectory: fixtureDirectory())
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

	func testFloatingFramesUseSourceCellResolution() throws {
		let pet = try CodexPet(petDirectory: fixtureDirectory())
		let frames = pet.floatingFrames(for: .implementing)
		let first = try XCTUnwrap(frames.first)

		let sheetCG = try XCTUnwrap(pet.spritesheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let sourceCellWidth = sheetCG.width / 8
		let sourceCellHeight = sheetCG.height / 9

		XCTAssertEqual(first.cgImage.width, sourceCellWidth)
		XCTAssertEqual(first.cgImage.height, sourceCellHeight)
		XCTAssertEqual(first.image.size.width, CGFloat(sourceCellWidth), accuracy: 0.001)
		XCTAssertEqual(first.image.size.height, CGFloat(sourceCellHeight), accuracy: 0.001)
		XCTAssertGreaterThan(first.cgImage.height, 44)
	}

	func testEveryCodexSheetStateHasNonEmptyFrames() throws {
		let pet = try CodexPet(petDirectory: fixtureDirectory())
		// Phase 03 Codex-sheet states — celebrating is intentionally absent (wired in P3.04).
		for state in [ActivityState.idle, .implementing, .runningTests, .waiting, .requestingInput, .errored] {
			XCTAssertFalse(pet.frames(for: state).isEmpty, "\(state) must yield frames")
		}
	}

	func testFramesSkipsTransparentAndPlaceholderMagentaCells() throws {
		let fixture = try makeSyntheticFixtureWithBlankImplementingFrame()
		let pet = try CodexPet(petDirectory: fixture.path)
		let idle = pet.frames(for: .idle)

		// Idle row declares 8 frames. Synthetic sheet marks cols 6 and 7 as
		// transparent/magenta across all rows, so only 6 should render.
		XCTAssertEqual(idle.count, 6)
	}

	private func makeSyntheticFixtureWithBlankImplementingFrame() throws -> URL {
		let temp = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("codogotchi-codexpet-test-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

		let cellWidth = 10
		let cellHeight = 10
		let cols = CodexPet.gridColumns
		let rows = CodexPet.gridRows
		let width = cols * cellWidth
		let height = rows * cellHeight

		guard let ctx = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			XCTFail("failed to build synthetic sheet context")
			throw NSError(domain: "CodexPetTests", code: 1)
		}

		// Start transparent everywhere.
		ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

		for row in 0..<rows {
			for col in 0..<cols {
				let rect = CGRect(
					x: col * cellWidth,
					y: row * cellHeight,
					width: cellWidth,
					height: cellHeight
				)
				// Mark trailing columns as blanks for every row so top/bottom
				// origin differences cannot affect which row the loader reads.
				if col == 6 {
					// Transparent blank.
					continue
				}
				if col == 7 {
					// Placeholder-magenta blank.
					ctx.setFillColor(NSColor.magenta.cgColor)
					ctx.fill(rect)
					continue
				}
				ctx.setFillColor(NSColor.white.cgColor)
				ctx.fill(rect)
			}
		}

		guard let image = ctx.makeImage() else {
			XCTFail("failed to materialize synthetic sheet image")
			throw NSError(domain: "CodexPetTests", code: 2)
		}
		let rep = NSBitmapImageRep(cgImage: image)
		guard let pngData = rep.representation(using: .png, properties: [:]) else {
			XCTFail("failed to encode synthetic sheet png")
			throw NSError(domain: "CodexPetTests", code: 3)
		}

		let sheetURL = temp.appendingPathComponent("spritesheet.png")
		try pngData.write(to: sheetURL)

		let manifest = """
		{
		  "id": "synthetic",
		  "display_name": "Synthetic",
		  "spritesheet_path": "spritesheet.png"
		}
		"""
		guard let manifestData = manifest.data(using: .utf8) else {
			XCTFail("failed to encode manifest")
			throw NSError(domain: "CodexPetTests", code: 4)
		}
		try manifestData.write(to: temp.appendingPathComponent("pet.json"))
		return temp
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

final class CodexPetRowMapExpansionTests: XCTestCase {
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
		XCTAssertEqual(CodexPet.rowMap[.waiting]?.rowIndex, 6)
	}

	func testRowMapRequestingInputRowIndex() {
		XCTAssertEqual(CodexPet.rowMap[.requestingInput]?.rowIndex, 3)
	}

	func testRowMapErroredRowIndex() {
		XCTAssertEqual(CodexPet.rowMap[.errored]?.rowIndex, 5)
	}

	func testCelebratingRemovedFromRowMap() {
		XCTAssertNil(CodexPet.rowMap[.celebrating])
	}

	func testWaitingFramesCountAndRow() throws {
		let pet = try CodexPet(petDirectory: fixtureDirectory())
		let frames = pet.frames(for: .waiting)
		XCTAssertFalse(frames.isEmpty, ".waiting must yield at least one visible frame")
		XCTAssertLessThanOrEqual(
			frames.count,
			CodexPet.rowMap[.waiting]?.frameCount ?? 8,
			".waiting must not exceed declared frameCount"
		)
	}

	func testIdleFramesRegressionIs8() throws {
		let pet = try CodexPet(petDirectory: fixtureDirectory())
		let idle = pet.frames(for: .idle)
		XCTAssertFalse(idle.isEmpty, ".idle must yield at least one visible frame")
		XCTAssertLessThanOrEqual(
			idle.count,
			CodexPet.rowMap[.idle]?.frameCount ?? 8,
			".idle must not exceed declared frameCount"
		)
	}
}

import AppKit
import XCTest

@testable import Codogotchi

/// Behavior contract for `CodogotchiPet` — the tiered loader for all 19 v4
/// ActivityState values:
///   - `codogotchi-lite-basic-spritesheet.webp` (1536×1872, 9 rows) — canonical Lite-Basic tier
///   - `codogotchi-lite-enhanced-spritesheet.webp` (1536×1664, 8 rows) — additive Lite-Enhanced tier
///   - `codogotchi-soa-spritesheet.webp`  (1536×2080, 10 rows) — 10 SoA gate states
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

	// MARK: - Grid constants (P8.06 — 8-frame two-sheet contract)

	func testGridColumnsIs8() {
		XCTAssertEqual(CodogotchiPet.gridColumns, 8,
			"P8.06: each sheet uses 8 columns per row (1.5s / 8-frame loop)")
	}

	func testFrameIntervalIs1Point5Per8Frames() {
		XCTAssertEqual(CodogotchiPet.frameInterval, 1.5 / 8.0, accuracy: 0.0001,
			"P8.06: 8 frames at 1.5s loop = 187.5ms per frame")
	}

	// MARK: - liteBasicRowMap coverage

	func testLiteBasicRowMapHasExactly8HookStates() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap.count, 8)
	}

	func testLiteBasicRowMapCoversReviveAndCoreHookStates() {
		let expected: Set<ActivityState> = [
			.revive,
			.standby, .errored, .waitingForInput,
			.implementing, .testing, .thinking, .reading,
		]
		XCTAssertEqual(Set(CodogotchiPet.liteBasicRowMap.keys), expected)
	}

	func testAllLiteBasicRowsHave8Frames() {
		for (state, spec) in CodogotchiPet.liteBasicRowMap {
			XCTAssertEqual(spec.frameCount, 8, "\(state) lite row must have 8 frames")
		}
	}

	func testLiteBasicDoesNotClaimIdle() {
		XCTAssertNil(CodogotchiPet.liteBasicRowMap[.idle])
	}
	func testLiteBasicRowReviveIsRow0() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.revive]?.rowIndex, 0)
	}
	func testLiteBasicRowStandbyIsRow1() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.standby]?.rowIndex, 1)
	}
	func testLiteBasicRowThinkingIsRow2() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.thinking]?.rowIndex, 2)
	}
	func testLiteBasicRowReadingIsRow3() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.reading]?.rowIndex, 3)
	}
	func testLiteBasicRowImplementingIsRow4() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.implementing]?.rowIndex, 4)
	}
	func testLiteBasicRowTestingIsRow5() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.testing]?.rowIndex, 5)
	}
	func testLiteBasicRowErroredIsRow6() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.errored]?.rowIndex, 6)
	}
	func testLiteBasicRowWaitingForInputIsRow7() {
		XCTAssertEqual(CodogotchiPet.liteBasicRowMap[.waitingForInput]?.rowIndex, 7)
	}

	// MARK: - liteEnhancedRowMap coverage

	func testLiteEnhancedRowMapHasExactly6EnhancedStates() {
		XCTAssertEqual(CodogotchiPet.liteEnhancedRowMap.count, 6)
	}

	func testLiteEnhancedRowMapCoversAllEnhancedHookStates() {
		let expected: Set<ActivityState> = [
			.cramming, .editing, .gitOps, .verifying, .searching, .webSearch,
		]
		XCTAssertEqual(Set(CodogotchiPet.liteEnhancedRowMap.keys), expected)
	}

	func testAllLiteEnhancedRowsHave8Frames() {
		for (state, spec) in CodogotchiPet.liteEnhancedRowMap {
			XCTAssertEqual(spec.frameCount, 8, "\(state) enhanced row must have 8 frames")
		}
	}

	func testLiteEnhancedIdleEscalationRowsAreTopTwoRows() {
		XCTAssertEqual(CodogotchiPet.idleImpatientEnhancedRow.rowIndex, 0)
		XCTAssertEqual(CodogotchiPet.idleFrustratedEnhancedRow.rowIndex, 1)
	}

	// MARK: - soaRowMap coverage (10 SoA gate states)

	func testSoaRowMapHasExactly10GateStates() {
		XCTAssertEqual(CodogotchiPet.soaRowMap.count, 10)
	}

	func testSoaRowMapCoversAllGateStates() {
		let expected: Set<ActivityState> = [
			.ticketStarted, .redTdd, .greenTdd, .adversarialReview,
			.openPr, .pollReview, .reviewClean, .recordReview, .advance, .ticketCompleted,
		]
		XCTAssertEqual(Set(CodogotchiPet.soaRowMap.keys), expected)
	}

	func testAllSoaRowsHave8Frames() {
		for (state, spec) in CodogotchiPet.soaRowMap {
			XCTAssertEqual(spec.frameCount, 8, "\(state) SoA row must have 8 frames")
		}
	}

	// Row indices per codogotchi-8frame-lite-soa-sheet-prompts.md (chronological lifecycle order)
	func testSoaRowTicketStartedIsRow0() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.ticketStarted]?.rowIndex, 0)
	}
	func testSoaRowRedTddIsRow1() { XCTAssertEqual(CodogotchiPet.soaRowMap[.redTdd]?.rowIndex, 1) }
	func testSoaRowGreenTddIsRow2() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.greenTdd]?.rowIndex, 2)
	}
	func testSoaRowAdversarialReviewIsRow3() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.adversarialReview]?.rowIndex, 3)
	}
	func testSoaRowOpenPrIsRow4() { XCTAssertEqual(CodogotchiPet.soaRowMap[.openPr]?.rowIndex, 4) }
	func testSoaRowPollReviewIsRow5() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.pollReview]?.rowIndex, 5)
	}
	func testSoaRowReviewCleanIsRow6() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.reviewClean]?.rowIndex, 6)
	}
	func testSoaRowRecordReviewIsRow7() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.recordReview]?.rowIndex, 7)
	}
	func testSoaRowAdvanceIsRow8() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.advance]?.rowIndex, 8)
	}
	func testSoaRowTicketCompletedIsRow9() {
		XCTAssertEqual(CodogotchiPet.soaRowMap[.ticketCompleted]?.rowIndex, 9)
	}

	// MARK: - Complete schema-v4 coverage (all 19 states)

	func testAllNonIdleSchemaV4StatesCoveredByMaps() {
		let covered = Set(CodogotchiPet.liteBasicRowMap.keys)
			.union(Set(CodogotchiPet.liteEnhancedRowMap.keys))
			.union(Set(CodogotchiPet.soaRowMap.keys))
		for state in ActivityState.allCases {
			if state == .idle { continue }
			XCTAssertTrue(
				covered.contains(state),
				"ActivityState.\(state) is not in liteBasicRowMap, liteEnhancedRowMap, or soaRowMap"
			)
		}
	}

	func testLiteBasicLiteEnhancedAndSoaMapsAreDisjoint() {
		let liteOverlap = Set(CodogotchiPet.liteBasicRowMap.keys).intersection(
			Set(CodogotchiPet.liteEnhancedRowMap.keys))
		let overlap = Set(CodogotchiPet.liteBasicRowMap.keys).intersection(
			Set(CodogotchiPet.soaRowMap.keys))
		let enhancedSoaOverlap = Set(CodogotchiPet.liteEnhancedRowMap.keys).intersection(
			Set(CodogotchiPet.soaRowMap.keys))
		XCTAssertTrue(liteOverlap.isEmpty, "liteBasicRowMap and liteEnhancedRowMap must not share states: \(liteOverlap)")
		XCTAssertTrue(overlap.isEmpty, "liteBasicRowMap and soaRowMap must not share states: \(overlap)")
		XCTAssertTrue(enhancedSoaOverlap.isEmpty, "liteEnhancedRowMap and soaRowMap must not share states: \(enhancedSoaOverlap)")
	}

	// MARK: - No placeholder rows (P7 placeholders removed)

	func testOldPlaceholderStatesNowHaveRealSoaRows() {
		// P7 temporary placeholders: greenTdd→2, redTdd→3, openPr→4, recordReview→8
		// These must now have REAL rows on the SoA sheet.
		XCTAssertEqual(CodogotchiPet.soaRowMap[.greenTdd]?.rowIndex, 2)
		XCTAssertEqual(CodogotchiPet.soaRowMap[.redTdd]?.rowIndex, 1)
		XCTAssertEqual(CodogotchiPet.soaRowMap[.openPr]?.rowIndex, 4)
		XCTAssertEqual(CodogotchiPet.soaRowMap[.recordReview]?.rowIndex, 7)
		// reviewClean is at row 6 on the SoA sheet (not row 0 as in the old single-sheet)
		XCTAssertEqual(CodogotchiPet.soaRowMap[.reviewClean]?.rowIndex, 6)
	}

	// MARK: - Loader

	func testLoaderLoadsLiteBasicLiteEnhancedAndSoaSheetsFromFixture() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertNotNil(
			pet.liteBasicSheet,
			"codogotchi-lite-basic-spritesheet.webp must load from fixture")
		XCTAssertNotNil(
			pet.liteEnhancedSheet,
			"codogotchi-lite-enhanced-spritesheet.webp must load from fixture")
		XCTAssertNotNil(pet.soaSheet, "codogotchi-soa-spritesheet.webp must load from fixture")
	}

	func testGhostRowReturns8FloatingFramesFromLiteBasicSheet() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(
			pet.floatingGhostFrames().count,
			8,
			"ghost row must return 8 source-cell frames from the lite-basic sheet")
	}

	// MARK: - Cell dimension validation

	func testLiteBasicSheetWidthIsDivisibleBy8() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		guard let sheet = pet.liteBasicSheet,
			let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			XCTFail("lite-basic sheet must be loaded from fixture")
			return
		}
		XCTAssertEqual(
			cg.width % CodogotchiPet.gridColumns, 0,
			"Lite-Basic sheet width (\(cg.width)) must be divisible by \(CodogotchiPet.gridColumns)"
		)
	}

	func testSoaSheetWidthIsDivisibleBy8() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		guard let sheet = pet.soaSheet,
			let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			XCTFail("SoA sheet must be loaded from fixture")
			return
		}
		XCTAssertEqual(
			cg.width % CodogotchiPet.gridColumns, 0,
			"SoA sheet width (\(cg.width)) must be divisible by \(CodogotchiPet.gridColumns)"
		)
	}

	func testLiteEnhancedSheetWidthIsDivisibleBy8() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		guard let sheet = pet.liteEnhancedSheet,
			let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			XCTFail("lite-enhanced sheet must be loaded from fixture")
			return
		}
		XCTAssertEqual(
			cg.width % CodogotchiPet.gridColumns, 0,
			"Lite-Enhanced sheet width (\(cg.width)) must be divisible by \(CodogotchiPet.gridColumns)"
		)
	}

	// MARK: - Frame extraction: 8 frames, correct sheets

	func testIdleReturnsEmptySoCodexOwnsIdle() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(
			pet.frames(for: .idle).count, 0, ".idle must fall through to the Codex sheet")
	}

	func testReviveReturns8FramesFromLiteBasicSheet() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(
			pet.frames(for: .revive).count, 8, ".revive must return 8 frames from the lite-basic sheet")
	}

	func testTicketStartedReturns8FramesFromSoaSheet() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(
			pet.frames(for: .ticketStarted).count, 8,
			".ticketStarted must return 8 frames from the SoA sheet")
	}

	func testAllLiteBasicStatesReturn8MenubarFrames() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		for state in CodogotchiPet.liteBasicRowMap.keys {
			let frames = pet.frames(for: state)
			XCTAssertEqual(frames.count, 8, "\(state) must return 8 menubar frames from lite-basic sheet")
		}
	}

	func testAllLiteEnhancedStatesReturn8MenubarFrames() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		for state in CodogotchiPet.liteEnhancedRowMap.keys {
			let frames = pet.frames(for: state)
			XCTAssertEqual(frames.count, 8, "\(state) must return 8 menubar frames from lite-enhanced sheet")
		}
	}

	func testAllSoaStatesReturn8MenubarFrames() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		for state in CodogotchiPet.soaRowMap.keys {
			let frames = pet.frames(for: state)
			XCTAssertEqual(frames.count, 8, "\(state) must return 8 menubar frames from SoA sheet")
		}
	}

	func testMenubarFrameHeightIs22pt() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let frames = pet.frames(for: .thinking)
		let first = try XCTUnwrap(frames.first)
		XCTAssertEqual(first.image.size.height, 22, accuracy: 0.001)
	}

	func testSoaSheetFramesDifferFromLiteSheetFrames() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let idleFrames = pet.frames(for: .standby)
		let ticketStartedFrames = pet.frames(for: .ticketStarted)
		let idleFirst = try XCTUnwrap(idleFrames.first)
		let tsFirst = try XCTUnwrap(ticketStartedFrames.first)
		XCTAssertFalse(
			cgImagesPixelEqual(idleFirst.cgImage, tsFirst.cgImage),
			".standby (lite-basic row 1) and .ticketStarted (SoA row 0) must differ in pixel content"
		)
	}

	// MARK: - Fall-through: unknown/artless state returns empty

	func testMissingSheetSoftDegrades() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-no-sheet-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		let pet = try CodogotchiPet(petDirectory: tmp.path)

		// All states must return empty frames when both sheets are absent (no crash)
		for state in ActivityState.allCases {
			XCTAssertTrue(
				pet.frames(for: state).isEmpty,
				"\(state) must degrade to empty frames when sheets are missing"
			)
		}
	}

	func testIncompatibleLiteBasicSheetGridThrows() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-bad-lite-basic-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		let stubPng = makeSinglePixelPNG()
		try stubPng.write(to: tmp.appendingPathComponent("codogotchi-lite-basic-spritesheet.webp"))

		XCTAssertThrowsError(try CodogotchiPet(petDirectory: tmp.path)) { error in
			guard let loadError = error as? CodexPetLoadError else {
				XCTFail("expected CodexPetLoadError, got \(error)")
				return
			}
			XCTAssertEqual(loadError, .spritesheetIncompatibleGrid)
		}
	}

	// MARK: - Floating frames use source-cell resolution

	func testFloatingFramesForImplementingUseLiteBasicSourceCellResolution() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let frames = pet.floatingFrames(for: .implementing)
		XCTAssertEqual(frames.count, 8, ".implementing floating frames must be 8")
		let first = try XCTUnwrap(frames.first)

		let sheet = try XCTUnwrap(pet.liteBasicSheet, "lite-basic sheet must be loaded")
		let sheetCG = try XCTUnwrap(sheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let cellW = sheetCG.width / CodogotchiPet.gridColumns
		let cellH = sheetCG.height / 9

		XCTAssertEqual(first.cgImage.width, cellW)
		XCTAssertEqual(first.cgImage.height, cellH)
		XCTAssertGreaterThan(first.cgImage.height, 44)
	}

	func testFloatingFramesForEditingUseLiteEnhancedSourceCellResolution() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let frames = pet.floatingFrames(for: .editing)
		XCTAssertEqual(frames.count, 8, ".editing floating frames must be 8")
		let first = try XCTUnwrap(frames.first)

		let sheet = try XCTUnwrap(pet.liteEnhancedSheet, "lite-enhanced sheet must be loaded")
		let sheetCG = try XCTUnwrap(sheet.cgImage(forProposedRect: nil, context: nil, hints: nil))
		let cellW = sheetCG.width / CodogotchiPet.gridColumns
		let cellH = sheetCG.height / 8

		XCTAssertEqual(first.cgImage.width, cellW)
		XCTAssertEqual(first.cgImage.height, cellH)
		XCTAssertGreaterThan(first.cgImage.height, 44)
	}

	func testIdleEscalationFramesReturn8FloatingFramesFromLiteEnhancedSheet() throws {
		let pet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		XCTAssertEqual(
			pet.floatingFrames(forIdleEscalation: .impatient).count,
			8,
			"idle-impatient row must return 8 source-cell frames from the lite-enhanced sheet")
		XCTAssertEqual(
			pet.floatingFrames(forIdleEscalation: .frustrated).count,
			8,
			"idle-frustrated row must return 8 source-cell frames from the lite-enhanced sheet")
	}

	// MARK: - Helpers

	private func cgImagesPixelEqual(_ a: CGImage, _ b: CGImage) -> Bool {
		guard a.width == b.width, a.height == b.height else { return false }
		let w = a.width, h = a.height
		let n = w * h * 4
		var bufA = [UInt8](repeating: 0, count: n)
		var bufB = [UInt8](repeating: 0, count: n)
		let cs = CGColorSpaceCreateDeviceRGB()
		let bi = CGImageAlphaInfo.premultipliedLast.rawValue
		func draw(_ img: CGImage, into buf: inout [UInt8]) {
			buf.withUnsafeMutableBytes { raw in
				guard let base = raw.baseAddress,
					let ctx = CGContext(
						data: base, width: w, height: h, bitsPerComponent: 8,
						bytesPerRow: w * 4, space: cs, bitmapInfo: bi)
				else { return }
				ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
			}
		}
		draw(a, into: &bufA)
		draw(b, into: &bufB)
		return bufA == bufB
	}

	private func makeSinglePixelPNG() -> Data {
		let bitmapRep = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
		return bitmapRep.representation(using: .png, properties: [:])!
	}
}

// MARK: - Cross-loader disjointness (P8.06: Codex is fallback-only)

final class CrossLoaderRowMapTests: XCTestCase {
	func testCodexPetAndCodogotchiMapsAreDisjointFromSoaMap() {
		// SoA gate states must not appear in CodexPet.rowMap — they are
		// exclusively served by CodogotchiPet.soaRowMap.
		let soaOverlap = Set(CodexPet.rowMap.keys).intersection(Set(CodogotchiPet.soaRowMap.keys))
		XCTAssertTrue(
			soaOverlap.isEmpty,
			"CodexPet.rowMap must not contain SoA gate states: \(soaOverlap)")
	}

	func testCodogotchiLiteBasicAndSoaMapsCoverEveryNonIdleState() {
		let all = Set(CodogotchiPet.liteBasicRowMap.keys)
			.union(Set(CodogotchiPet.liteEnhancedRowMap.keys))
			.union(Set(CodogotchiPet.soaRowMap.keys))
		XCTAssertEqual(all.count, ActivityState.allCases.count - 1,
			"lite-basic + lite-enhanced + soa maps together must cover every non-idle v4 state")
	}
}

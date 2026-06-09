import AppKit
import Foundation

/// Tiered asset loader for the v4 closed enum (all 19 ActivityState values).
///
/// Reads `pet.json` + the optional Codogotchi WebP sheets from `petDirectory`:
///   - `codogotchi-lite-basic-spritesheet.webp` (1536×1872, 8 cols × 9 rows)
///     is the canonical Lite tier: revive + 7 core hook states + the dedicated
///     0-HP `ghost` row. States not painted in Lite-Basic alias to the closest
///     core row at the app level.
///   - `codogotchi-lite-spritesheet.webp` is deprecated and ignored by the renderer.
///   - `codogotchi-soa-spritesheet.webp` (1536×2080, 8 cols × 10 rows)
///     covers the 10 SoA gate states.
///
/// Resolution for `frames(for:)`:
///   1. SoA sheet — checked first via `soaRowMap`.
///   2. Lite-Basic sheet — checked second via `liteBasicRowMap`.
///   3. Empty array — callers fall through to the Codex sheet (hook animation
///      fallback; Phase 07 contract preserved).
///
/// Either or both sheets may be absent (soft degrade): `init` succeeds,
/// `frames(for:)` returns an empty array for the missing sheet's states.
/// A sheet that loads but whose pixel dimensions are not divisible by
/// `gridColumns` (width) or the sheet's declared row count (height) throws
/// `CodexPetLoadError.spritesheetIncompatibleGrid`.
final class CodogotchiPet {
	let id: String
	let displayName: String

	/// Loaded lite-basic spritesheet. Nil when absent at load time (soft degrade).
	let liteBasicSheet: NSImage?
	/// Loaded SoA spritesheet. Nil when absent at load time (soft degrade).
	let soaSheet: NSImage?

	// MARK: - Row maps

	/// Lite-Basic row map: idle falls through to the Codex sheet, while revive
	/// and the non-idle activity states are mapped here.
	static let liteBasicRowMap: [ActivityState: RowSpec] = [
		.revive: RowSpec(rowIndex: 0, frameCount: 8),
		.standby: RowSpec(rowIndex: 1, frameCount: 8),
		.thinking: RowSpec(rowIndex: 2, frameCount: 8),
		.reading: RowSpec(rowIndex: 3, frameCount: 8),
		.implementing: RowSpec(rowIndex: 4, frameCount: 8),
		.editing: RowSpec(rowIndex: 4, frameCount: 8),
		.gitOps: RowSpec(rowIndex: 4, frameCount: 8),
		.testing: RowSpec(rowIndex: 5, frameCount: 8),
		.verifying: RowSpec(rowIndex: 5, frameCount: 8),
		.errored: RowSpec(rowIndex: 6, frameCount: 8),
		.waitingForInput: RowSpec(rowIndex: 7, frameCount: 8),
		.searching: RowSpec(rowIndex: 2, frameCount: 8),
		.webSearch: RowSpec(rowIndex: 3, frameCount: 8),
		.cramming: RowSpec(rowIndex: 3, frameCount: 8),
	]

	/// Dedicated 0-HP row on the Lite-Basic sheet.
	static let ghostBasicRow = RowSpec(rowIndex: 8, frameCount: 8)

	/// SoA-sheet row map: 10 gate states.
	/// Row indices match the lifecycle order in codogotchi-8frame-lite-soa-sheet-prompts.md.
	static let soaRowMap: [ActivityState: RowSpec] = [
		.ticketStarted: RowSpec(rowIndex: 0, frameCount: 8),
		.redTdd: RowSpec(rowIndex: 1, frameCount: 8),
		.greenTdd: RowSpec(rowIndex: 2, frameCount: 8),
		.adversarialReview: RowSpec(rowIndex: 3, frameCount: 8),
		.openPr: RowSpec(rowIndex: 4, frameCount: 8),
		.pollReview: RowSpec(rowIndex: 5, frameCount: 8),
		.reviewClean: RowSpec(rowIndex: 6, frameCount: 8),
		.recordReview: RowSpec(rowIndex: 7, frameCount: 8),
		.advance: RowSpec(rowIndex: 8, frameCount: 8),
		.ticketCompleted: RowSpec(rowIndex: 9, frameCount: 8),
	]

	// MARK: - Grid / timing constants

	/// Columns per sheet row: 8 frames per loop.
	static let gridColumns = 8

	/// Loop timing: 1.5 s / 8 frames = 187.5 ms per frame.
	static let frameInterval: TimeInterval = 1.5 / 8.0

	// MARK: - Internal

	private let cgLiteBasicSheet: CGImage?
	private let cgSoaSheet: CGImage?
	private let liteBasicFrameWidth: Int
	private let liteBasicFrameHeight: Int
	private let soaFrameWidth: Int
	private let soaFrameHeight: Int

	convenience init() throws {
		try self.init(petDirectory: CodogotchiPet.defaultPetDirectoryPath())
	}

	/// Load the Lite-Basic and SoA sheets from `petDirectory`.
	///
	/// - Throws `CodexPetLoadError.petJsonNotFound` when `pet.json` is absent.
	/// - Throws `CodexPetLoadError.petJsonMalformed` when `pet.json` cannot be decoded.
	/// - Throws `CodexPetLoadError.spritesheetUnreadable` when a present sheet cannot be decoded.
	/// - Throws `CodexPetLoadError.spritesheetIncompatibleGrid` when a present sheet's pixel
	///   dimensions are not divisible by `gridColumns` (width) × row count (height).
	/// - Missing sheets are soft-degraded: `init` succeeds and `frames(for:)` returns `[]`.
	init(petDirectory: String) throws {
		let dirURL = URL(fileURLWithPath: petDirectory)

		let petJsonURL = dirURL.appendingPathComponent("pet.json")
		let petJsonData: Data
		do {
			petJsonData = try Data(contentsOf: petJsonURL)
		} catch {
			throw CodexPetLoadError.petJsonNotFound
		}

		let manifest: CodogotchiManifest
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			manifest = try decoder.decode(CodogotchiManifest.self, from: petJsonData)
		} catch {
			throw CodexPetLoadError.petJsonMalformed
		}

		self.id = manifest.id
		self.displayName = manifest.displayName

		// Load lite-basic sheet (soft degrade when absent).
		let liteBasicURL = dirURL.appendingPathComponent("codogotchi-lite-basic-spritesheet.webp")
		if FileManager.default.fileExists(atPath: liteBasicURL.path) {
			guard let img = NSImage(contentsOfFile: liteBasicURL.path) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			let liteBasicRows = 9
			guard
				cg.width >= CodogotchiPet.gridColumns,
				cg.height >= liteBasicRows,
				cg.width % CodogotchiPet.gridColumns == 0,
				cg.height % liteBasicRows == 0
			else {
				throw CodexPetLoadError.spritesheetIncompatibleGrid
			}
			self.liteBasicSheet = img
			self.cgLiteBasicSheet = cg
			self.liteBasicFrameWidth = cg.width / CodogotchiPet.gridColumns
			self.liteBasicFrameHeight = cg.height / liteBasicRows
		} else {
			NSLog(
				"CodogotchiPet: lite-basic sheet absent at %@ — lite states will fall through to Codex",
				liteBasicURL.path)
			self.liteBasicSheet = nil
			self.cgLiteBasicSheet = nil
			self.liteBasicFrameWidth = 0
			self.liteBasicFrameHeight = 0
		}

		// Load SoA sheet (soft degrade when absent).
		let soaURL = dirURL.appendingPathComponent("codogotchi-soa-spritesheet.webp")
		if FileManager.default.fileExists(atPath: soaURL.path) {
			guard let img = NSImage(contentsOfFile: soaURL.path) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			let soaRows = 10
			guard
				cg.width >= CodogotchiPet.gridColumns,
				cg.height >= soaRows,
				cg.width % CodogotchiPet.gridColumns == 0,
				cg.height % soaRows == 0
			else {
				throw CodexPetLoadError.spritesheetIncompatibleGrid
			}
			self.soaSheet = img
			self.cgSoaSheet = cg
			self.soaFrameWidth = cg.width / CodogotchiPet.gridColumns
			self.soaFrameHeight = cg.height / soaRows
		} else {
			NSLog(
				"CodogotchiPet: SoA sheet absent at %@ — gate states will fall through to Codex",
				soaURL.path)
			self.soaSheet = nil
			self.cgSoaSheet = nil
			self.soaFrameWidth = 0
			self.soaFrameHeight = 0
		}
	}

	var hasLiteBasicSheet: Bool { cgLiteBasicSheet != nil }

	// MARK: - Frame access

	/// Return menubar-scaled animation frames for `state`.
	///
	/// Dispatch: SoA sheet → lite-basic sheet → empty (caller falls through to Codex).
	func frames(for state: ActivityState) -> [CodexPet.Frame] {
		if let spec = CodogotchiPet.soaRowMap[state], let cg = cgSoaSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: soaFrameWidth, fh: soaFrameHeight, output: .menubar)
		}
		if let spec = CodogotchiPet.liteBasicRowMap[state], let cg = cgLiteBasicSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: liteBasicFrameWidth, fh: liteBasicFrameHeight,
				output: .menubar)
		}
		return []
	}

	/// Return source-cell-resolution frames for the SpriteKit floating pet.
	///
	/// Same dispatch order as `frames(for:)`.
	func floatingFrames(for state: ActivityState) -> [CodexPet.Frame] {
		if let spec = CodogotchiPet.soaRowMap[state], let cg = cgSoaSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: soaFrameWidth, fh: soaFrameHeight,
				output: .sourceCell)
		}
		if let spec = CodogotchiPet.liteBasicRowMap[state], let cg = cgLiteBasicSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: liteBasicFrameWidth, fh: liteBasicFrameHeight,
				output: .sourceCell)
		}
		return []
	}

	/// Lite-Basic intentionally has no idle-escalation rows. Idle falls through
	/// to the Codex sheet for this tier.
	func floatingFrames(forIdleEscalation level: IdleEscalation) -> [CodexPet.Frame] {
		_ = level
		return []
	}

	/// Source-cell frames for the dedicated 0-HP `ghost` row when the Lite-Basic
	/// sheet is installed. Returns `[]` when the sheet is absent so callers can
	/// fall back to Codex idle.
	func floatingGhostFrames() -> [CodexPet.Frame] {
		guard let cg = cgLiteBasicSheet else { return [] }
		return sliceFrames(
			spec: CodogotchiPet.ghostBasicRow,
			cgSheet: cg,
			fw: liteBasicFrameWidth,
			fh: liteBasicFrameHeight,
			output: .sourceCell
		)
	}

	// MARK: - Private slicing

	private enum FrameOutput {
		case menubar
		case sourceCell
	}

	private func sliceFrames(
		spec: RowSpec,
		cgSheet: CGImage,
		fw frameWidth: Int,
		fh frameHeight: Int,
		output: FrameOutput
	) -> [CodexPet.Frame] {
		var out: [CodexPet.Frame] = []
		out.reserveCapacity(spec.frameCount)

		let displaySize: NSSize
		let pxW: Int
		let pxH: Int
		let interpolation: CGInterpolationQuality

		switch output {
		case .menubar:
			let targetHeight: CGFloat = 22
			let scale = targetHeight / CGFloat(frameHeight)
			displaySize = NSSize(width: CGFloat(frameWidth) * scale, height: targetHeight)
			let pixelScale: CGFloat = 2
			pxW = Int((displaySize.width * pixelScale).rounded())
			pxH = Int((displaySize.height * pixelScale).rounded())
			interpolation = .high
		case .sourceCell:
			displaySize = NSSize(width: CGFloat(frameWidth), height: CGFloat(frameHeight))
			pxW = frameWidth
			pxH = frameHeight
			interpolation = .none
		}

		for col in 0..<spec.frameCount {
			let rect = CGRect(
				x: col * frameWidth,
				y: spec.rowIndex * frameHeight,
				width: frameWidth,
				height: frameHeight
			)
			guard let slice = cgSheet.cropping(to: rect) else {
				assertionFailure(
					"CodogotchiPet.sliceFrames — cropping returned nil for rect \(rect)"
				)
				continue
			}
			let owned: CGImage
			if let ctx = CGContext(
				data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
				bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) {
				ctx.interpolationQuality = interpolation
				ctx.draw(slice, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
				owned = ctx.makeImage() ?? slice
			} else {
				owned = slice
			}
			out.append(CodexPet.Frame(image: NSImage(cgImage: owned, size: displaySize), cgImage: owned))
		}

		return out
	}

	// MARK: - Default path

	static func defaultPetDirectoryPath() -> String {
		if let cStr = getenv("CODOGOTCHI_HOME"), let base = String(validatingUTF8: cStr) {
			return URL(fileURLWithPath: base)
				.appendingPathComponent("pets")
				.appendingPathComponent(PetConfig.resolvedPetName())
				.path
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("pets")
			.appendingPathComponent(PetConfig.resolvedPetName())
			.path
	}
}

/// Decoded `pet.json` for the codogotchi pet format. Only `id` and
/// `displayName` are read; spritesheet paths are fixed filename conventions.
private struct CodogotchiManifest: Decodable {
	let id: String
	let displayName: String
}

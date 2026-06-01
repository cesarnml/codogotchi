import AppKit
import Foundation

/// Two-sheet asset loader for the v4 closed enum (all 19 ActivityState values).
///
/// Reads `pet.json` + two WebP sheets from `petDirectory`:
///   - `codogotchi-lite-spritesheet.webp` (1536×2288, 8 cols × 11 rows)
///     covers the 9 hook/lite states; rows 1–2 are idle-escalation rows
///     selected by the renderer based on elapsed-idle thresholds.
///   - `codogotchi-soa-spritesheet.webp` (1536×2080, 8 cols × 10 rows)
///     covers the 10 SoA gate states.
///
/// Resolution for `frames(for:)`:
///   1. SoA sheet — checked first via `soaRowMap`.
///   2. Lite sheet — checked second via `liteRowMap`.
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

	/// Loaded lite spritesheet. Nil when absent at load time (soft degrade).
	let liteSheet: NSImage?
	/// Loaded SoA spritesheet. Nil when absent at load time (soft degrade).
	let soaSheet: NSImage?

	// MARK: - Row maps

	/// Lite-sheet row map: 9 hook/lite states.
	/// Row indices match the generation order in codogotchi-8frame-lite-soa-sheet-prompts.md.
	static let liteRowMap: [ActivityState: RowSpec] = [
		.idle: RowSpec(rowIndex: 0, frameCount: 8),
		// rows 1–2 are idle-impatient / idle-frustrated (renderer-selected escalation)
		.standby: RowSpec(rowIndex: 3, frameCount: 8),
		.thinking: RowSpec(rowIndex: 4, frameCount: 8),
		.reading: RowSpec(rowIndex: 5, frameCount: 8),
		.implementing: RowSpec(rowIndex: 6, frameCount: 8),
		.testing: RowSpec(rowIndex: 7, frameCount: 8),
		.cramming: RowSpec(rowIndex: 8, frameCount: 8),
		.errored: RowSpec(rowIndex: 9, frameCount: 8),
		.waitingForInput: RowSpec(rowIndex: 10, frameCount: 8),
	]

	/// Idle-escalation rows on the lite sheet (not in ActivityState enum).
	/// Used by the renderer to select time-based idle variants.
	static let idleImpatientLiteRow = RowSpec(rowIndex: 1, frameCount: 8)
	static let idleFrustratedLiteRow = RowSpec(rowIndex: 2, frameCount: 8)

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

	private let cgLiteSheet: CGImage?
	private let cgSoaSheet: CGImage?
	private let liteFrameWidth: Int
	private let liteFrameHeight: Int
	private let soaFrameWidth: Int
	private let soaFrameHeight: Int

	convenience init() throws {
		try self.init(petDirectory: CodogotchiPet.defaultPetDirectoryPath())
	}

	/// Load both sheets from `petDirectory`.
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

		// Load lite sheet (soft degrade when absent).
		let liteURL = dirURL.appendingPathComponent("codogotchi-lite-spritesheet.webp")
		if FileManager.default.fileExists(atPath: liteURL.path) {
			guard let img = NSImage(contentsOfFile: liteURL.path) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
				throw CodexPetLoadError.spritesheetUnreadable
			}
			let liteRows = 11
			guard
				cg.width >= CodogotchiPet.gridColumns,
				cg.height >= liteRows,
				cg.width % CodogotchiPet.gridColumns == 0,
				cg.height % liteRows == 0
			else {
				throw CodexPetLoadError.spritesheetIncompatibleGrid
			}
			self.liteSheet = img
			self.cgLiteSheet = cg
			self.liteFrameWidth = cg.width / CodogotchiPet.gridColumns
			self.liteFrameHeight = cg.height / liteRows
		} else {
			NSLog(
				"CodogotchiPet: lite sheet absent at %@ — hook states will fall through to Codex",
				liteURL.path)
			self.liteSheet = nil
			self.cgLiteSheet = nil
			self.liteFrameWidth = 0
			self.liteFrameHeight = 0
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

	/// Whether `codogotchi-lite-spritesheet.webp` loaded — required for idle escalation rows.
	var hasLiteSheet: Bool { cgLiteSheet != nil }

	// MARK: - Frame access

	/// Return menubar-scaled animation frames for `state`.
	///
	/// Dispatch: SoA sheet → lite sheet → empty (caller falls through to Codex).
	func frames(for state: ActivityState) -> [CodexPet.Frame] {
		if let spec = CodogotchiPet.soaRowMap[state], let cg = cgSoaSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: soaFrameWidth, fh: soaFrameHeight, output: .menubar)
		}
		if let spec = CodogotchiPet.liteRowMap[state], let cg = cgLiteSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: liteFrameWidth, fh: liteFrameHeight, output: .menubar)
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
		if let spec = CodogotchiPet.liteRowMap[state], let cg = cgLiteSheet {
			return sliceFrames(
				spec: spec, cgSheet: cg, fw: liteFrameWidth, fh: liteFrameHeight,
				output: .sourceCell)
		}
		return []
	}

	/// Source-cell frames for a time-based idle-escalation row (lite sheet only).
	/// Returns `[]` for `.none` or when the lite sheet is absent, so the renderer
	/// falls back to the plain idle animation (e.g. the Codex-only pet).
	func floatingFrames(forIdleEscalation level: IdleEscalation) -> [CodexPet.Frame] {
		let spec: RowSpec
		switch level {
		case .none: return []
		case .impatient: spec = CodogotchiPet.idleImpatientLiteRow
		case .frustrated: spec = CodogotchiPet.idleFrustratedLiteRow
		}
		guard let cg = cgLiteSheet else { return [] }
		return sliceFrames(
			spec: spec, cgSheet: cg, fw: liteFrameWidth, fh: liteFrameHeight,
			output: .sourceCell)
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

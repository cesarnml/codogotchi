import AppKit
import Foundation

/// Pet asset loader for the codogotchi-spritesheet states.
///
/// Reads `pet.json` + `codogotchi-spritesheet.webp` from `petDirectory`
/// (default `~/.codogotchi/pets/maew/`) and exposes a hardcoded
/// `ActivityState → RowSpec` table for the nine SoA-owned states on a
/// **24 columns × 9 rows** grid per the Phase 03 contract.
///
/// Missing spritesheet is a soft failure: `init` succeeds and `frames(for:)`
/// returns an empty array for all states, letting the renderer fall back to
/// `.idle`. Malformed spritesheet (grid not divisible by 24×9) is a hard
/// failure that throws `CodexPetLoadError.spritesheetIncompatibleGrid`.
final class CodogotchiPet {
	let id: String
	let displayName: String
	/// The loaded spritesheet. Nil when the spritesheet was absent at load time
	/// (soft degrade). Non-nil when the sheet loaded successfully.
	let spritesheet: NSImage?

	/// Codogotchi-sheet row map. All nine SoA-owned states map to 24-frame rows.
	///
	/// Row indices per the Phase 03 contract's Codogotchi Sheet table:
	/// - `.celebrating`     → row 0 (24 frames)
	/// - `.hyped`           → row 1 (24 frames)
	/// - `.focused`         → row 2 (24 frames)
	/// - `.nervous`         → row 3 (24 frames)
	/// - `.ascended`        → row 4 (24 frames)
	/// - `.callingForBackup`→ row 5 (24 frames)
	/// - `.panicking`       → row 6 (24 frames)
	/// - `.reviewing`       → row 7 (24 frames)
	/// - `.pushing`         → row 8 (24 frames)
	static let rowMap: [ActivityState: RowSpec] = [
		.celebrating: RowSpec(rowIndex: 0, frameCount: 24),
		.hyped: RowSpec(rowIndex: 1, frameCount: 24),
		.focused: RowSpec(rowIndex: 2, frameCount: 24),
		.nervous: RowSpec(rowIndex: 3, frameCount: 24),
		.ascended: RowSpec(rowIndex: 4, frameCount: 24),
		.callingForBackup: RowSpec(rowIndex: 5, frameCount: 24),
		.panicking: RowSpec(rowIndex: 6, frameCount: 24),
		.reviewing: RowSpec(rowIndex: 7, frameCount: 24),
		.pushing: RowSpec(rowIndex: 8, frameCount: 24),
	]

	/// Codogotchi-sheet grid dimensions: 24 columns × 9 rows.
	static let gridColumns = 24
	static let gridRows = 9

	/// Per-frame display interval for codogotchi-sheet animations (~167 ms/frame).
	/// Codex-sheet frames use `CodexPet.frameInterval` (~188 ms/frame for 8-frame rows).
	static let frameInterval: TimeInterval = 167.0 / 1000.0

	private let cgSheet: CGImage?
	private let frameWidth: Int
	private let frameHeight: Int

	convenience init() throws {
		try self.init(petDirectory: CodogotchiPet.defaultPetDirectoryPath())
	}

	/// Load a codogotchi pet from `petDirectory`.
	///
	/// Reads `pet.json` for `id` and `displayName`; then attempts to load
	/// `codogotchi-spritesheet.webp`. Missing spritesheet → soft degrade (no
	/// throw). Malformed grid → throws `CodexPetLoadError.spritesheetIncompatibleGrid`.
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

		let sheetURL = dirURL.appendingPathComponent(manifest.spritesheetPath)
		guard FileManager.default.fileExists(atPath: sheetURL.path) else {
			// Soft degrade: spritesheet absent, frames will return empty arrays.
			// Log once so operators can diagnose silent idle rendering.
			NSLog(
				"CodogotchiPet: spritesheet absent at %@ — codogotchi-owned states will render as idle",
				sheetURL.path
			)
			self.spritesheet = nil
			self.cgSheet = nil
			self.frameWidth = 0
			self.frameHeight = 0
			return
		}

		guard let image = NSImage(contentsOfFile: sheetURL.path) else {
			throw CodexPetLoadError.spritesheetUnreadable
		}

		guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
			throw CodexPetLoadError.spritesheetUnreadable
		}

		guard
			cg.width >= CodogotchiPet.gridColumns,
			cg.height >= CodogotchiPet.gridRows,
			cg.width % CodogotchiPet.gridColumns == 0,
			cg.height % CodogotchiPet.gridRows == 0
		else {
			throw CodexPetLoadError.spritesheetIncompatibleGrid
		}

		self.spritesheet = image
		self.cgSheet = cg
		self.frameWidth = cg.width / CodogotchiPet.gridColumns
		self.frameHeight = cg.height / CodogotchiPet.gridRows
	}

	/// Return the per-state animation frames sliced from the codogotchi spritesheet.
	///
	/// Returns an empty array when:
	/// - The state is not in `rowMap` (Codex-sheet-owned states).
	/// - The spritesheet was absent at load time (soft degrade).
	func frames(for state: ActivityState) -> [CodexPet.Frame] {
		guard let cgSheet = cgSheet, let spec = CodogotchiPet.rowMap[state] else { return [] }
		return frames(forRow: spec, cgSheet: cgSheet, state: state, output: .menubar)
	}

	/// Return codogotchi-sheet frames at native source-cell resolution for the
	/// SpriteKit floating pet.
	func floatingFrames(for state: ActivityState) -> [CodexPet.Frame] {
		guard let cgSheet = cgSheet, let spec = CodogotchiPet.rowMap[state] else { return [] }
		return frames(forRow: spec, cgSheet: cgSheet, state: state, output: .sourceCell)
	}

	private func frames(
		forRow spec: RowSpec,
		cgSheet: CGImage,
		state: ActivityState,
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
			displaySize = NSSize(
				width: CGFloat(frameWidth) * scale,
				height: targetHeight
			)
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
					"CodogotchiPet.frames(for: \(state)) — cropping returned nil for rect \(rect)"
				)
				continue
			}
			let owned: CGImage
			if let ctx = CGContext(
				data: nil,
				width: pxW,
				height: pxH,
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			) {
				ctx.interpolationQuality = interpolation
				ctx.draw(slice, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
				owned = ctx.makeImage() ?? slice
			} else {
				owned = slice
			}
			let image = NSImage(cgImage: owned, size: displaySize)
			out.append(CodexPet.Frame(image: image, cgImage: owned))
		}

		return out
	}

	private enum FrameOutput {
		case menubar
		case sourceCell

		var logLabel: String {
			switch self {
			case .menubar:
				return "menubar"
			case .sourceCell:
				return "source-cell"
			}
		}
	}

	// MARK: - Helpers

	static func defaultPetDirectoryPath() -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser
		return home
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("pets")
			.appendingPathComponent(PetConfig.resolvedPetName())
			.path
	}
}

/// Decoded `pet.json` for the codogotchi pet format.
private struct CodogotchiManifest: Decodable {
	let id: String
	let displayName: String
	let spritesheetPath: String
}

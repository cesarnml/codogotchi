import AppKit
import Foundation

/// Failure modes for `MaliPet(petDirectory:)`. Surfaced as named cases so the
/// caller (P2.05 renderer, P2.06 demo mode) can map them to user-visible
/// failure visuals without re-parsing an error string.
enum MaliPetLoadError: Error, Equatable {
	case petJsonNotFound
	case petJsonMalformed
	case spritesheetNotFound
	case spritesheetUnreadable
	case spritesheetIncompatibleGrid
}

/// Decoded `pet.json`. Only the three fields Phase 02 reads are declared;
/// extra keys (description, etc.) are tolerated and ignored.
private struct PetManifest: Decodable {
	let id: String
	let displayName: String
	let spritesheetPath: String
}

/// One sliceable row in the spritesheet grid.
///
/// `rowIndex` is the 0-indexed row from the top of `spritesheet-grid-8x9.png`
/// (the annotated grid PNG sitting alongside the spritesheet in
/// `~/.codex/pets/mali/`). `frameCount` is how many leading columns in that
/// row carry usable frames before the row terminates in unused magenta cells.
///
/// Both numbers were obtained by visual inspection of the grid PNG, owner-
/// confirmed on 2026-05-21. Wrong values will be visually obvious in the
/// P2.05 menubar renderer; correct them there if they slip past this loader.
struct RowSpec: Equatable {
	let rowIndex: Int
	let frameCount: Int
}

/// Pet asset loader for the Codex-spritesheet states.
///
/// Reads `pet.json` + the WebP spritesheet from `petDirectory` (default
/// `~/.codex/pets/mali/`) and exposes a hardcoded `ActivityState → RowSpec`
/// table. Six Codex-sheet states are mapped to their visually-inspected rows
/// in `spritesheet-grid-8x9.png` (8 cols × 9 rows); the remaining nine
/// codogotchi-owned states are wired in P3.04.
///
/// Hardcoded map is deliberate over `pet.json` extension or a sibling
/// rows file because the format extension belongs to Phase 06's multi-pet
/// catalog work — see the ticket Rationale section.
final class MaliPet {
	let id: String
	let displayName: String
	let spritesheet: NSImage

	/// Codex-sheet row map. Only Codex-spritesheet-served states are listed
	/// here; codogotchi-owned states (celebrating, hyped, focused, nervous,
	/// ascended, callingForBackup, panicking, reviewing, pushing) are wired in
	/// P3.04. States absent from this map fall back to `.idle` rendering via
	/// `frames(for:)` returning an empty array and the renderer's idle fallback.
	///
	/// Row indices owner-confirmed against `spritesheet-grid-8x9.png` cells:
	///
	/// - `.idle`           → row 0 (standing/idle chibi poses)
	/// - `.implementing`   → row 7 (seated chibi with laptop + glasses)
	/// - `.runningTests`   → row 8 (bottom-row pose variants)
	/// - `.waiting`        → row 6 (Codex-sheet waiting poses — P3.03)
	/// - `.requestingInput`→ row 3 (Codex-sheet requesting-input poses — P3.03)
	/// - `.errored`        → row 5 (Codex-sheet errored poses — P3.03)
	///
	/// `.celebrating` was row 4 in Phase 02 (Codex `jumping` row). It is
	/// removed here — the codogotchi sheet owns it from P3.04 onward. Between
	/// P3.03 and P3.04, `.celebrating` renders as `.idle` (honest intermediate).
	static let rowMap: [ActivityState: RowSpec] = [
		.idle: RowSpec(rowIndex: 0, frameCount: 8),
		.implementing: RowSpec(rowIndex: 7, frameCount: 6),
		.runningTests: RowSpec(rowIndex: 8, frameCount: 4),
		.waiting: RowSpec(rowIndex: 6, frameCount: 8),
		.requestingInput: RowSpec(rowIndex: 3, frameCount: 8),
		.errored: RowSpec(rowIndex: 5, frameCount: 8),
	]

	/// Spritesheet grid dimensions. The grid PNG asserts 8 columns × 9 rows.
	static let gridColumns = 8
	static let gridRows = 9

	/// Per-frame display interval for Codex-sheet animations (~125 ms/frame for
	/// 8-frame rows → 1 s cycle). Codogotchi-sheet frames use their own interval.
	static let frameInterval: TimeInterval = 1.0 / Double(gridColumns)

	private let cgSheet: CGImage
	private let frameWidth: Int
	private let frameHeight: Int

	convenience init() throws {
		try self.init(petDirectory: MaliPet.defaultPetDirectoryPath())
	}

	/// Load a pet from `petDirectory`. Reads `pet.json` and the spritesheet
	/// path it references (relative paths resolve against `petDirectory`).
	init(petDirectory: String) throws {
		let dirURL = URL(fileURLWithPath: petDirectory)

		let petJsonURL = dirURL.appendingPathComponent("pet.json")
		let petJsonData: Data
		do {
			petJsonData = try Data(contentsOf: petJsonURL)
		} catch {
			throw MaliPetLoadError.petJsonNotFound
		}

		let manifest: PetManifest
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			manifest = try decoder.decode(PetManifest.self, from: petJsonData)
		} catch {
			throw MaliPetLoadError.petJsonMalformed
		}

		let sheetURL = dirURL.appendingPathComponent(manifest.spritesheetPath)
		guard FileManager.default.fileExists(atPath: sheetURL.path) else {
			throw MaliPetLoadError.spritesheetNotFound
		}

		// `NSImage(contentsOfFile:)` decodes WebP via ImageIO on macOS 13+. If
		// a future repo target loses ImageIO WebP support, fall back to
		// `CGImageSourceCreateWithURL` and convert the fixture to PNG; see
		// the ticket Rationale section.
		guard let image = NSImage(contentsOfFile: sheetURL.path) else {
			throw MaliPetLoadError.spritesheetUnreadable
		}

		guard
			let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			throw MaliPetLoadError.spritesheetUnreadable
		}

		// 8 columns × 9 rows is a load-time invariant. The runtime row map
		// only references rows 0..8; an incompatible grid would silently
		// slice gibberish at runtime, so refuse early. We require the
		// pixel dimensions to be evenly divisible by the grid shape so
		// frame rects computed from integer division of width/8 and
		// height/9 cover the full sheet without trailing slack — a
		// 12×9 spritesheet would otherwise pass a width-only minimum
		// check and silently slice misaligned frames.
		guard
			cg.width >= MaliPet.gridColumns,
			cg.height >= MaliPet.gridRows,
			cg.width % MaliPet.gridColumns == 0,
			cg.height % MaliPet.gridRows == 0
		else {
			throw MaliPetLoadError.spritesheetIncompatibleGrid
		}

		self.id = manifest.id
		self.displayName = manifest.displayName
		self.spritesheet = image
		self.cgSheet = cg
		self.frameWidth = cg.width / MaliPet.gridColumns
		self.frameHeight = cg.height / MaliPet.gridRows
	}

	/// Return the per-state animation frames sliced from the spritesheet.
	///
	/// Returns an empty array only when the row map is missing an entry for
	/// `state` — the four floor states above are guaranteed to map. Each
	/// frame is an `NSImage` wrapping a `CGImage.cropping(to:)` view over
	/// the source sheet so the bytes are not re-decoded per frame.
	///
	/// Coordinates: `CGImage` is top-left origin. Frame `(row, col)` lives at
	/// rectangle `(col * frameWidth, row * frameHeight, frameWidth, frameHeight)`.
	/// The grid PNG's row indexing matches this orientation. (Cocoa's
	/// flipped-coordinate-system gotcha applies to `NSGraphicsContext`
	/// drawing, not to `CGImage.cropping(to:)` — see the Swift notes file.)
	func frames(for state: ActivityState) -> [Frame] {
		guard let spec = MaliPet.rowMap[state] else { return [] }

		var out: [Frame] = []
		out.reserveCapacity(spec.frameCount)
		// Scale frames to the standard macOS menubar height (22 pt) so the
		// raw spritesheet pixel dimensions don't overflow the status bar.
		let targetHeight: CGFloat = 22
		let scale = targetHeight / CGFloat(frameHeight)
		let displaySize = NSSize(width: CGFloat(frameWidth) * scale, height: targetHeight)

		for col in 0..<spec.frameCount {
			let rect = CGRect(
				x: col * frameWidth,
				y: spec.rowIndex * frameHeight,
				width: frameWidth,
				height: frameHeight,
			)
			// `cropping(to:)` returning nil would mean `rect` slipped
			// outside `cgSheet` — but the load-time grid-shape gate
			// asserts `cgSheet` is exactly `gridColumns * frameWidth`
			// wide and `gridRows * frameHeight` tall, and `rowMap`
			// only references valid grid cells. A nil here is a real
			// bug (corrupt sheet backing, mutated rowMap, or a future
			// gridColumns/gridRows mismatch). Trip assertionFailure in
			// debug builds; degrade gracefully in release rather than
			// crash the menubar.
			guard let slice = cgSheet.cropping(to: rect) else {
				assertionFailure(
					"MaliPet.frames(for: \(state)) — cropping returned nil for rect \(rect); rowMap or grid invariant broken"
				)
				continue
			}
			// Materialize the cropped slice into a self-contained CGImage so
			// the resulting NSImage owns its pixel data outright. Cropping
			// returns a view that shares cgSheet's buffer; AppKit's status
			// item rendering then collapses successive frames to whichever
			// one it cached first (a known symptom: pet freezes on one
			// frame instead of animating). Drawing at the display size in
			// @2x pixels also yields a sharp Retina presentation.
			let pixelScale: CGFloat = 2
			let pxW = Int((displaySize.width * pixelScale).rounded())
			let pxH = Int((displaySize.height * pixelScale).rounded())
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
				ctx.interpolationQuality = .high
				ctx.draw(slice, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
				owned = ctx.makeImage() ?? slice
			} else {
				owned = slice
			}
			let image = NSImage(cgImage: owned, size: displaySize)
			out.append(Frame(image: image, cgImage: owned))
		}

		return out
	}

	/// One animation frame: the renderable `NSImage` plus its backing
	/// `CGImage`. The renderer keeps the CGImage handy so desaturation can
	/// feed Core Image directly instead of asking AppKit to vend one via
	/// `NSImage.cgImage(forProposedRect:)`, which intermittently returns nil
	/// when the NSImage's logical size (points) differs from its backing
	/// pixel dimensions and was the root cause of the menubar flicker.
	struct Frame {
		let image: NSImage
		let cgImage: CGImage
	}

	// MARK: - Helpers

	static func defaultPetDirectoryPath() -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser
		return home
			.appendingPathComponent(".codex")
			.appendingPathComponent("pets")
			.appendingPathComponent(PetConfig.resolvedPetName())
			.path
	}
}

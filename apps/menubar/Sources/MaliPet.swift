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

/// Phase 02's pet asset loader.
///
/// Reads `pet.json` + the WebP spritesheet from `petDirectory` (default
/// `~/.codex/pets/mali/`) and exposes a hardcoded `ActivityState → RowSpec`
/// table. The four floor states the renderer paints are mapped to their
/// visually-inspected rows in `spritesheet-grid-8x9.png` (8 cols × 9 rows).
///
/// Hardcoded map is deliberate over `pet.json` extension or a sibling
/// rows file because Phase 02 ships exactly one pet and the format
/// extension belongs to Phase 06's multi-pet catalog work — see the ticket
/// Rationale section.
final class MaliPet {
	let id: String
	let displayName: String
	let spritesheet: NSImage

	/// Hardcoded row map for the four floor states.
	///
	/// Row indices owner-confirmed against `spritesheet-grid-8x9.png` cells:
	///
	/// - `.idle`         → row 0 (top row of standing/idle chibi poses)
	/// - `.implementing` → row 7 (seated chibi with laptop + glasses)
	/// - `.runningTests` → row 8 (bottom row of pose variants)
	/// - `.celebrating`  → row 4 (raised-arm / celebratory poses)
	///
	/// Frame counts are visually estimated leading-frame counts before each
	/// row terminates in unused magenta-background cells. If a count is
	/// wrong, the renderer will animate fewer or more frames than intended;
	/// correct here and rebuild.
	static let rowMap: [ActivityState: RowSpec] = [
		.idle: RowSpec(rowIndex: 0, frameCount: 8),
		.implementing: RowSpec(rowIndex: 7, frameCount: 6),
		.runningTests: RowSpec(rowIndex: 8, frameCount: 4),
		.celebrating: RowSpec(rowIndex: 4, frameCount: 5),
	]

	/// Spritesheet grid dimensions. The grid PNG asserts 8 columns × 9 rows.
	static let gridColumns = 8
	static let gridRows = 9

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
	func frames(for state: ActivityState) -> [NSImage] {
		guard let spec = MaliPet.rowMap[state] else { return [] }

		var out: [NSImage] = []
		out.reserveCapacity(spec.frameCount)
		let pixelSize = NSSize(width: frameWidth, height: frameHeight)

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
			let image = NSImage(cgImage: slice, size: pixelSize)
			out.append(image)
		}

		return out
	}

	// MARK: - Helpers

	private static func defaultPetDirectoryPath() -> String {
		let home = FileManager.default.homeDirectoryForCurrentUser
		return home
			.appendingPathComponent(".codex")
			.appendingPathComponent("pets")
			.appendingPathComponent("mali")
			.path
	}
}

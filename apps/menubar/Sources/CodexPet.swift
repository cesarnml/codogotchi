import AppKit
import Foundation

/// Failure modes for `CodexPet(petDirectory:)`. Surfaced as named cases so the
/// caller (P2.05 renderer, P2.06 demo mode) can map them to user-visible
/// failure visuals without re-parsing an error string.
enum CodexPetLoadError: Error, Equatable {
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
final class CodexPet {
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

	/// Reserved-row map for mouse-reactive floating interactions (P4.07).
	///
	/// These rows are deliberately kept off `rowMap` so the menu-bar renderer —
	/// which resolves frames keyed by `ActivityState` — never consumes them.
	/// Only the floating scene reads this map via `frames(forInteraction:)`.
	///
	/// Row indices per `docs/contracts/animation-state-vocabulary.md`:
	/// - `.runningRight` → row 1
	/// - `.runningLeft`  → row 2
	/// - `.jumping`      → row 4
	///
	/// Frame counts: running rows use the full 8-column cycle; jumping uses 5
	/// frames per the Phase 02 `celebrating` precedent for the same row.
	static let interactionRowMap: [FloatingInteraction: RowSpec] = [
		.runningRight: RowSpec(rowIndex: 1, frameCount: 8),
		.runningLeft: RowSpec(rowIndex: 2, frameCount: 8),
		.jumping: RowSpec(rowIndex: 4, frameCount: 5),
	]

	/// Spritesheet grid dimensions. The grid PNG asserts 8 columns × 9 rows.
	static let gridColumns = 8
	static let gridRows = 9

	/// Per-frame display interval for Codex-sheet animations.
	///
	/// Codex-sheet runs on an 8-column grid; full-row cycles target ~1.5 s
	/// (`animationCycleDuration / frameCount` in the renderers).
	/// Codogotchi-sheet frames use their own interval.
	static let animationCycleDuration: TimeInterval = 1.5
	static let frameInterval: TimeInterval = animationCycleDuration / Double(gridColumns)

	private let cgSheet: CGImage
	private let frameWidth: Int
	private let frameHeight: Int
	/// Materialized interaction rows for the floating pet (Fix 14). Slicing a row
	/// from the sheet is ~100–200 ms; cache once per interaction at load time.
	private var floatingInteractionFrameCache: [FloatingInteraction: [Frame]] = [:]

	convenience init() throws {
		try self.init(petDirectory: CodexPet.defaultPetDirectoryPath())
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
			throw CodexPetLoadError.petJsonNotFound
		}

		let manifest: PetManifest
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			manifest = try decoder.decode(PetManifest.self, from: petJsonData)
		} catch {
			throw CodexPetLoadError.petJsonMalformed
		}

		let sheetURL = dirURL.appendingPathComponent(manifest.spritesheetPath)
		guard FileManager.default.fileExists(atPath: sheetURL.path) else {
			throw CodexPetLoadError.spritesheetNotFound
		}

		// `NSImage(contentsOfFile:)` decodes WebP via ImageIO on macOS 13+. If
		// a future repo target loses ImageIO WebP support, fall back to
		// `CGImageSourceCreateWithURL` and convert the fixture to PNG; see
		// the ticket Rationale section.
		guard let image = NSImage(contentsOfFile: sheetURL.path) else {
			throw CodexPetLoadError.spritesheetUnreadable
		}

		guard
			let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			throw CodexPetLoadError.spritesheetUnreadable
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
			cg.width >= CodexPet.gridColumns,
			cg.height >= CodexPet.gridRows,
			cg.width % CodexPet.gridColumns == 0,
			cg.height % CodexPet.gridRows == 0
		else {
			throw CodexPetLoadError.spritesheetIncompatibleGrid
		}

		self.id = manifest.id
		self.displayName = manifest.displayName
		self.spritesheet = image
		self.cgSheet = cg
		self.frameWidth = cg.width / CodexPet.gridColumns
		self.frameHeight = cg.height / CodexPet.gridRows
		prewarmFloatingInteractionFrameCache()
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
		guard let spec = CodexPet.rowMap[state] else { return [] }
		return frames(forRow: spec, output: .menubar)
	}

	/// Return frames at native source-cell resolution for the SpriteKit
	/// floating pet. Unlike `frames(for:)`, this does not pre-scale to the
	/// menu-bar icon size before SpriteKit receives the texture.
	func floatingFrames(for state: ActivityState) -> [Frame] {
		guard let spec = CodexPet.rowMap[state] else { return [] }
		return frames(forRow: spec, output: .sourceCell)
	}

	/// Slice frames for a reserved interaction row (running-right, running-left,
	/// jumping). Returns empty when the interaction has no row mapping or the
	/// row falls outside the loaded sheet's grid — the caller (floating scene)
	/// must treat empty as "missing reserved row" and fall back to the current
	/// activity-state animation.
	func frames(forInteraction interaction: FloatingInteraction) -> [Frame] {
		sliceInteractionFrames(for: interaction, output: .menubar)
	}

	/// Slice reserved interaction frames at native source-cell resolution for
	/// the floating surface. Results are cached at pet load — safe to call on
	/// every `setInteraction` during translate drags (Fix 14).
	func floatingFrames(forInteraction interaction: FloatingInteraction) -> [Frame] {
		if let cached = floatingInteractionFrameCache[interaction] {
			return cached
		}
		let built = sliceInteractionFrames(for: interaction, output: .sourceCell)
		floatingInteractionFrameCache[interaction] = built
		return built
	}

	private func prewarmFloatingInteractionFrameCache() {
		for interaction in FloatingInteraction.allCases {
			floatingInteractionFrameCache[interaction] = sliceInteractionFrames(
				for: interaction,
				output: .sourceCell
			)
		}
	}

	private func sliceInteractionFrames(
		for interaction: FloatingInteraction,
		output: FrameOutput
	) -> [Frame] {
		guard let spec = CodexPet.interactionRowMap[interaction] else { return [] }
		guard spec.rowIndex < CodexPet.gridRows, spec.frameCount <= CodexPet.gridColumns else {
			return []
		}
		return frames(forRow: spec, output: output)
	}

	private func frames(forRow spec: RowSpec, output: FrameOutput) -> [Frame] {
		var out: [Frame] = []
		out.reserveCapacity(spec.frameCount)
		let displaySize: NSSize
		let pxW: Int
		let pxH: Int
		let interpolation: CGInterpolationQuality
		switch output {
		case .menubar:
			// Scale frames to the standard macOS menubar height (22 pt) so the
			// raw spritesheet pixel dimensions don't overflow the status bar.
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
					"CodexPet.frames(forRow: \(spec)) — cropping returned nil for rect \(rect); rowMap or grid invariant broken"
				)
				continue
			}
			// Some third-party Codex-compatible sheets leave trailing frames fully
			// transparent or pure placeholder magenta. Skip those frames so
			// renderers animate only meaningful frames and preserve cycle timing
			// by dividing 1.5 s over the remaining frame count.
			guard Self.hasRenderablePixels(slice) else {
				continue
			}
			// Materialize the cropped slice into a self-contained CGImage so
			// the resulting NSImage owns its pixel data outright. Cropping
			// returns a view that shares cgSheet's buffer; AppKit's status
			// item rendering then collapses successive frames to whichever
			// one it cached first (a known symptom: pet freezes on one
			// frame instead of animating). Drawing at the display size in
			// @2x pixels also yields a sharp Retina presentation.
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

	private static func hasRenderablePixels(_ image: CGImage) -> Bool {
		let width = image.width
		let height = image.height
		guard width > 0, height > 0 else { return false }
		guard let ctx = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			// If pixel normalization fails, keep the frame rather than dropping
			// potentially valid art due to CoreGraphics context setup issues.
			return true
		}

		ctx.interpolationQuality = .none
		ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		guard let data = ctx.data else { return true }

		let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
		let count = width * height
		var opaqueCount = 0
		var visibleCount = 0

		// Normalized RGBA8 from premultiplied-last bitmap context.
		for i in 0..<count {
			let base = i * 4
			let r = Int(bytes[base])
			let g = Int(bytes[base + 1])
			let b = Int(bytes[base + 2])
			let a = Int(bytes[base + 3])

			if a <= 8 {
				continue
			}
			opaqueCount += 1

			// Treat fully/sufficiently saturated placeholder magenta as blank.
			let isPlaceholderMagenta = r >= 240 && g <= 20 && b >= 240
			if !isPlaceholderMagenta {
				visibleCount += 1
				if visibleCount > 0 {
					return true
				}
			}
		}

		// Entirely transparent or entirely placeholder-magenta frame.
		return opaqueCount > 0 && visibleCount > 0
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

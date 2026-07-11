import AppKit
import Foundation

/// Slices a static thumbnail from a pet's spritesheet for the Pet-tab card grid.
///
/// The thumbnail is the first frame of the idle animation row — row 0, column 0
/// of the 8×9 Codex/codogotchi sheet grid (see `CodexPet.rowMap`, where `.idle`
/// maps to `rowIndex: 0`). A single static frame is deliberate: animating dozens
/// of catalog cards would be a perf and attention tax, so the grid shows each
/// pet at rest.
enum PetThumbnail {
	private static let gridColumns = 8
	private static let gridRows = 9

	/// Returns the idle first frame scaled so its height is `targetHeight`
	/// points (drawn at @2x for Retina sharpness), or `nil` when the sheet is
	/// missing, unreadable, or smaller than the grid.
	static func idleFirstFrame(spritesheetURL: URL, targetHeight: CGFloat = 40) -> NSImage? {
		guard
			FileManager.default.fileExists(atPath: spritesheetURL.path),
			let image = NSImage(contentsOfFile: spritesheetURL.path),
			let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
			cg.width >= gridColumns, cg.height >= gridRows
		else { return nil }

		let frameW = cg.width / gridColumns
		let frameH = cg.height / gridRows
		guard frameW > 0, frameH > 0,
			let slice = cg.cropping(to: CGRect(x: 0, y: 0, width: frameW, height: frameH))
		else { return nil }

		let scale = targetHeight / CGFloat(frameH)
		let size = NSSize(width: CGFloat(frameW) * scale, height: targetHeight)
		let pixelScale: CGFloat = 2
		let pxW = max(1, Int((size.width * pixelScale).rounded()))
		let pxH = max(1, Int((size.height * pixelScale).rounded()))

		guard let ctx = CGContext(
			data: nil, width: pxW, height: pxH,
			bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			return NSImage(cgImage: slice, size: size)
		}
		ctx.interpolationQuality = .high
		ctx.draw(slice, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
		guard let owned = ctx.makeImage() else { return NSImage(cgImage: slice, size: size) }
		return NSImage(cgImage: owned, size: size)
	}
}

import AppKit

/// Draws the resize affordance icon in a layer above SpriteKit so subview
/// hiding / Metal compositing cannot swallow it.
final class FloatingPetOverlayView: NSView {
	var showsResizeAffordance = false
	var resizeAffordanceRect: CGRect = .zero

	override var isOpaque: Bool { false }

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override func draw(_ dirtyRect: NSRect) {
		guard showsResizeAffordance else { return }
		let drawRect = resizeAffordanceRect.isEmpty
			? FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
			: resizeAffordanceRect
		FloatingPetOverlayView.drawResizeAffordance(in: drawRect)
	}

	static func drawResizeAffordance(in affordanceBounds: CGRect) {
		let bgRect = affordanceBounds.insetBy(dx: 3, dy: 3)
		guard bgRect.width > 4, bgRect.height > 4 else {
			return
		}

		let background = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.20, alpha: 0.94)
		let rounded = NSBezierPath(roundedRect: bgRect, xRadius: 5, yRadius: 5)
		background.setFill()
		rounded.fill()

		if let symbol = NSImage(
			systemSymbolName: "arrow.up.left.and.arrow.down.right",
			accessibilityDescription: nil
		) {
			let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
				.applying(.init(hierarchicalColor: .white))
			let icon = symbol.withSymbolConfiguration(config) ?? symbol
			let iconSide = min(bgRect.width, bgRect.height) - 4
			icon.size = NSSize(width: iconSide, height: iconSide)
			let origin = NSPoint(
				x: bgRect.midX - iconSide / 2,
				y: bgRect.midY - iconSide / 2
			)
			icon.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
			return
		}

		drawFallbackArrows(in: bgRect)
	}

	private static func drawFallbackArrows(in bgRect: NSRect) {
		NSColor.white.withAlphaComponent(0.9).setStroke()
		let path = NSBezierPath()
		path.lineWidth = 1.5
		let inset: CGFloat = 5
		path.move(to: CGPoint(x: bgRect.minX + inset, y: bgRect.maxY - inset))
		path.line(to: CGPoint(x: bgRect.maxX - inset, y: bgRect.minY + inset))
		path.move(to: CGPoint(x: bgRect.minX + inset + 3, y: bgRect.maxY - inset))
		path.line(to: CGPoint(x: bgRect.minX + inset, y: bgRect.maxY - inset - 3))
		path.move(to: CGPoint(x: bgRect.maxX - inset, y: bgRect.minY + inset + 3))
		path.line(to: CGPoint(x: bgRect.maxX - inset - 3, y: bgRect.minY + inset))
		path.stroke()
	}
}


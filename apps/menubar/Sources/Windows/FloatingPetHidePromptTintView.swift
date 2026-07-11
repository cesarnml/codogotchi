import AppKit

final class FloatingPetHidePromptTintView: NSView {
	override func makeBackingLayer() -> CALayer {
		let layer = CAGradientLayer()
		layer.startPoint = CGPoint(x: 0.5, y: 1)
		layer.endPoint = CGPoint(x: 0.5, y: 0)
		return layer
	}

	private var gradientLayer: CAGradientLayer? { layer as? CAGradientLayer }

	func setGradient(top: NSColor, bottom: NSColor) {
		gradientLayer?.colors = [bottom.cgColor, top.cgColor]
	}
}

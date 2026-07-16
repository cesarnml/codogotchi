import AppKit

final class RPGMiniRingIconView: NSView {
	private let shapeLayer = CAShapeLayer()

	init(fraction: Double) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.addSublayer(shapeLayer)
		shapeLayer.fillColor = NSColor.clear.cgColor
		shapeLayer.strokeColor = NSColor.systemYellow.cgColor
		shapeLayer.lineWidth = 4
		shapeLayer.lineCap = .round
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 34),
			heightAnchor.constraint(equalToConstant: 34),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	override func layout() {
		super.layout()
		let inset: CGFloat = 6
		let rect = bounds.insetBy(dx: inset, dy: inset)
		let path = CGMutablePath()
		path.addEllipse(in: rect)
		shapeLayer.frame = bounds
		shapeLayer.path = path
	}
}

import AppKit

/// Bare timer glyph, sized to a `badgeHeight` square. Chrome (frosted
/// background, border, shadow) now lives on the owning `PromptTimerChipView`
/// pill, which wraps this glyph and the countdown label in one shared
/// background — this view only lays out the image.
final class TimerIconChipView: NSView {
	private let imageView = NSImageView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var sideConstraint: NSLayoutConstraint?
	private var glyphInsetConstraints: [NSLayoutConstraint] = []

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.contentTintColor = AnimationBadgeChrome.textColor
		imageView.translatesAutoresizingMaskIntoConstraints = false
		if let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Prompt timer") {
			image.isTemplate = true
			imageView.image = image
		}
		addSubview(imageView)

		let side = widthAnchor.constraint(equalToConstant: metrics.badgeHeight)
		let height = heightAnchor.constraint(equalTo: widthAnchor)
		let inset = metrics.verticalPadding
		glyphInsetConstraints = [
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			imageView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
		]
		sideConstraint = side
		NSLayoutConstraint.activate([side, height] + glyphInsetConstraints)
		applyMetrics(isRunning: true)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(metrics: GateBadgeLayout.Metrics, isRunning: Bool) {
		self.metrics = metrics
		applyMetrics(isRunning: isRunning)
	}

	private func applyMetrics(isRunning: Bool) {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		imageView.alphaValue = isRunning ? 1.0 : 0.72
	}
}


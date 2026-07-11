import AppKit

/// Square frosted chip carrying the driving platform's logo, shown immediately
/// left of the animation badge. The logo is a template (monochrome) asset tinted
/// to the badge text color so it reads on both light and dark backdrops.
final class PlatformChipView: NSView {
	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let imageView = NSImageView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var sideConstraint: NSLayoutConstraint?
	private var glyphInsetConstraints: [NSLayoutConstraint] = []

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.contentTintColor = AnimationBadgeChrome.textColor
		imageView.translatesAutoresizingMaskIntoConstraints = false
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
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			side,
			height,
		] + glyphInsetConstraints)
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(platform: PlatformAttribution, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		let image = NSImage(named: platform.assetName)
		image?.isTemplate = true
		imageView.image = image
		applyMetrics()
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	private func applyMetrics() {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}


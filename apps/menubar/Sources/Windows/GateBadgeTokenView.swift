import AppKit

/// Frosted badge token matching the attention bubble / animation badge chrome:
/// a `hudWindow` visual-effect material, hairline white border, soft shadow.
/// `tintColor` layers a translucent hue over the material (used for the ticket
/// token's dark navy); pass `nil` for the neutral dark gate token.
final class GateBadgeTokenView: NSView {
	private let effectView = NSVisualEffectView(frame: .zero)
	private let tintView = NSView(frame: .zero)
	private let label = NSTextField(labelWithString: "")
	private let textColor: NSColor
	private let weight: NSFont.Weight
	private let tintColor: NSColor?
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var heightConstraint: NSLayoutConstraint?
	private var leadingConstraint: NSLayoutConstraint?
	private var trailingConstraint: NSLayoutConstraint?

	init(tintColor: NSColor?, textColor: NSColor, weight: NSFont.Weight) {
		self.tintColor = tintColor
		self.textColor = textColor
		self.weight = weight
		super.init(frame: .zero)
		wantsLayer = true
		layer?.masksToBounds = false

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		tintView.wantsLayer = true
		tintView.layer?.backgroundColor = (tintColor ?? .clear).cgColor
		tintView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tintView)

		label.textColor = textColor
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		let heightConstraint = heightAnchor.constraint(equalToConstant: metrics.badgeHeight)
		let leadingConstraint = label.leadingAnchor.constraint(
			equalTo: leadingAnchor,
			constant: metrics.horizontalPadding
		)
		let trailingConstraint = label.trailingAnchor.constraint(
			equalTo: trailingAnchor,
			constant: -metrics.horizontalPadding
		)
		self.heightConstraint = heightConstraint
		self.leadingConstraint = leadingConstraint
		self.trailingConstraint = trailingConstraint
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			heightConstraint,
			leadingConstraint,
			trailingConstraint,
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(text: String, metrics: GateBadgeLayout.Metrics) {
		label.stringValue = text
		self.metrics = metrics
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	override var intrinsicContentSize: NSSize {
		let textSize = label.intrinsicContentSize
		return NSSize(
			width: textSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	private func applyMetrics() {
		effectView.layer?.cornerRadius = metrics.cornerRadius
		effectView.layer?.masksToBounds = true
		tintView.layer?.cornerRadius = metrics.cornerRadius
		tintView.layer?.masksToBounds = true
		layer?.cornerRadius = metrics.cornerRadius
		layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0.32
		layer?.shadowRadius = 8
		layer?.shadowOffset = CGSize(width: 0, height: -2)
		label.font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: weight)
		label.textColor = textColor
		heightConstraint?.constant = metrics.badgeHeight
		leadingConstraint?.constant = metrics.horizontalPadding
		trailingConstraint?.constant = -metrics.horizontalPadding
	}
}


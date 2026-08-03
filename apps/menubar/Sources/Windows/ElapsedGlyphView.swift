import AppKit

/// Bare elapsed-clock glyph, sized to a `badgeHeight` square. Chrome (frosted
/// background, border, shadow) lives on the owning `ElapsedChipView` pill, which
/// wraps this glyph and the label in one shared background — this view only lays
/// out the image.
///
/// The symbol is `ElapsedKind`-driven (`timer` for a prompt turn, `zzz` for an
/// idle session) rather than fixed, since one chip slot serves both clocks.
final class ElapsedGlyphView: NSView {
	private let imageView = NSImageView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var sideConstraint: NSLayoutConstraint?
	private var glyphInsetConstraints: [NSLayoutConstraint] = []
	/// Last applied kind, so a same-kind reconfigure skips the symbol lookup.
	/// `nil` until the first `configure` — the initializer deliberately picks no
	/// default glyph, so the chip can never flash the wrong symbol for a frame.
	private var currentKind: ElapsedKind?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

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
		NSLayoutConstraint.activate([side, height] + glyphInsetConstraints)
		applyMetrics(isRunning: true)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(metrics: GateBadgeLayout.Metrics, isRunning: Bool, kind: ElapsedKind) {
		self.metrics = metrics
		applyKind(kind)
		applyMetrics(isRunning: isRunning)
	}

	private func applyKind(_ kind: ElapsedKind) {
		guard kind != currentKind else { return }
		currentKind = kind
		guard let image = NSImage(
			systemSymbolName: kind.symbolName,
			accessibilityDescription: kind.accessibilityDescription
		) else { return }
		image.isTemplate = true
		imageView.image = image
	}

	private func applyMetrics(isRunning: Bool) {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		imageView.alphaValue = isRunning ? 1.0 : 0.72
	}
}

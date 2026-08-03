import AppKit

/// Single frosted pill housing the elapsed-clock glyph and its label together,
/// on the same `AnimationBadgeChrome` background as `PlatformSessionBadge` —
/// previously the glyph alone carried its own chrome while the "1:00" label sat
/// bare in the stack, so the time read as plain text over whatever the pet was
/// floating above. The glyph no longer
/// draws its own chrome; this view now owns one background spanning both.
///
/// Renders whichever clock `ElapsedPresentation.kind` names — the prompt turn
/// while the agent works, the idle duration while it is quiet. The two never
/// contend for the slot: `PromptTimerTracker` clears itself on `idle`, which is
/// the only state `IdleElapsed` produces a presentation for.
final class ElapsedChipView: NSView {
	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let chipView = ElapsedGlyphView(frame: .zero)
	private let label = NSTextField(labelWithString: "")
	private let stackView = NSStackView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		stackView.orientation = .horizontal
		stackView.alignment = .centerY
		stackView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stackView)
		stackView.addArrangedSubview(chipView)
		stackView.addArrangedSubview(label)

		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.textColor = AnimationBadgeChrome.textColor
		label.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.horizontalPadding * 0.6),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.horizontalPadding),
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(presentation: ElapsedPresentation, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		label.stringValue = presentation.label
		label.alphaValue = presentation.isRunning ? 1.0 : 0.72
		chipView.configure(
			metrics: metrics, isRunning: presentation.isRunning, kind: presentation.kind)
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		let labelSize = label.intrinsicContentSize
		return NSSize(
			width: metrics.horizontalPadding * 1.6 + metrics.badgeHeight
				+ stackView.spacing + labelSize.width,
			height: metrics.badgeHeight
		)
	}

	private func applyMetrics() {
		label.font = NSFont.monospacedDigitSystemFont(ofSize: metrics.fontSize, weight: .medium)
		stackView.spacing = max(2, round(metrics.interBadgeSpacing * 0.55))
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}


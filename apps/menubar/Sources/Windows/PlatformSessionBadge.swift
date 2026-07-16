import AppKit

/// Session-label pill shown as a second row beneath the platform chip +
/// animation badge, centered horizontally. Renders the user's rename label
/// (from `SessionLabelStore`, via `configure(number:label:tooltip:metrics:)`)
/// when set, else falls back to "Session N" for the number assigned by
/// `SessionNumberAllocatorState`. `tooltip` exposes the session's last submitted
/// prompt as a native `NSView.toolTip` (P15.06). Reuses the same frosted
/// chrome and `GateBadgeLayout.Metrics` scaling as the animation badge pill —
/// single source of scaling truth.
final class PlatformSessionBadge: NSView {
	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let label = NSTextField(labelWithString: "")
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.alignment = .center
		label.textColor = AnimationBadgeChrome.textColor
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	/// Configures the badge for session `number` and decides whether it should
	/// be visible at all. `label`, when present, replaces the "Session N" text
	/// with the user's rename (P15.06) — or, for a plain-origin/"combined"
	/// window (`number` `nil`), the pool's platform-name default or the user's
	/// rename (P?? unification: these windows now get a badge too, where
	/// previously `number == nil` hid the row unconditionally regardless of
	/// `label`). The row hides only when there is truly nothing to show
	/// (`number` and `label` both `nil` — a plain-origin window whose origin
	/// didn't resolve to a known platform). `tooltip` — the session's last
	/// submitted prompt — is shown by AppKit's native delayed hover tooltip;
	/// empty/`nil` clears it.
	func configure(number: Int?, label: String? = nil, tooltip: String? = nil, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		let resolvedLabel = (label?.isEmpty == false) ? label : nil
		// Assign toolTip only on real change: the setter re-registers AppKit's
		// tooltip tracking even for an identical string, restarting the hover
		// delay — and reposition() re-configures every poll tick, so an
		// unconditional set here starves the delayed tooltip forever.
		let resolvedTooltip: String?
		if let number {
			self.label.stringValue = resolvedLabel ?? "Session \(number)"
			isHidden = false
			resolvedTooltip = (tooltip?.isEmpty == false) ? tooltip : nil
		} else if let resolvedLabel {
			self.label.stringValue = resolvedLabel
			isHidden = false
			resolvedTooltip = (tooltip?.isEmpty == false) ? tooltip : nil
		} else {
			isHidden = true
			resolvedTooltip = nil
		}
		if toolTip != resolvedTooltip {
			toolTip = resolvedTooltip
			boundsAtTooltipRegistration = bounds
		}
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	// Geometry captured at the moment AppKit registers the tooltip rect, so
	// `layout()` can detect later silent resizes and re-register.
	private var boundsAtTooltipRegistration: NSRect = .zero

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: label.intrinsicContentSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	override func layout() {
		super.layout()
		applyMetrics()
		// AppKit pins the tooltip rect to the view's geometry at toolTip-setter
		// time and does not track later resizes. The badge resizes after
		// registration whenever the label text changes without the tooltip
		// string changing (e.g. "Session N" → retrieved title), leaving a
		// stale rect that no longer covers the hover area — so re-register
		// here whenever bounds have drifted since the last registration.
		if toolTip != nil, bounds != boundsAtTooltipRegistration {
			let current = toolTip
			toolTip = nil
			toolTip = current
			boundsAtTooltipRegistration = bounds
		}
	}

	private func applyMetrics() {
		let font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: .medium)
		label.font = font
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}


import AppKit

/// Frosted label pill: the activity-state name on the same chrome as the
/// platform chip. Sizing/scaling follows the gate badge metrics.
final class AnimationLabelPillView: NSView {
	/// Base label opacity while the agent is working: dimmed so the bright sweep
	/// reads as a highlight passing through. Restored to `restColor` at rest.
	private static let inFlightColor = NSColor(calibratedWhite: 0.58, alpha: 1.0)
	private static let restColor = AnimationBadgeChrome.textColor
	/// Width of the bright band as a fraction of the label width. The band is a
	/// clear→white→clear gradient, so the strongly-lit core reads as ~half of this.
	private static let shimmerBandFraction: CGFloat = 0.8
	/// Seconds for one full left→right pass across the text.
	private static let shimmerDuration: CFTimeInterval = 1.3
	private static let shimmerAnimationKey = "codogotchi.badge.shimmer"

	private let effectView = AnimationBadgeChrome.makeEffectView()
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let label = NSTextField(labelWithString: "")
	/// Overlay clipped to the glyph shapes (`glyphMask`). It hosts the moving
	/// `shimmerBand`; everything outside the band reads through to the dimmed base
	/// `label`, so a bright highlight appears only where the band crosses letters.
	private let shimmerContainer = CALayer()
	/// The bright band that physically translates across the text. A *normal*
	/// sublayer (not a mask), so its position animation runs reliably — animating a
	/// mask layer's geometry, by contrast, is silently dropped by Core Animation.
	private let shimmerBand = CAGradientLayer()
	/// Static glyph stencil used as `shimmerContainer.mask`. Mirrors the label's
	/// string/font/alignment/frame so the highlight registers on the letters.
	private let glyphMask = CATextLayer()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var isShimmering = false
	/// Band width the running animation was built for; lets us restart only when
	/// the label resizes, not on every layout pass.
	private var shimmerBandWidth: CGFloat = 0
	private var occlusionObserver: NSObjectProtocol?
	/// Watchdog that re-arms the sweep if it ever stops advancing. Core Animation
	/// culls animations on a range of events (Space switch, app deactivation,
	/// window occlusion) and does not always restore them or fire a notification,
	/// which previously left the highlight frozen mid-text. The heartbeat samples
	/// the band's presentation layer and restarts the animation the instant it
	/// detects no movement, so the sweep cannot stay stuck.
	private var shimmerHeartbeat: Timer?
	private var lastShimmerSampleX: CGFloat = .nan

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.alignment = .center
		label.textColor = Self.restColor
		label.wantsLayer = true
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		// Glyph-masked overlay hosting a narrow bright band. Hidden until a working
		// state arrives. Hosted in the pill's own layer (above the label) rather
		// than the text field's AppKit-owned layer.
		glyphMask.alignmentMode = .center
		glyphMask.truncationMode = .end
		glyphMask.foregroundColor = NSColor.white.cgColor
		shimmerContainer.mask = glyphMask
		shimmerContainer.masksToBounds = true
		shimmerContainer.isHidden = true
		shimmerContainer.zPosition = 1

		shimmerBand.startPoint = CGPoint(x: 0, y: 0.5)
		shimmerBand.endPoint = CGPoint(x: 1, y: 0.5)
		shimmerBand.colors = [
			NSColor.clear.cgColor,
			NSColor.white.cgColor,
			NSColor.clear.cgColor,
		]
		shimmerBand.locations = [0, 0.5, 1]
		shimmerContainer.addSublayer(shimmerBand)
		layer?.addSublayer(shimmerContainer)

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

	deinit {
		if let occlusionObserver {
			NotificationCenter.default.removeObserver(occlusionObserver)
		}
		shimmerHeartbeat?.invalidate()
	}

	func configure(text: String, inFlight: Bool, metrics: GateBadgeLayout.Metrics) {
		self.metrics = metrics
		let font = NSFont.monospacedSystemFont(ofSize: metrics.fontSize, weight: .medium)
		label.stringValue = text
		label.font = font
		label.textColor = inFlight ? Self.inFlightColor : Self.restColor
		glyphMask.string = text
		glyphMask.font = font
		glyphMask.fontSize = metrics.fontSize
		setShimmering(inFlight)
		applyMetrics()
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: label.intrinsicContentSize.width + metrics.horizontalPadding * 2,
			height: metrics.badgeHeight
		)
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		let scale = window?.backingScaleFactor ?? 2
		glyphMask.contentsScale = scale
		shimmerBand.contentsScale = scale
		// A move between displays drops layer animations; force a re-arm.
		forceShimmerRearm()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		observeWindowVisibility()
		// Re-attaching to a window drops any prior animation; re-arm.
		forceShimmerRearm()
	}

	/// Core Animation culls running animations whenever the hosting window is
	/// occluded or moved off the active Space, and they are *not* restored when it
	/// returns. For a long-lived state (e.g. "Reading") nothing else would re-arm
	/// the sweep, so it would freeze. Re-arm whenever the window becomes visible.
	private func observeWindowVisibility() {
		if let occlusionObserver {
			NotificationCenter.default.removeObserver(occlusionObserver)
			self.occlusionObserver = nil
		}
		guard let window else { return }
		occlusionObserver = NotificationCenter.default.addObserver(
			forName: NSWindow.didChangeOcclusionStateNotification,
			object: window,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
				self.forceShimmerRearm()
			}
		}
	}

	private func setShimmering(_ shimmering: Bool) {
		shimmerContainer.isHidden = !shimmering
		isShimmering = shimmering
		if shimmering {
			startShimmerHeartbeat()
		} else {
			shimmerHeartbeat?.invalidate()
			shimmerHeartbeat = nil
			shimmerBand.removeAnimation(forKey: Self.shimmerAnimationKey)
			shimmerBandWidth = 0
		}
		// `refreshShimmerGeometry` (driven from `applyMetrics`) arms the animation
		// once the label has a resolved width.
	}

	private func startShimmerHeartbeat() {
		guard shimmerHeartbeat == nil else { return }
		lastShimmerSampleX = .nan
		// Sample a few times per sweep. Added to `.common` modes so it keeps firing
		// during tracking runloops (menu/drag), and on the main runloop it fires
		// even while the app is in the background.
		let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.shimmerHeartbeatTick() }
		}
		RunLoop.main.add(timer, forMode: .common)
		shimmerHeartbeat = timer
	}

	private func shimmerHeartbeatTick() {
		// Only police the sweep when it should actually be running and visible.
		guard isShimmering, window?.occlusionState.contains(.visible) == true else {
			lastShimmerSampleX = .nan
			return
		}
		let sample = shimmerBand.presentation()?.position.x ?? .nan
		defer { lastShimmerSampleX = sample }
		// Frozen if there is no in-flight presentation, or the band has not advanced
		// since the previous sample. A spurious match at the sweep wrap just restarts
		// the sweep — visually harmless.
		let frozen = sample.isNaN || (!lastShimmerSampleX.isNaN && abs(sample - lastShimmerSampleX) < 0.5)
		if frozen { forceShimmerRearm() }
	}

	private func forceShimmerRearm() {
		shimmerBandWidth = 0
		shimmerBand.removeAnimation(forKey: Self.shimmerAnimationKey)
		refreshShimmerGeometry()
	}

	/// Size the band to the current label width and (re)arm the sweep. Restarts
	/// only when the band width actually changes so steady-state layout passes do
	/// not reset the animation phase mid-stroke.
	private func refreshShimmerGeometry() {
		let width = label.bounds.width
		let height = label.bounds.height
		guard isShimmering, width > 0, height > 0 else { return }
		let bandWidth = max(8, width * Self.shimmerBandFraction)
		let needsRestart =
			abs(bandWidth - shimmerBandWidth) > 0.5
			|| shimmerBand.animation(forKey: Self.shimmerAnimationKey) == nil
		guard needsRestart else { return }
		shimmerBandWidth = bandWidth

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shimmerBand.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: height)
		shimmerBand.position = CGPoint(x: -bandWidth / 2, y: height / 2)
		CATransaction.commit()

		let animation = CABasicAnimation(keyPath: "position.x")
		// Center of the band travels from just off the left edge to just off the
		// right edge — one continuous left→right pass per cycle.
		animation.fromValue = -bandWidth / 2
		animation.toValue = width + bandWidth / 2
		animation.duration = Self.shimmerDuration
		animation.repeatCount = .infinity
		animation.timingFunction = CAMediaTimingFunction(name: .linear)
		shimmerBand.add(animation, forKey: Self.shimmerAnimationKey)
	}

	private func applyMetrics() {
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
		// Mirror the label's resolved frame so the overlay glyph stencil registers
		// exactly on top of the dimmed base glyphs. Disable implicit animation so
		// the overlay does not lag the pill during drag/reposition.
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shimmerContainer.frame = label.frame
		glyphMask.frame = shimmerContainer.bounds
		CATransaction.commit()
		refreshShimmerGeometry()
	}
}


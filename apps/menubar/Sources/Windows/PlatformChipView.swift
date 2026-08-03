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

	/// Key for the single logo animation on `imageView`'s layer. One key means
	/// re-applying is idempotent and removal is unambiguous.
	private static let animationKey = "platformChipLogo"
	/// Animation currently installed on the glyph layer, or `nil` when static.
	/// `configure` runs on every poll tick, so this is what keeps an unchanged
	/// animation from being torn down and restarted (a visible stutter) each time.
	private var installedAnimation: PlatformChipAnimation?
	private var currentPlatform: PlatformAttribution?
	private var motionSettings = MotionSettings.disabled
	private var isInFlight = false
	/// Set while the badge panel is ordered out. `window` stays non-nil for an
	/// ordered-out window and Core Animation keeps evaluating the animation, so
	/// without an explicit signal a hidden pet would animate forever — see
	/// `refreshAnimation`.
	private var isSuspended = false
	/// Token for the Reduce Motion observer. Block-based with an explicit main
	/// queue, so the handler cannot land off-main and race `deinit`.
	private var reducedMotionObserver: (any NSObjectProtocol)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		addSubview(effectView)
		addSubview(tintView)

		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.contentTintColor = AnimationBadgeChrome.textColor
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.wantsLayer = true
		addSubview(imageView)
		centerGlyphAnchorPoint()

		// Reduce Motion is toggled in System Settings while the app is running, so
		// react to it live rather than only sampling it at launch. Block-based with
		// `queue: .main` rather than a selector: AppKit does not promise which
		// thread posts this, and a selector-based observer would leave `deinit`'s
		// removal racing an already-dispatched call into a half-freed view.
		reducedMotionObserver = MotionPolicy.observeChanges { [weak self] in
			self?.refreshAnimation()
		}

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

	deinit {
		MotionPolicy.removeObserver(reducedMotionObserver)
	}

	/// Called when the badge panel is ordered out or back in. Ordering a window
	/// out does not clear `window` on its views, so this is the only signal the
	/// chip gets that it is no longer on screen.
	func setAnimationSuspended(_ suspended: Bool) {
		guard suspended != isSuspended else { return }
		isSuspended = suspended
		refreshAnimation()
	}

	func configure(
		platform: PlatformAttribution,
		metrics: GateBadgeLayout.Metrics,
		inFlight: Bool = false,
		motionSettings: MotionSettings = .disabled
	) {
		self.metrics = metrics
		if platform != currentPlatform {
			currentPlatform = platform
			let image = NSImage(named: platform.assetName)
			image?.isTemplate = true
			imageView.image = image
		}
		self.isInFlight = inFlight
		self.motionSettings = motionSettings
		applyMetrics()
		refreshAnimation()
	}

	/// The chip is a fixed square sized by `metrics.badgeHeight`, but that size
	/// comes from a width constraint — which `intrinsicContentSize` does not
	/// report. Without this override AppKit answers `noIntrinsicMetric` (-1), and
	/// `AnimationBadgeView.pillCenterX` uses that -1 as if it were a real width
	/// when working out where to anchor the badge on the pet. Every sibling in
	/// that stack (`AnimationLabelPillView`, `PlatformSessionBadge`,
	/// `PromptTimerChipView`, `GateBadgeTokenView`) already overrides this.
	override var intrinsicContentSize: NSSize {
		NSSize(width: metrics.badgeHeight, height: metrics.badgeHeight)
	}

	override func layout() {
		super.layout()
		applyMetrics()
		// The glyph's geometry is only real once layout has run. A pool tick can
		// call `configure` before that (freshly spawned window on a mode switch),
		// so this is where a deferred animation actually gets installed.
		refreshAnimation()
	}

	/// Stops the animation as soon as the chip leaves the window, and restores it
	/// on the way back. AppKit does not tear down a `CAAnimation` when its view is
	/// merely unparented, so without this an off-screen chip keeps its layer
	/// animating — invisible, but still burning CPU on an always-running app.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		refreshAnimation()
	}

	/// Re-assert the centre pivot as late as possible.
	///
	/// AppKit resets a freshly-created layer-backed view's `anchorPoint` to
	/// (0, 0) during the first display/commit pass — *after* anything `init`,
	/// `configure`, `applyMetrics` or `layout` can do, so no synchronous call
	/// from those can win the race. `viewWillDraw` runs after that geometry sync
	/// and before the frame is committed, which is the one hook that lands in
	/// time. Measured: without this a fresh chip rotates about its bottom-left
	/// corner for ~1s (the glyph's centre traces a 13pt arc down-and-right) until
	/// the next poll tick repairs it; with it, deviation is 0 from the first
	/// frame. Only fires when the view needs display, so it costs nothing at rest.
	override func viewWillDraw() {
		super.viewWillDraw()
		centerGlyphAnchorPoint()
	}

	/// Single point of truth for whether the glyph is animating. The animation
	/// runs only when it is enabled, the pet is mid-turn, the chip is actually in
	/// a window, the system is not asking for reduced motion, and the platform
	/// has an animation defined.
	private func refreshAnimation() {
		// AppKit re-syncs the glyph layer's geometry — including resetting
		// `anchorPoint` to (0, 0) — whenever it re-lays out the view. Most callers
		// arrive here just after `applyMetrics`, but `viewDidMoveToWindow` and the
		// Reduce Motion observer do not, so re-assert the centre pivot before
		// installing a rotation rather than relying on a layout pass having
		// happened first. Cheap, and it keeps the corner-orbit bug from returning
		// through the back door.
		centerGlyphAnchorPoint()

		// Do not start spinning until the glyph has been laid out. A pool tick can
		// reach `configure` before the first layout pass — most visibly when a mode
		// switch spawns a fresh window mid-turn — and a rotation installed against
		// a zero-sized layer renders about the wrong point, which reads as the mark
		// orbiting rather than spinning. `layout()` calls back here once the real
		// geometry exists, so the only cost is a brief delay before the animation
		// starts, in exchange for never showing the wonky frames.
		let hasLaidOutGeometry = imageView.bounds.width > 0 && imageView.bounds.height > 0

		let desired: PlatformChipAnimation? =
			isInFlight && !isSuspended && window != nil && hasLaidOutGeometry
			&& motionSettings.allowsChipAnimation(systemPrefersReducedMotion: MotionPolicy.prefersReducedMotion())
			? currentPlatform.flatMap(PlatformChipAnimation.forPlatform)
			: nil

		// The descriptor diff alone is not quite enough: if the animation ever
		// goes missing from the layer while we still want it, re-add it. Verified
		// by probe that ordering the window out does *not* drop it — an earlier
		// revision of this comment claimed it did, and was wrong — so this is
		// defensive only, covering whatever else may clear a layer's animations.
		// The ordered-out case is handled by `isSuspended` above, not here.
		let isAnimating = imageView.layer?.animation(forKey: Self.animationKey) != nil
		guard desired != installedAnimation || (desired != nil && !isAnimating) else { return }
		installedAnimation = desired

		guard let desired else {
			imageView.layer?.removeAnimation(forKey: Self.animationKey)
			return
		}
		imageView.layer?.add(desired.makeAnimation(), forKey: Self.animationKey)
	}

	private func applyMetrics() {
		if sideConstraint?.constant != metrics.badgeHeight {
			// AppKit caches `intrinsicContentSize`; the badge-size slider changes it.
			invalidateIntrinsicContentSize()
		}
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
		centerGlyphAnchorPoint()
	}

	/// Pivot the glyph about its own center.
	///
	/// AppKit hands a layer-backed `NSView` an `anchorPoint` of `(0, 0)` — the
	/// bottom-left corner — not the `(0.5, 0.5)` a bare `CALayer` gets. Every
	/// `transform.rotation.*` is applied about the anchor, so on the default
	/// anchor a 13pt glyph orbits its own corner on a ~9pt radius instead of
	/// spinning in place. Re-asserted from `applyMetrics` (i.e. every layout
	/// pass) because AppKit rewrites layer geometry whenever it re-lays out the
	/// view. Only the model `position` moves here; the animated `transform` is
	/// never touched, so AppKit's own layout math is unaffected.
	private func centerGlyphAnchorPoint() {
		guard let glyphLayer = imageView.layer else { return }
		let centered = CGPoint(x: 0.5, y: 0.5)
		if glyphLayer.anchorPoint != centered {
			glyphLayer.anchorPoint = centered
		}
		let center = CGPoint(x: imageView.frame.midX, y: imageView.frame.midY)
		if glyphLayer.position != center {
			glyphLayer.position = center
		}
	}

}


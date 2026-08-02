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
	private var animationEnabled = false
	private var isInFlight = false

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
		// Both flip marks are mirror-symmetric about their rotation axis, so the
		// back face can reuse the same art instead of needing a second asset.
		imageView.layer?.isDoubleSided = true
		addSubview(imageView)
		centerGlyphAnchorPoint()

		// Reduce Motion is toggled in System Settings while the app is running, so
		// react to it live rather than only sampling it at launch.
		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(accessibilityDisplayOptionsChanged),
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)

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
		NSWorkspace.shared.notificationCenter.removeObserver(self)
	}

	@objc private func accessibilityDisplayOptionsChanged() {
		DispatchQueue.main.async { [weak self] in self?.refreshAnimation() }
	}

	func configure(
		platform: PlatformAttribution,
		metrics: GateBadgeLayout.Metrics,
		inFlight: Bool = false,
		animationEnabled: Bool = false
	) {
		self.metrics = metrics
		if platform != currentPlatform {
			currentPlatform = platform
			let image = NSImage(named: platform.assetName)
			image?.isTemplate = true
			imageView.image = image
		}
		self.isInFlight = inFlight
		self.animationEnabled = animationEnabled
		applyMetrics()
		refreshAnimation()
	}

	override func layout() {
		super.layout()
		applyMetrics()
	}

	/// Stops the animation as soon as the chip leaves the window, and restores it
	/// on the way back. AppKit does not tear down a `CAAnimation` when its view is
	/// merely unparented, so without this an off-screen chip keeps its layer
	/// animating — invisible, but still burning CPU on an always-running app.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		refreshAnimation()
	}

	/// Single point of truth for whether the glyph is animating. The animation
	/// runs only when it is enabled, the pet is mid-turn, the chip is actually in
	/// a window, the system is not asking for reduced motion, and the platform
	/// has an animation defined.
	private func refreshAnimation() {
		let desired: PlatformChipAnimation? =
			animationEnabled && isInFlight && window != nil && !Self.prefersReducedMotion()
			? currentPlatform.flatMap(PlatformChipAnimation.forPlatform)
			: nil

		// The descriptor diff alone is not enough to decide there is nothing to
		// do. Core Animation drops a layer's animations when its window is
		// ordered out (`ChromeFlockCoordinator.hideAnimationBadge`), and that
		// happens without `viewDidMoveToWindow` firing — the view is still in the
		// window, the window is just off-screen. Re-showing mid-turn then arrives
		// here with an unchanged descriptor and a layer that is no longer
		// animating, so also re-add whenever the animation has gone missing.
		let isAnimating = imageView.layer?.animation(forKey: Self.animationKey) != nil
		guard desired != installedAnimation || (desired != nil && !isAnimating) else { return }
		installedAnimation = desired

		guard let desired else {
			imageView.layer?.removeAnimation(forKey: Self.animationKey)
			return
		}
		imageView.layer?.add(desired.makeAnimation(), forKey: Self.animationKey)
	}

	/// Whether the system is asking apps to suppress non-essential motion. The
	/// in-app toggle is not a substitute: someone who set Reduce Motion in System
	/// Settings has no reason to expect a per-app switch also needs turning off.
	///
	/// Overridable so tests are deterministic — otherwise every animation test
	/// here would read the host's real accessibility setting and fail outright on
	/// a machine that has Reduce Motion enabled.
	static var prefersReducedMotion: () -> Bool = {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	private func applyMetrics() {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
		centerGlyphAnchorPoint()
		centerPerspective()
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

	/// Perspective for the axis flips, so a turn foreshortens like a solid card
	/// instead of reading as a flat squash.
	///
	/// `sublayerTransform` is applied about the *chip's* anchor point, which is
	/// `(0, 0)` for the same AppKit reason as above — leaving the vanishing point
	/// at the chip's bottom-left corner and skewing the flip off to one side.
	/// Sandwiching the perspective between translations moves the vanishing point
	/// to the chip's center. Recomputed on layout since it depends on the size.
	private func centerPerspective() {
		guard let layer else { return }
		var perspective = CATransform3DIdentity
		perspective.m34 = -1 / 320
		let offset = CGPoint(x: bounds.midX, y: bounds.midY)
		layer.sublayerTransform = CATransform3DConcat(
			CATransform3DConcat(
				CATransform3DMakeTranslation(-offset.x, -offset.y, 0),
				perspective
			),
			CATransform3DMakeTranslation(offset.x, offset.y, 0)
		)
	}
}


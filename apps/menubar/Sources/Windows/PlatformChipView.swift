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
		// Perspective for the in-plane-axis flips, applied to the glyph's parent
		// so it survives animating the glyph layer's own rotation. Without it an
		// axis flip reads as a flat horizontal/vertical squash.
		var perspective = CATransform3DIdentity
		perspective.m34 = -1 / 320
		layer?.sublayerTransform = perspective

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
	/// a window, and the platform has an animation defined.
	private func refreshAnimation() {
		let desired: PlatformChipAnimation? =
			animationEnabled && isInFlight && window != nil
			? currentPlatform.flatMap(PlatformChipAnimation.forPlatform)
			: nil

		guard desired != installedAnimation else { return }
		installedAnimation = desired

		guard let desired else {
			imageView.layer?.removeAnimation(forKey: Self.animationKey)
			return
		}
		imageView.layer?.add(desired.makeAnimation(), forKey: Self.animationKey)
	}

	private func applyMetrics() {
		sideConstraint?.constant = metrics.badgeHeight
		for constraint in glyphInsetConstraints {
			constraint.constant = (constraint.constant < 0 ? -1 : 1) * metrics.verticalPadding
		}
		AnimationBadgeChrome.apply(to: self, effect: effectView, tint: tintView, cornerRadius: metrics.cornerRadius)
	}
}


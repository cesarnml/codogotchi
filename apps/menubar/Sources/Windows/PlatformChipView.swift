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
		reducedMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
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
		if let reducedMotionObserver {
			NSWorkspace.shared.notificationCenter.removeObserver(reducedMotionObserver)
		}
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
		// AppKit re-syncs the glyph layer's geometry — including resetting
		// `anchorPoint` to (0, 0) — whenever it re-lays out the view. Most callers
		// arrive here just after `applyMetrics`, but `viewDidMoveToWindow` and the
		// Reduce Motion observer do not, so re-assert the centre pivot before
		// installing a rotation rather than relying on a layout pass having
		// happened first. Cheap, and it keeps the corner-orbit bug from returning
		// through the back door.
		centerGlyphAnchorPoint()

		let desired: PlatformChipAnimation? =
			animationEnabled && isInFlight && !isSuspended && window != nil
			&& !Self.prefersReducedMotion()
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

	/// Whether the system is asking apps to suppress non-essential motion. The
	/// in-app toggle is not a substitute: someone who set Reduce Motion in System
	/// Settings has no reason to expect a per-app switch also needs turning off.
	///
	/// This is the shipped behaviour and is deliberately a `let` — nothing in the
	/// app can repoint it.
	static let systemPrefersReducedMotion: () -> Bool = {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	/// Test-only override. Animation tests must not read the host's real
	/// accessibility setting or they fail outright on a machine that has Reduce
	/// Motion enabled. Set to `nil` to restore the shipped behaviour; production
	/// never assigns this.
	static var reducedMotionOverrideForTesting: (() -> Bool)?

	static func prefersReducedMotion() -> Bool {
		(reducedMotionOverrideForTesting ?? systemPrefersReducedMotion)()
	}

	private func applyMetrics() {
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


import AppKit
import XCTest

@testable import Codogotchi

/// Covers the animation descriptor table and — more importantly — the chip's
/// add/remove lifecycle. A leaked `CAAnimation` is invisible rather than
/// obviously broken, so the failure mode these guard is idle CPU burn on an
/// always-running menubar app, not a wrong-looking badge.
final class PlatformChipAnimationTests: XCTestCase {

	/// Pin Reduce Motion off for the lifetime of each test. Without this every
	/// animation case below would read the host's real accessibility setting and
	/// fail on a machine that has Reduce Motion enabled.
	///
	/// `tearDown` restores the value saved in `setUp` rather than reconstructing a
	/// default, so this class can never leave a stale reimplementation installed
	/// for the rest of the test process.
	private var savedReducedMotionOverride: (() -> Bool)?

	override func setUp() {
		super.setUp()
		savedReducedMotionOverride = PlatformChipView.reducedMotionOverrideForTesting
		PlatformChipView.reducedMotionOverrideForTesting = { false }
	}

	override func tearDown() {
		PlatformChipView.reducedMotionOverrideForTesting = savedReducedMotionOverride
		super.tearDown()
	}

	// MARK: - Descriptor table

	func testEveryDrivingPlatformSharesTheSameBreathe() {
		// All five are one family — same shrink depth, only the period and whether a
		// rotation rides on top differ — so they read as variations rather than five
		// unrelated animations.
		for platform in [PlatformAttribution.claudeCode, .codex, .cursor, .vscode, .antigravity] {
			let pulse: CGFloat?
			switch PlatformChipAnimation.forPlatform(platform) {
			case let .spin(_, scalePulse): pulse = scalePulse
			case let .breathe(_, scalePulse): pulse = scalePulse
			case .none: pulse = nil
			}
			XCTAssertEqual(
				pulse, PlatformChipAnimation.scalePulse,
				"\(platform.displayName) must shrink and regrow like the others")
		}
	}

	func testOnlyMarksWithRotationalSymmetrySpin() {
		// A mark that maps onto itself every 120 degrees or less reads as spinning in
		// place. A mark with rotational symmetry order 1 has no such rotation, so
		// spinning it tumbles the logo — upside down for half of every cycle, which
		// looks broken rather than busy. Those breathe only.
		for platform in [PlatformAttribution.claudeCode, .codex, .cursor] {
			guard case .spin = PlatformChipAnimation.forPlatform(platform) else {
				XCTFail("\(platform.displayName) is rotationally symmetric and should spin")
				continue
			}
		}
		for platform in [PlatformAttribution.vscode, .antigravity] {
			guard case .breathe = PlatformChipAnimation.forPlatform(platform) else {
				XCTFail("\(platform.displayName) has symmetry order 1 — spinning it would tumble it")
				continue
			}
		}
	}

	func testBreatheNeverRotates() throws {
		// The whole point of the breathe-only treatment: orientation is preserved
		// exactly, so an asymmetric mark is never shown upside down.
		let animation = PlatformChipAnimation.breathe(period: 2, scalePulse: 0.5).makeAnimation()
		let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
		XCTAssertEqual(keyframe.keyPath, "transform.scale")
		XCTAssertEqual(keyframe.repeatCount, .infinity)
	}

	func testPeriodsAreDistinctSoConcurrentPetsDoNotLockIntoUnison() {
		let periods = [PlatformAttribution.claudeCode, .codex, .cursor, .vscode, .antigravity]
			.compactMap { platform -> CFTimeInterval? in
				switch PlatformChipAnimation.forPlatform(platform) {
				case let .spin(period, _): period
				case let .breathe(period, _): period
				case .none: nil
				}
			}
		XCTAssertEqual(periods.count, 5)
		XCTAssertEqual(Set(periods).count, 5, "two pets working at once should not visibly tick together")
	}

	func testDefaultStarHasNoAnimation() {
		// The star shows while nothing is driving the pet, so it has no in-flight
		// state of its own to signal.
		XCTAssertNil(PlatformChipAnimation.forPlatform(.default))
	}

	func testSpinWithPulseGroupsRotationAndScale() throws {
		let animation = PlatformChipAnimation.spin(period: 2, scalePulse: 0.5).makeAnimation()
		let group = try XCTUnwrap(animation as? CAAnimationGroup)
		let keyPaths = (group.animations ?? []).compactMap { ($0 as? CAPropertyAnimation)?.keyPath }
		XCTAssertEqual(keyPaths, ["transform.rotation.z", "transform.scale"])
		XCTAssertEqual(group.repeatCount, .infinity)
	}

	// MARK: - Rotation pivot

	func testGlyphPivotsAboutItsOwnCentreNotTheDefaultCornerAnchor() throws {
		// AppKit hands a layer-backed NSView an anchorPoint of (0, 0). Left alone,
		// every rotation is applied about the glyph's bottom-left corner, so the
		// mark orbits its own corner instead of spinning in place — the shape looks
		// right but the centre of mass swings on a circle roughly 0.7x the glyph's
		// width. Symmetry-axis choice cannot compensate for this.
		let (chip, window) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		window.contentView?.layoutSubtreeIfNeeded()

		let glyph = try XCTUnwrap(chip.subviews.compactMap { $0 as? NSImageView }.first)
		let layer = try XCTUnwrap(glyph.layer)
		// Snapshot the rendered rect *before* re-anchoring, so the "layout is
		// untouched" claim is checked against a real prior value. Comparing
		// `layer.frame` to `glyph.frame` after the fact cannot fail: frame is
		// derived from position/bounds/anchorPoint, so it merely restates the
		// position assertion.
		let renderedBefore = layer.frame
		layer.anchorPoint = .zero
		layer.position = glyph.frame.origin
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		window.contentView?.layoutSubtreeIfNeeded()

		XCTAssertEqual(layer.anchorPoint, CGPoint(x: 0.5, y: 0.5), "rotation must pivot about the glyph centre")
		XCTAssertEqual(
			layer.position, CGPoint(x: glyph.frame.midX, y: glyph.frame.midY),
			"re-anchoring must be compensated by position or the glyph jumps")
		XCTAssertEqual(
			layer.frame, renderedBefore,
			"the visible frame must be untouched — only the pivot moves, not the layout")
	}

	// MARK: - Chip lifecycle

	/// Hosts the chip in a real window — `PlatformChipView` refuses to animate
	/// while unparented, so an off-window chip would make every case below
	/// vacuously pass.
	private func makeHostedChip() -> (PlatformChipView, NSWindow) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
			styleMask: [.borderless], backing: .buffered, defer: false)
		let chip = PlatformChipView(frame: .zero)
		chip.translatesAutoresizingMaskIntoConstraints = false
		window.contentView?.addSubview(chip)
		NSLayoutConstraint.activate([
			chip.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
			chip.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
		])
		// Give the glyph real geometry up front: the chip refuses to animate against
		// a zero-sized layer, so without this every case below would pass vacuously.
		window.contentView?.layoutSubtreeIfNeeded()
		return (chip, window)
	}

	private func metrics() -> GateBadgeLayout.Metrics {
		GateBadgeLayout.metrics(for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160))
	}

	private func animationKeys(_ chip: PlatformChipView) -> [String] {
		let glyph = chip.subviews.compactMap { $0 as? NSImageView }.first
		return glyph?.layer?.animationKeys() ?? []
	}

	func testDoesNotAnimateBeforeTheGlyphHasBeenLaidOut() {
		// A pool tick can reach `configure` before the first layout pass — most
		// visibly when a mode switch spawns a fresh window mid-turn. Installing a
		// rotation against a zero-sized layer renders about the wrong point, which
		// reads as the mark orbiting instead of spinning, so the animation waits.
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
			styleMask: [.borderless], backing: .buffered, defer: false)
		let chip = PlatformChipView(frame: .zero)
		chip.translatesAutoresizingMaskIntoConstraints = false
		window.contentView?.addSubview(chip)
		NSLayoutConstraint.activate([
			chip.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
			chip.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
		])

		chip.configure(
			platform: .cursor, metrics: metrics(), inFlight: true,
			animationSettings: .init(isEnabled: true))
		XCTAssertTrue(
			animationKeys(chip).isEmpty,
			"a zero-sized glyph must not start animating")

		window.contentView?.layoutSubtreeIfNeeded()
		XCTAssertEqual(
			animationKeys(chip).count, 1,
			"layout must install the deferred animation without waiting for another poll tick")
	}

	func testDisabledToggleNeverAnimatesEvenInFlight() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: false))
		XCTAssertTrue(animationKeys(chip).isEmpty, "default-off must leave the chip completely static")
	}

	func testEnabledButIdleDoesNotAnimate() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: false, animationSettings: .init(isEnabled: true))
		XCTAssertTrue(animationKeys(chip).isEmpty, "the animation signals in-flight, not merely enabled")
	}

	func testEnabledAndInFlightAnimates() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)
	}

	func testAnimationStopsWhenFlightEnds() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: false, animationSettings: .init(isEnabled: true))
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}

	func testTogglingOffMidFlightStopsTheRunningAnimation() {
		// The case most likely to be missed by hand: the switch is flipped off
		// while a prompt is still running, so nothing else re-renders the chip.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: false))
		XCTAssertTrue(animationKeys(chip).isEmpty, "toggling off mid-flight must stop a running animation")
	}

	func testRepeatedIdenticalConfigureDoesNotRestartTheAnimation() {
		// `configure` runs every poll tick; re-adding the animation each time
		// would reset it to frame zero and read as a stutter.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .codex, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		let first = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")

		for _ in 0..<5 {
			chip.configure(platform: .codex, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		}
		let latest = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")
		XCTAssertTrue(first === latest, "an unchanged animation must be left running, not re-added")
	}

	func testSwitchingPlatformMidFlightSwapsTheAnimation() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		let spin = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")

		XCTAssertTrue(spin is CAAnimationGroup, "Cursor spins, so rotation is grouped with the breathe")

		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		let breathe = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")
		XCTAssertFalse(spin === breathe, "a different platform must install its own animation")
		XCTAssertTrue(
			breathe is CAKeyframeAnimation,
			"VS Code breathes only — a bare scale keyframe, no rotation to tumble it")
	}

	func testLeavingTheWindowStopsTheAnimation() {
		// AppKit keeps a layer animating after its view is unparented, so an
		// off-screen chip would otherwise burn CPU invisibly.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.removeFromSuperview()
		XCTAssertTrue(animationKeys(chip).isEmpty, "an unparented chip must not keep animating")
	}

	func testReturningToAWindowRestoresTheAnimation() {
		let (chip, window) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		chip.removeFromSuperview()
		XCTAssertTrue(animationKeys(chip).isEmpty)

		window.contentView?.addSubview(chip)
		XCTAssertEqual(animationKeys(chip).count, 1, "re-parenting mid-flight must resume the animation")
	}

	func testAnimationIsReinstalledAfterCoreAnimationDropsIt() {
		// Ordering the badge panel out (`hideAnimationBadge`) leaves the chip in
		// its window but detaches the layer tree, so Core Animation drops the
		// running animation without `viewDidMoveToWindow` ever firing. Re-showing
		// mid-turn then re-configures with an unchanged descriptor, so the diff
		// alone would decide there was nothing to do and the chip would stay
		// static for the rest of the turn.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?.removeAllAnimations()
		XCTAssertTrue(animationKeys(chip).isEmpty, "precondition: the animation is gone")

		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(
			animationKeys(chip).count, 1,
			"a re-configure must restore an animation the system dropped underneath us")
	}

	func testShippedReducedMotionDefaultReadsTheSystemSetting() {
		// Every other Reduce Motion test injects the override, so without this the
		// production closure never runs: reading the wrong property, or wiring the
		// observer to `NotificationCenter.default` (workspace notifications are not
		// posted there), would ship with the suite fully green.
		XCTAssertEqual(
			PlatformChipView.systemPrefersReducedMotion(),
			NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
	}

	func testOverrideIsAbsentByDefaultSoProductionUsesTheSystemSetting() {
		// Guards the seam itself: production must never ship with an override
		// installed. `setUp` sets one, so consult the value it saved.
		XCTAssertNil(savedReducedMotionOverride)
	}

	func testSuspendingStopsTheAnimationWhileTheBadgeIsOrderedOut() {
		// Ordering the badge panel out leaves `window` set and Core Animation keeps
		// evaluating the animation, so the chip needs an explicit stand-down or a
		// hidden pet spins forever on an invisible layer.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.setAnimationSuspended(true)
		XCTAssertTrue(animationKeys(chip).isEmpty, "a hidden badge must not keep animating")

		chip.setAnimationSuspended(false)
		XCTAssertEqual(animationKeys(chip).count, 1, "unhiding mid-turn must resume")
	}

	func testSuspendedChipStaysStaticAcrossPollTicks() {
		// `configure` runs every tick while the pet is hidden; none of those may
		// reinstall the animation.
		let (chip, _) = makeHostedChip()
		chip.setAnimationSuspended(true)
		for _ in 0..<5 {
			chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		}
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}

	func testReduceMotionSuppressesTheAnimation() {
		// System Settings > Accessibility > Display > Reduce Motion must win over
		// the in-app toggle — the two live in different places, and someone who
		// set the system one has no reason to expect a per-app switch also needs
		// turning off.
		PlatformChipView.reducedMotionOverrideForTesting = { true }
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}

	func testTurningOnReduceMotionMidFlightStopsARunningAnimation() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertEqual(animationKeys(chip).count, 1)

		PlatformChipView.reducedMotionOverrideForTesting = { true }
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertTrue(animationKeys(chip).isEmpty, "enabling Reduce Motion must stop a running animation")
	}

	func testDefaultPlatformStaysStaticEvenWhenEnabledAndInFlight() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .default, metrics: metrics(), inFlight: true, animationSettings: .init(isEnabled: true))
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}
}

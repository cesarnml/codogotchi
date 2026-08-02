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
	override func setUp() {
		super.setUp()
		PlatformChipView.prefersReducedMotion = { false }
	}

	override func tearDown() {
		PlatformChipView.prefersReducedMotion = {
			NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		}
		super.tearDown()
	}

	// MARK: - Descriptor table

	func testFlipAxisFollowsEachMarksLineOfSymmetry() {
		// A flip is only legible on a mark that mirrors about the rotation axis,
		// since the layer is double-sided and reuses one asset for both faces.
		XCTAssertEqual(
			PlatformChipAnimation.forPlatform(.vscode),
			.flip(axis: .horizontal, period: 4.0, turns: 2),
			"the VS Code ribbon mirrors about the horizontal")
		XCTAssertEqual(
			PlatformChipAnimation.forPlatform(.antigravity),
			.flip(axis: .vertical, period: 4.0, turns: 2),
			"the Antigravity arch mirrors about the vertical")
	}

	func testRadiallySymmetricMarksSpinInPlane() {
		XCTAssertEqual(PlatformChipAnimation.forPlatform(.cursor), .spin(period: 2.8, scalePulse: nil))
		XCTAssertEqual(PlatformChipAnimation.forPlatform(.claudeCode), .spin(period: 3.2, scalePulse: nil))
		if case let .spin(_, scalePulse) = PlatformChipAnimation.forPlatform(.codex) {
			XCTAssertEqual(scalePulse, 0.72, "Codex shrinks and regrows while spinning")
		} else {
			XCTFail("Codex should spin")
		}
	}

	func testDefaultStarHasNoAnimation() {
		// The star shows while nothing is driving the pet, so it has no in-flight
		// state of its own to signal.
		XCTAssertNil(PlatformChipAnimation.forPlatform(.default))
	}

	func testAxisKeyPathsRotateAboutInPlaneAxes() {
		XCTAssertEqual(PlatformChipAnimation.Axis.horizontal.keyPath, "transform.rotation.x")
		XCTAssertEqual(PlatformChipAnimation.Axis.vertical.keyPath, "transform.rotation.y")
	}

	func testFlipReturnsToZeroSoTheRepeatIsSeamless() throws {
		let animation = PlatformChipAnimation.flip(axis: .vertical, period: 4, turns: 2).makeAnimation()
		let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
		let values = try XCTUnwrap(keyframe.values).map { ($0 as? NSNumber)?.doubleValue }
		XCTAssertEqual(values.first, 0)
		XCTAssertEqual(values.last, 0, "a flip must unwind to its start or the loop visibly jumps")
		XCTAssertEqual(try XCTUnwrap(values[1]), -2 * Double.pi * 2, accuracy: 0.0001)
		XCTAssertEqual(keyframe.repeatCount, .infinity)
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
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		window.contentView?.layoutSubtreeIfNeeded()

		let glyph = try XCTUnwrap(chip.subviews.compactMap { $0 as? NSImageView }.first)
		let layer = try XCTUnwrap(glyph.layer)
		XCTAssertEqual(layer.anchorPoint, CGPoint(x: 0.5, y: 0.5), "rotation must pivot about the glyph centre")
		XCTAssertEqual(
			layer.position, CGPoint(x: glyph.frame.midX, y: glyph.frame.midY),
			"re-anchoring must be compensated by position or the glyph jumps")
		XCTAssertEqual(
			layer.frame, glyph.frame,
			"the visible frame must be untouched — only the pivot moves, not the layout")
	}

	func testPerspectiveVanishingPointIsCentredOnTheChip() throws {
		// `sublayerTransform` is applied about the chip's own (0, 0) anchor, so a
		// bare perspective matrix puts the vanishing point at the chip's corner and
		// skews each flip off to one side. The centred sandwich shows up as
		// z-dependent shear (m31/m32) with no static translation (m41/m42).
		let (chip, window) = makeHostedChip()
		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationEnabled: true)
		window.contentView?.layoutSubtreeIfNeeded()

		let sublayer = try XCTUnwrap(chip.layer).sublayerTransform
		XCTAssertNotEqual(sublayer.m34, 0, "flips need perspective or they read as a flat squash")
		XCTAssertEqual(sublayer.m41, 0, accuracy: 0.0001, "a resting glyph must not be displaced")
		XCTAssertEqual(sublayer.m42, 0, accuracy: 0.0001)
		XCTAssertEqual(
			sublayer.m31, sublayer.m34 * chip.bounds.midX, accuracy: 0.0001,
			"vanishing point should sit on the chip's centre, not its corner")
		XCTAssertEqual(sublayer.m32, sublayer.m34 * chip.bounds.midY, accuracy: 0.0001)
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
		return (chip, window)
	}

	private func metrics() -> GateBadgeLayout.Metrics {
		GateBadgeLayout.metrics(for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160))
	}

	private func animationKeys(_ chip: PlatformChipView) -> [String] {
		let glyph = chip.subviews.compactMap { $0 as? NSImageView }.first
		return glyph?.layer?.animationKeys() ?? []
	}

	func testDisabledToggleNeverAnimatesEvenInFlight() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: false)
		XCTAssertTrue(animationKeys(chip).isEmpty, "default-off must leave the chip completely static")
	}

	func testEnabledButIdleDoesNotAnimate() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: false, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty, "the animation signals in-flight, not merely enabled")
	}

	func testEnabledAndInFlightAnimates() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(animationKeys(chip).count, 1)
	}

	func testAnimationStopsWhenFlightEnds() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: false, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}

	func testTogglingOffMidFlightStopsTheRunningAnimation() {
		// The case most likely to be missed by hand: the switch is flipped off
		// while a prompt is still running, so nothing else re-renders the chip.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationEnabled: false)
		XCTAssertTrue(animationKeys(chip).isEmpty, "toggling off mid-flight must stop a running animation")
	}

	func testRepeatedIdenticalConfigureDoesNotRestartTheAnimation() {
		// `configure` runs every poll tick; re-adding the animation each time
		// would reset it to frame zero and read as a stutter.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .codex, metrics: metrics(), inFlight: true, animationEnabled: true)
		let first = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")

		for _ in 0..<5 {
			chip.configure(platform: .codex, metrics: metrics(), inFlight: true, animationEnabled: true)
		}
		let latest = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")
		XCTAssertTrue(first === latest, "an unchanged animation must be left running, not re-added")
	}

	func testSwitchingPlatformMidFlightSwapsTheAnimation() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		let spin = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")

		chip.configure(platform: .vscode, metrics: metrics(), inFlight: true, animationEnabled: true)
		let flip = chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?
			.animation(forKey: "platformChipLogo")
		XCTAssertFalse(spin === flip, "a different platform must install its own animation")
		XCTAssertTrue(flip is CAKeyframeAnimation, "VS Code flips rather than spinning")
	}

	func testLeavingTheWindowStopsTheAnimation() {
		// AppKit keeps a layer animating after its view is unparented, so an
		// off-screen chip would otherwise burn CPU invisibly.
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.removeFromSuperview()
		XCTAssertTrue(animationKeys(chip).isEmpty, "an unparented chip must not keep animating")
	}

	func testReturningToAWindowRestoresTheAnimation() {
		let (chip, window) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
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
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(animationKeys(chip).count, 1)

		chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?.removeAllAnimations()
		XCTAssertTrue(animationKeys(chip).isEmpty, "precondition: the animation is gone")

		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(
			animationKeys(chip).count, 1,
			"a re-configure must restore an animation the system dropped underneath us")
	}

	func testReduceMotionSuppressesTheAnimation() {
		// System Settings > Accessibility > Display > Reduce Motion must win over
		// the in-app toggle — the two live in different places, and someone who
		// set the system one has no reason to expect a per-app switch also needs
		// turning off.
		PlatformChipView.prefersReducedMotion = { true }
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}

	func testTurningOnReduceMotionMidFlightStopsARunningAnimation() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertEqual(animationKeys(chip).count, 1)

		PlatformChipView.prefersReducedMotion = { true }
		chip.configure(platform: .cursor, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty, "enabling Reduce Motion must stop a running animation")
	}

	func testDefaultPlatformStaysStaticEvenWhenEnabledAndInFlight() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .default, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}
}

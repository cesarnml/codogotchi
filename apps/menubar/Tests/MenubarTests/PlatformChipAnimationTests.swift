import AppKit
import XCTest

@testable import Codogotchi

/// Covers the animation descriptor table and — more importantly — the chip's
/// add/remove lifecycle. A leaked `CAAnimation` is invisible rather than
/// obviously broken, so the failure mode these guard is idle CPU burn on an
/// always-running menubar app, not a wrong-looking badge.
final class PlatformChipAnimationTests: XCTestCase {

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

	// MARK: - Chip lifecycle

	/// Hosts the chip in a real window — `PlatformChipView` refuses to animate
	/// while unparented, so an off-window chip would make every case below
	/// vacuously pass.
	private func makeHostedChip() -> (PlatformChipView, NSWindow) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
			styleMask: [.borderless], backing: .buffered, defer: false)
		let chip = PlatformChipView(frame: .zero)
		window.contentView?.addSubview(chip)
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

	func testDefaultPlatformStaysStaticEvenWhenEnabledAndInFlight() {
		let (chip, _) = makeHostedChip()
		chip.configure(platform: .default, metrics: metrics(), inFlight: true, animationEnabled: true)
		XCTAssertTrue(animationKeys(chip).isEmpty)
	}
}

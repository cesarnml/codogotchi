import AppKit
import XCTest

@testable import Codogotchi

/// Pins `AttentionBubbleLayout.frame` — the attention-bubble anchor math both
/// Own mode (`FloatingPetPanelController`) and Minimalist mode
/// (`MinimalistPanelController`) call with different `leadingX`/`bottomAnchorY`
/// inputs. Written ahead of P17.03's chrome-flock coordinator: this math
/// previously lived as a `private enum BubbleLayout` inside
/// `AttentionBubblePanel.swift` with no dedicated test coverage, unlike its
/// four sibling panel types (`AnimationBadgeLayout`, `GateBadgeLayout`,
/// `SpeechBubbleLayout`, `RPGHUDLayout`), which are already pure and tested.
final class AttentionBubbleLayoutTests: XCTestCase {
	private let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

	/// Own mode anchors `leadingX` to the animation badge panel's own `minX`
	/// (the platform chip's leading edge) — not centered on the pet frame.
	func testFrameIsLeadingAlignedToLeadingX() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let leadingX: CGFloat = 420
		let frame = AttentionBubbleLayout.frame(
			relativeTo: petFrame, leadingX: leadingX, bottomAnchorY: petFrame.minY, visibleFrame: visibleFrame)
		XCTAssertEqual(frame.minX, leadingX, accuracy: 0.01)
	}

	/// The bubble sits `gapBelowPet` below `bottomAnchorY` — the chrome's own
	/// bottom edge (animation badge panel's `minY` in Own mode, the strip's
	/// `minY` in Minimalist mode), not necessarily `petFrame.minY`.
	func testFrameSitsGapBelowPetBelowTheBottomAnchor() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let bottomAnchorY: CGFloat = 280
		let frame = AttentionBubbleLayout.frame(
			relativeTo: petFrame, leadingX: petFrame.minX, bottomAnchorY: bottomAnchorY, visibleFrame: visibleFrame)
		XCTAssertEqual(
			frame.maxY,
			bottomAnchorY - AttentionBubbleLayout.gapBelowPet,
			accuracy: 0.01)
	}

	func testFrameHeightMatchesTheFixedConstant() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let frame = AttentionBubbleLayout.frame(
			relativeTo: petFrame, leadingX: petFrame.minX, bottomAnchorY: petFrame.minY, visibleFrame: visibleFrame)
		XCTAssertEqual(frame.height, AttentionBubbleLayout.height, accuracy: 0.01)
	}

	/// Width comes from the shared `AttentionBubbleLayoutMetrics.bubbleWidth`
	/// helper (also used by `SpeechBubbleLayout`), not a local computation —
	/// so it grows with pet width within the shared min/max bounds.
	func testWidthGrowsWithPetWidthWithinSharedMetricsBounds() {
		let narrowPet = CGRect(x: 0, y: 0, width: 96, height: 96)
		let widePet = CGRect(x: 0, y: 0, width: 256, height: 256)
		let narrowFrame = AttentionBubbleLayout.frame(
			relativeTo: narrowPet, leadingX: 0, bottomAnchorY: narrowPet.minY, visibleFrame: visibleFrame)
		let wideFrame = AttentionBubbleLayout.frame(
			relativeTo: widePet, leadingX: 0, bottomAnchorY: widePet.minY, visibleFrame: visibleFrame)
		XCTAssertLessThan(narrowFrame.width, wideFrame.width)
		XCTAssertEqual(
			narrowFrame.width,
			AttentionBubbleLayoutMetrics.bubbleWidth(forPetWidth: narrowPet.width),
			accuracy: 0.01)
	}

	func testFrameNeverExceedsTheVisibleFrameBounds() {
		// Pet frame + anchors near the very top-left corner: an unclamped
		// bubble would spill off the top and left edges of the screen.
		let petFrame = CGRect(x: 0, y: 20, width: 160, height: 160)
		let frame = AttentionBubbleLayout.frame(
			relativeTo: petFrame, leadingX: -50, bottomAnchorY: 4, visibleFrame: visibleFrame)
		XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
		XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
		XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
		XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
	}
}

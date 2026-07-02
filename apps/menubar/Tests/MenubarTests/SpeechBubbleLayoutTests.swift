import XCTest

@testable import Codogotchi

final class SpeechBubbleLayoutTests: XCTestCase {
	private let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

	func testFrameIsHorizontallyCenteredOnThePetFrame() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(relativeTo: petFrame, visibleFrame: visibleFrame)
		XCTAssertEqual(frame.midX, petFrame.midX, accuracy: 0.5)
	}

	/// The tail's point (bottom of the panel) must sit `topGapToCharacter`
	/// above the pet frame's top edge — a thought bubble anchored near the
	/// character's head, not `AttentionBubblePanel`'s below-the-pet anchor.
	func testTailPointSitsAboveThePetFramesTopEdge() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(relativeTo: petFrame, visibleFrame: visibleFrame)
		XCTAssertEqual(
			frame.minY, petFrame.maxY - SpeechBubbleLayout.topGapToCharacter, accuracy: 0.5)
	}

	func testFrameNeverExceedsTheVisibleFrameBounds() {
		// Pet frame near the very top-left corner: an unclamped bubble would
		// spill off the top and left edges of the screen.
		let petFrame = CGRect(x: 0, y: 780, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(relativeTo: petFrame, visibleFrame: visibleFrame)
		XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
		XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
		XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
		XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
	}

	func testWidthGrowsWithPetWidthWithinBounds() {
		let narrowPet = CGRect(x: 0, y: 0, width: 96, height: 96)
		let widePet = CGRect(x: 0, y: 0, width: 256, height: 256)
		let narrowFrame = SpeechBubbleLayout.frame(relativeTo: narrowPet, visibleFrame: visibleFrame)
		let wideFrame = SpeechBubbleLayout.frame(relativeTo: widePet, visibleFrame: visibleFrame)
		XCTAssertLessThan(narrowFrame.width, wideFrame.width)
	}

	/// The full panel height must reserve room for the tail's protruding
	/// lower half below the body — without this the tail would be clipped at
	/// the window edge instead of visibly poking out under the bubble.
	func testHeightReservesRoomForTheProtrudingTail() {
		XCTAssertEqual(SpeechBubbleLayout.height, SpeechBubbleLayout.bodyHeight + SpeechBubbleLayout.tailVisibleHeight)
	}
}

import AppKit
import XCTest

@testable import Codogotchi

final class SpeechBubbleLayoutTests: XCTestCase {
	private let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

	func testFrameIsHorizontallyCenteredOnThePetFrame() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(aboveFloatingPetFrame: petFrame, visibleFrame: visibleFrame)
		XCTAssertEqual(frame.midX, petFrame.midX, accuracy: 0.5)
	}

	/// Own/Combined mode: the tail's point (bottom of the panel) must dip
	/// `tipInsetIntoPetFrame` *inside* the pet window's top edge — pointing at
	/// the character's head through the sprite cell's transparent headroom,
	/// not `AttentionBubblePanel`'s below-the-pet anchor.
	func testOwnModeTailPointDipsInsideThePetFramesTopEdge() {
		let petFrame = CGRect(x: 400, y: 300, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(aboveFloatingPetFrame: petFrame, visibleFrame: visibleFrame)
		XCTAssertEqual(
			frame.minY,
			petFrame.maxY - SpeechBubbleLayout.tipInsetIntoPetFrame,
			accuracy: 0.5)
	}

	/// Minimalist mode: the strip panel's frame carries padding above its
	/// drawn chip row, so the tail's point dips `tipInsetIntoStrip` inside
	/// the frame's top edge to land just above the visible chrome.
	func testMinimalistModeTailPointDipsInsideTheStripsTopEdge() {
		let stripFrame = CGRect(x: 400, y: 300, width: 220, height: 64)
		let frame = SpeechBubbleLayout.frame(aboveMinimalistStrip: stripFrame, visibleFrame: visibleFrame)
		XCTAssertEqual(
			frame.minY,
			stripFrame.maxY - SpeechBubbleLayout.tipInsetIntoStrip,
			accuracy: 0.5)
	}

	func testFrameNeverExceedsTheVisibleFrameBounds() {
		// Pet frame near the very top-left corner: an unclamped bubble would
		// spill off the top and left edges of the screen.
		let petFrame = CGRect(x: 0, y: 780, width: 160, height: 160)
		let frame = SpeechBubbleLayout.frame(aboveFloatingPetFrame: petFrame, visibleFrame: visibleFrame)
		XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
		XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
		XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
		XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
	}

	func testWidthGrowsWithPetWidthWithinBounds() {
		let narrowPet = CGRect(x: 0, y: 0, width: 96, height: 96)
		let widePet = CGRect(x: 0, y: 0, width: 256, height: 256)
		let narrowFrame = SpeechBubbleLayout.frame(aboveFloatingPetFrame: narrowPet, visibleFrame: visibleFrame)
		let wideFrame = SpeechBubbleLayout.frame(aboveFloatingPetFrame: widePet, visibleFrame: visibleFrame)
		XCTAssertLessThan(narrowFrame.width, wideFrame.width)
	}

	/// The full panel height must reserve room for the tail's protruding
	/// lower half below the body — without this the tail would be clipped at
	/// the window edge instead of visibly poking out under the bubble.
	func testHeightReservesRoomForTheProtrudingTail() {
		XCTAssertEqual(SpeechBubbleLayout.height, SpeechBubbleLayout.bodyHeight + SpeechBubbleLayout.tailVisibleHeight)
	}

	/// The conflict message must wrap within the two-line budget at the
	/// narrowest bubble the layout produces (`minBubbleWidth` — the Minimalist
	/// strip's bubble). A third line has no room above the pinned Settings
	/// action link and gets clipped mid-sentence.
	func testConflictMessageFitsTwoLinesAtTheNarrowestBubbleWidth() {
		let contentWidth = AttentionBubbleLayoutMetrics.minBubbleWidth - SpeechBubbleLayout.hPad * 2
		let font = NSFont.systemFont(ofSize: 11)
		let wrapped = (SpeechBubbleConflictCopy.message as NSString).boundingRect(
			with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin],
			attributes: [.font: font]
		)
		let singleLine = ("X" as NSString).boundingRect(
			with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin],
			attributes: [.font: font]
		)
		XCTAssertLessThanOrEqual(wrapped.height, singleLine.height * 2 + 0.5)
	}
}

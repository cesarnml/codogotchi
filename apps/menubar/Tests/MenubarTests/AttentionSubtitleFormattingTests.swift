import XCTest
@testable import Codogotchi

final class AttentionSubtitleFormattingTests: XCTestCase {
	private let font = NSFont.systemFont(ofSize: 10)

	func testAddsRePrefixWhenExcerptFits() {
		let width = AttentionBubbleLayoutMetrics.subtitleContentWidth(forPetWidth: 256)
		let line = AttentionSubtitleFormatting.truncatedReplyLine(
			excerpt: "verify and commit",
			fittingWidth: width,
			font: font
		)
		XCTAssertEqual(line, "Re: verify and commit")
	}

	func testLargerPetFitsMoreCharactersThanSmallestBubble() {
		let smallWidth = AttentionBubbleLayoutMetrics.subtitleContentWidth(forPetWidth: 96)
		let largeWidth = AttentionBubbleLayoutMetrics.subtitleContentWidth(forPetWidth: 256)
		let prompt =
			"help me brainstorm a good prefix to attention.summary for the floating pet"
		let small = AttentionSubtitleFormatting.truncatedReplyLine(
			excerpt: prompt,
			fittingWidth: smallWidth,
			font: font
		)
		let large = AttentionSubtitleFormatting.truncatedReplyLine(
			excerpt: prompt,
			fittingWidth: largeWidth,
			font: font
		)
		XCTAssertTrue(small.hasPrefix("Re: "))
		XCTAssertTrue(large.hasPrefix("Re: "))
		XCTAssertGreaterThan(large.count, small.count)
	}

	func testEmptyExcerptReturnsEmptyString() {
		XCTAssertEqual(
			AttentionSubtitleFormatting.truncatedReplyLine(
				excerpt: "   ",
				fittingWidth: 200,
				font: font
			),
			""
		)
	}
}

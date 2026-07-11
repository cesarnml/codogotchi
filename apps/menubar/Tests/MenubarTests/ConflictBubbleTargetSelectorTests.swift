import XCTest

@testable import Codogotchi

/// P15.08 behavior contract for the pure conflict-bubble target selector.
/// `firstSeenAt` is pre-filtered by the caller to a blocked origin's
/// currently-rendered session-keyed window keys; the selector only picks
/// among those candidates.
final class ConflictBubbleTargetSelectorTests: XCTestCase {

	func testTargetsTheEarliestFirstSeenKeyAmongRenderedActiveSessions() {
		let firstSeenAt: [WindowKey: Date] = [
			"claude_code:b": Date(timeIntervalSince1970: 200),
			"claude_code:a": Date(timeIntervalSince1970: 100),
			"claude_code:c": Date(timeIntervalSince1970: 300),
		]

		let target = ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: firstSeenAt)

		XCTAssertEqual(
			target, "claude_code:a",
			"the longest-lived (earliest first-seen) session must be the bubble's anchor")
	}

	func testReturnsNilForEmptyCandidates() {
		XCTAssertNil(ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: [:]))
	}

	func testSingleCandidateIsItsOwnTarget() {
		let firstSeenAt: [WindowKey: Date] = ["claude_code:only": Date()]

		XCTAssertEqual(
			ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: firstSeenAt),
			"claude_code:only")
	}

	func testDoesNotHopWhenTheLongestLivedSessionIsStillRendered() {
		// Same first-seen map queried twice must return the same target — the
		// selector is pure, so stability across ticks falls out of the caller
		// re-filtering to the same currently-rendered set each time.
		let firstSeenAt: [WindowKey: Date] = [
			"codex:x": Date(timeIntervalSince1970: 50),
			"codex:y": Date(timeIntervalSince1970: 75),
		]

		let first = ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: firstSeenAt)
		let second = ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt: firstSeenAt)

		XCTAssertEqual(first, "codex:x")
		XCTAssertEqual(first, second)
	}
}

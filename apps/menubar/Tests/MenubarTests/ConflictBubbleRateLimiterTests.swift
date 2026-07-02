import XCTest

@testable import Codogotchi

/// P15.08 behavior contract for the pure per-platform conflict-bubble rate
/// limiter. Exercised directly with no pool/window state — `shouldShow` and
/// `recordShown` are the entire surface `FloatingPetWindowPool` consumes.
final class ConflictBubbleRateLimiterTests: XCTestCase {

	func testFirstBlockFires() {
		let limiter = ConflictBubbleRateLimiter()
		let now = Date()

		XCTAssertTrue(
			limiter.shouldShow(origin: "claude_code", now: now),
			"a platform with no prior fire must be allowed to show")
	}

	func testSecondBlockWithinTheHourDoesNotFire() {
		var limiter = ConflictBubbleRateLimiter()
		let t0 = Date()
		limiter.recordShown(origin: "claude_code", now: t0)

		let t1 = t0.addingTimeInterval(30 * 60)

		XCTAssertFalse(
			limiter.shouldShow(origin: "claude_code", now: t1),
			"a re-blocked attempt within the hour must not re-fire")
	}

	func testBlockAfterTheHourElapsesFiresAgain() {
		var limiter = ConflictBubbleRateLimiter()
		let t0 = Date()
		limiter.recordShown(origin: "claude_code", now: t0)

		let t1 = t0.addingTimeInterval(3600 + 1)

		XCTAssertTrue(
			limiter.shouldShow(origin: "claude_code", now: t1),
			"a block after the hour elapses must fire again")
	}

	func testTwoPlatformsRateLimitIndependently() {
		var limiter = ConflictBubbleRateLimiter()
		let t0 = Date()
		limiter.recordShown(origin: "claude_code", now: t0)

		XCTAssertFalse(
			limiter.shouldShow(origin: "claude_code", now: t0.addingTimeInterval(60)),
			"claude_code just fired and must stay rate-limited")
		XCTAssertTrue(
			limiter.shouldShow(origin: "codex", now: t0.addingTimeInterval(60)),
			"codex's rate limit must be unaffected by claude_code firing")
	}
}

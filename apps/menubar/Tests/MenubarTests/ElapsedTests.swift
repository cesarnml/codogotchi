import XCTest

@testable import Codogotchi

/// `IdleElapsed` is the idle half of the shared chip slot: a pure function over
/// the slice's own `updated_at`, with no tracker and no scene. These cover the
/// gate (idle only), the anchor, and the two ways the stamp can be unusable.
final class IdleElapsedTests: XCTestCase {
	private let stamp = "2026-08-03T10:00:00.000+00:00"
	private var anchor: Date {
		StateJsonReader.parseISO8601Date(stamp)!
	}

	func testIdleSliceReportsElapsedSinceUpdatedAt() throws {
		let presentation = try XCTUnwrap(
			IdleElapsed.presentation(
				activityState: .idle,
				updatedAt: stamp,
				now: anchor.addingTimeInterval(47 * 60)
			))

		XCTAssertEqual(presentation.label, "47:00")
		XCTAssertEqual(presentation.kind, .idle)
		XCTAssertTrue(presentation.isRunning)
	}

	/// Long-quiet sessions are the common case for this chip, so the hour/day
	/// rollovers `compactLabel` already implements matter more here than they
	/// ever did for a prompt turn.
	func testLongIdleRollsOverToHoursAndDays() throws {
		let hours = try XCTUnwrap(
			IdleElapsed.presentation(
				activityState: .idle, updatedAt: stamp,
				now: anchor.addingTimeInterval(2 * 3600 + 15 * 60)))
		XCTAssertEqual(hours.label, "2h 15m")

		// Hours stay hours well past a day — `compactLabel` only switches to the
		// day form at 100h, which a quiet session can genuinely reach.
		let manyHours = try XCTUnwrap(
			IdleElapsed.presentation(
				activityState: .idle, updatedAt: stamp,
				now: anchor.addingTimeInterval(26 * 3600)))
		XCTAssertEqual(manyHours.label, "26h 0m")

		let days = try XCTUnwrap(
			IdleElapsed.presentation(
				activityState: .idle, updatedAt: stamp,
				now: anchor.addingTimeInterval(101 * 3600)))
		XCTAssertEqual(days.label, "4d 5h")
	}

	/// Every non-idle state has a turn clock in the slot instead — this side must
	/// stay silent so the two can never contend.
	func testNonIdleStatesProduceNoPresentation() {
		for state: ActivityState in [.thinking, .standby, .errored, .implementing, .waitingForInput] {
			XCTAssertNil(
				IdleElapsed.presentation(
					activityState: state, updatedAt: stamp, now: anchor.addingTimeInterval(60)),
				"\(state) must not produce an idle chip")
		}
	}

	func testMissingOrUnparseableStampProducesNoChip() {
		XCTAssertNil(
			IdleElapsed.presentation(activityState: .idle, updatedAt: nil, now: anchor))
		XCTAssertNil(
			IdleElapsed.presentation(activityState: .idle, updatedAt: "not-a-date", now: anchor))
	}

	/// A slice stamped in the future (clock skew between the hook's host and the
	/// renderer) must clamp to zero rather than render a negative label.
	func testFutureStampClampsToZero() throws {
		let presentation = try XCTUnwrap(
			IdleElapsed.presentation(
				activityState: .idle, updatedAt: stamp, now: anchor.addingTimeInterval(-300)))
		XCTAssertEqual(presentation.label, "0:00")
	}
}

/// The chip slot carries a `kind` so the glyph and any future third clock are
/// exhaustively switched rather than inferred.
final class ElapsedKindTests: XCTestCase {
	func testGlyphsAreDistinctPerKind() {
		XCTAssertEqual(ElapsedKind.turn.symbolName, "timer")
		XCTAssertEqual(ElapsedKind.idle.symbolName, "zzz")
		XCTAssertNotEqual(ElapsedKind.turn.symbolName, ElapsedKind.idle.symbolName)
	}

	/// Both symbols must actually resolve on the deployment target — a typo'd SF
	/// Symbol name fails silently at runtime (no image, bare label).
	func testBothSymbolsResolveOnThisPlatform() {
		for kind: ElapsedKind in [.turn, .idle] {
			XCTAssertNotNil(
				NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil),
				"SF Symbol \(kind.symbolName) did not resolve")
		}
	}

	func testTurnTrackerAlwaysReportsTurnKind() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-08-03T10:00:00.000+00:00",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)
		XCTAssertEqual(tracker.presentation()?.kind, .turn)
	}
}

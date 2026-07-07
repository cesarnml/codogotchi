import XCTest

@testable import Codogotchi

final class PromptTimerTests: XCTestCase {
	func testSessionStartBeginsTimerAtSnapshotTimestamp() {
		var tracker = PromptTimerTracker()

		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T01:00:07.000Z")!
		XCTAssertEqual(tracker.presentation(now: now)?.label, "0:07")
		XCTAssertEqual(tracker.presentation(now: now)?.isRunning, true)
	}

	func testStandbyWithAttentionStopsTimer() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)

		tracker.observe(
			state: .standby,
			updatedAt: "2026-07-07T01:02:03.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_end", name: "Stop"),
			attention: attention(expiresAt: "2099-01-01T00:00:00.000Z")
		)

		let later = StateJsonReader.parseISO8601Date("2026-07-07T01:10:00.000Z")!
		XCTAssertEqual(tracker.presentation(now: later)?.label, "2:03")
		XCTAssertEqual(tracker.presentation(now: later)?.isRunning, false)
	}

	func testTransientErroredStateDoesNotStopTimerWhenRecovered() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)
		tracker.observe(
			state: .errored,
			updatedAt: "2026-07-07T01:00:20.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "tool_use", name: "Bash"),
			attention: attention(expiresAt: "2099-01-01T00:00:00.000Z")
		)
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:55.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "tool_use", name: "Read"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T01:01:30.000Z")!
		XCTAssertEqual(tracker.presentation(now: now)?.label, "1:30")
		XCTAssertEqual(tracker.presentation(now: now)?.isRunning, true)
	}

	func testErroredForOneMinuteStopsTimerAtThreshold() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)
		tracker.observe(
			state: .errored,
			updatedAt: "2026-07-07T01:00:20.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_end", name: "StopFailure"),
			attention: attention(expiresAt: "2099-01-01T00:00:00.000Z")
		)

		let afterThreshold = StateJsonReader.parseISO8601Date("2026-07-07T01:02:30.000Z")!
		XCTAssertEqual(tracker.presentation(now: afterThreshold)?.label, "1:20")
		XCTAssertEqual(tracker.presentation(now: afterThreshold)?.isRunning, false)
	}

	func testCompactLabelsUseMinutesHoursAndDays() {
		XCTAssertEqual(PromptTimerPresentation.compactLabel(elapsed: 59), "0:59")
		XCTAssertEqual(PromptTimerPresentation.compactLabel(elapsed: 754), "12:34")
		XCTAssertEqual(PromptTimerPresentation.compactLabel(elapsed: 3_720), "1h 02m")
		XCTAssertEqual(PromptTimerPresentation.compactLabel(elapsed: 363_600), "4d 5h")
	}

	private func attention(expiresAt: String) -> AttentionPayload {
		AttentionPayload(
			createdAt: "2026-07-07T01:00:00.000Z",
			expiresAt: expiresAt,
			summary: "Done",
			reasonKind: "input_requested"
		)
	}
}

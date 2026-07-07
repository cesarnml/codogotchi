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

	func testIdleClearsTimerPresentation() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)

		tracker.observe(
			state: .idle,
			updatedAt: "2026-07-07T01:01:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_end", name: "Dismiss"),
			attention: nil
		)

		XCTAssertNil(tracker.presentation(now: StateJsonReader.parseISO8601Date("2026-07-07T01:02:00.000Z")!))
	}

	func testExplicitResetClearsCompletedTimerPresentation() {
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

		tracker.reset()

		XCTAssertNil(tracker.presentation(now: StateJsonReader.parseISO8601Date("2026-07-07T01:10:00.000Z")!))
	}

	func testInFlightAfterRestStartsNewTimerEvenWithoutSessionStart() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .standby,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_end", name: "Stop"),
			attention: attention(expiresAt: "2099-01-01T00:00:00.000Z")
		)

		tracker.observe(
			state: .testing,
			updatedAt: "2026-07-07T01:05:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "tool_use", name: "Bash"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T01:05:09.000Z")!
		XCTAssertEqual(tracker.presentation(now: now)?.label, "0:09")
		XCTAssertEqual(tracker.presentation(now: now)?.isRunning, true)
	}

	// Force Idle calls reset() synchronously, but the matching disk rewrite
	// (StateJsonWriter.forceIdle) lands asynchronously on a background queue.
	// A poll tick that reads the stale, pre-reset in-flight state before that
	// write completes must not resurrect the timer.
	func testResetIgnoresStaleInFlightObservationRacingTheAsyncRewrite() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)

		// User right-clicks Force Idle at 01:00:01 (wall clock) — resetPromptTimer()
		// runs synchronously, well after the stale "thinking" slice's own timestamp.
		tracker.reset(now: StateJsonReader.parseISO8601Date("2026-07-07T01:00:01.000Z")!)

		// The next poll tick reads that same stale, pre-reset "thinking" slice
		// (the async idle rewrite hasn't landed on disk yet).
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.500Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "tool_use", name: "Bash"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T01:00:02.000Z")!
		XCTAssertNil(tracker.presentation(now: now))
	}

	// Once the idle rewrite lands (or a real new turn starts) with a timestamp
	// AFTER the reset, the timer must start normally.
	func testResetAllowsInFlightObservationAfterTheResetMoment() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T01:00:00.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "session_start", name: "SessionStart"),
			attention: nil
		)

		tracker.reset(now: StateJsonReader.parseISO8601Date("2026-07-07T01:00:01.000Z")!)

		tracker.observe(
			state: .implementing,
			updatedAt: "2026-07-07T01:00:05.000Z",
			sourceEvent: SourceEvent(origin: "codex", kind: "tool_use", name: "Bash"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T01:00:09.000Z")!
		XCTAssertEqual(tracker.presentation(now: now)?.label, "0:04")
		XCTAssertEqual(tracker.presentation(now: now)?.isRunning, true)
	}

	// Force Idle's slice rewrite flips only `activity_state` to idle,
	// preserving the old `source_event` (which can be `session_start`) and
	// `updated_at`. Idle must win over the session_start branch, or every
	// poll of the rewritten slice restarts the timer from the preserved
	// timestamp and the chip becomes immortal.
	func testIdleWithPreservedSessionStartSourceEventClearsTimer() {
		var tracker = PromptTimerTracker()
		tracker.observe(
			state: .thinking,
			updatedAt: "2026-07-07T20:23:37.225Z",
			sourceEvent: SourceEvent(origin: "antigravity", kind: "session_start", name: "unknown"),
			attention: nil
		)

		// Force Idle landed: same updated_at, same session_start source event,
		// only the activity state flipped to idle.
		tracker.observe(
			state: .idle,
			updatedAt: "2026-07-07T20:23:37.225Z",
			sourceEvent: SourceEvent(origin: "antigravity", kind: "session_start", name: "unknown"),
			attention: nil
		)

		let now = StateJsonReader.parseISO8601Date("2026-07-07T20:24:14.000Z")!
		XCTAssertNil(tracker.presentation(now: now))
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

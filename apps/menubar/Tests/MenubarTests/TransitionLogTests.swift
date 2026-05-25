import XCTest

@testable import Codogotchi

/// Behavior contract for P2.08 `TransitionLog`: append-only NDJSON writer that
/// records observed state transitions, emits a heartbeat line once per hour
/// when no transition has occurred, and rotates the log file to `.log.1` when
/// it grows past 10MB.
///
/// Tests drive the heartbeat via an injectable clock and a synchronous
/// `tickHeartbeatForTesting()` seam so they do not stall on wall-clock waits.
final class TransitionLogTests: XCTestCase {

	// MARK: - Sandbox helpers

	private func makeSandboxDirectory() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-transition-log-tests")
			.appendingPathComponent(UUID().uuidString)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func readLines(_ url: URL) throws -> [String] {
		let data = try Data(contentsOf: url)
		guard let text = String(data: data, encoding: .utf8) else { return [] }
		return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
	}

	private func decodeJSONObject(_ line: String) throws -> [String: Any] {
		let data = Data(line.utf8)
		let obj = try JSONSerialization.jsonObject(with: data)
		return obj as? [String: Any] ?? [:]
	}

	private func makeSnapshot(
		_ state: ActivityState,
		updatedAt: String = "2026-05-20T14:32:11.123Z",
		sourceEvent: SourceEvent? = nil
	) -> StateSnapshot {
		return StateSnapshot(
			schemaVersion: 1,
			activityState: state,
			updatedAt: updatedAt,
			sourceEvent: sourceEvent
		)
	}

	// MARK: - NDJSON line shape

	func testRecordTransitionWritesNDJSONLineWithExpectedFields() throws {
		let dir = makeSandboxDirectory()
		let path = dir.appendingPathComponent("state-transitions.log")
		let fixedNow = Date(timeIntervalSince1970: 1_747_750_331.123)
		let log = TransitionLog(path: path, clock: { fixedNow })

		let snapshot = makeSnapshot(
			.implementing,
			sourceEvent: SourceEvent(
				origin: "claude_code",
				kind: "tool_use",
				name: "Edit"
			)
		)
		log.recordTransition(snapshot: snapshot, previousState: .idle)

		let lines = try readLines(path)
		XCTAssertEqual(lines.count, 1, "expected exactly one NDJSON line for one transition")
		let obj = try decodeJSONObject(lines[0])
		XCTAssertEqual(obj["state"] as? String, "implementing")
		XCTAssertEqual(obj["prev"] as? String, "idle")
		XCTAssertEqual(obj["schema_version"] as? Int, 1)
		XCTAssertEqual(obj["source_origin"] as? String, "claude_code")
		XCTAssertEqual(obj["source_kind"] as? String, "tool_use")
		XCTAssertEqual(obj["source_name"] as? String, "Edit")
		let ts = obj["ts"] as? String ?? ""
		// Shape check, not a value check. Fixed-clock fixture is enough to
		// prove the formatter is wired in; the exact year/month encoded by
		// `timeIntervalSince1970: 1_747_750_331.123` is intentionally not
		// asserted because it is brittle to fixture-value edits.
		let isoRegex = try NSRegularExpression(
			pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
		)
		XCTAssertNotNil(
			isoRegex.firstMatch(
				in: ts,
				range: NSRange(ts.startIndex..., in: ts)
			),
			"expected ISO-8601 ts with milliseconds and Z suffix, got \(ts)"
		)
		XCTAssertNil(obj["heartbeat"], "transition lines must not set heartbeat:true")
	}

	func testRecordTransitionWithMissingSourceEventEmitsNullSourceFields() throws {
		let dir = makeSandboxDirectory()
		let path = dir.appendingPathComponent("state-transitions.log")
		let log = TransitionLog(path: path, clock: { Date() })

		log.recordTransition(
			snapshot: makeSnapshot(.runningTests, sourceEvent: nil),
			previousState: .implementing
		)

		let lines = try readLines(path)
		XCTAssertEqual(lines.count, 1)
		let obj = try decodeJSONObject(lines[0])
		// When sourceEvent is absent, source_* fields must be absent or null —
		// never a stale carryover from a prior call.
		XCTAssertTrue(
			obj["source_origin"] is NSNull || obj["source_origin"] == nil,
			"source_origin must be null/absent when sourceEvent is nil"
		)
		XCTAssertTrue(
			obj["source_kind"] is NSNull || obj["source_kind"] == nil,
			"source_kind must be null/absent when sourceEvent is nil"
		)
		XCTAssertTrue(
			obj["source_name"] is NSNull || obj["source_name"] == nil,
			"source_name must be null/absent when sourceEvent is nil"
		)
	}

	// MARK: - Heartbeats

	func testNoTransitionsForOverAnHourEmitsHeartbeatLine() throws {
		let dir = makeSandboxDirectory()
		let path = dir.appendingPathComponent("state-transitions.log")
		var now = Date(timeIntervalSince1970: 1_747_700_000)
		let log = TransitionLog(
			path: path,
			clock: { now },
			heartbeatInterval: 60 * 60
		)

		// Establish a "last activity" baseline by recording one transition.
		log.recordTransition(
			snapshot: makeSnapshot(.idle),
			previousState: .idle
		)

		// Fast-forward 61 minutes with no further transitions and tick the
		// heartbeat. Expect exactly one heartbeat line appended.
		now = now.addingTimeInterval(61 * 60)
		log.tickHeartbeatForTesting()

		let lines = try readLines(path)
		XCTAssertEqual(
			lines.count, 2,
			"expected one transition + one heartbeat line, got \(lines.count)"
		)
		let hb = try decodeJSONObject(lines[1])
		XCTAssertEqual(hb["heartbeat"] as? Bool, true)
		XCTAssertEqual(hb["state"] as? String, "idle")
		XCTAssertEqual(hb["schema_version"] as? Int, 1)
	}

	func testTransitionResetsHeartbeatWindow() throws {
		let dir = makeSandboxDirectory()
		let path = dir.appendingPathComponent("state-transitions.log")
		var now = Date(timeIntervalSince1970: 1_747_700_000)
		let log = TransitionLog(
			path: path,
			clock: { now },
			heartbeatInterval: 60 * 60
		)

		log.recordTransition(snapshot: makeSnapshot(.idle), previousState: .idle)

		// Tick at 30 minutes — no heartbeat yet (window not elapsed).
		now = now.addingTimeInterval(30 * 60)
		log.tickHeartbeatForTesting()

		// Real transition at 45 minutes — must reset the heartbeat window.
		now = now.addingTimeInterval(15 * 60)
		log.recordTransition(snapshot: makeSnapshot(.implementing), previousState: .idle)

		// Tick again at 60 minutes total elapsed since reset (only 15 minutes
		// after the reset) — still no heartbeat.
		now = now.addingTimeInterval(15 * 60)
		log.tickHeartbeatForTesting()

		let lines = try readLines(path)
		XCTAssertEqual(
			lines.count, 2,
			"expected only the two transitions; heartbeat must not fire within the reset window"
		)
		for line in lines {
			let obj = try decodeJSONObject(line)
			XCTAssertNil(obj["heartbeat"], "transitions must not carry heartbeat:true")
		}
	}

	// MARK: - Rotation

	func testRotationAtTenMegabytesProducesSingleBackup() throws {
		let dir = makeSandboxDirectory()
		let path = dir.appendingPathComponent("state-transitions.log")
		let backup = dir.appendingPathComponent("state-transitions.log.1")
		let log = TransitionLog(path: path, clock: { Date() })

		// Pre-seed the active log with > 10MB of plausible (but inert) bytes
		// so the very next recorded transition triggers rotation. Padding with
		// JSON-shaped lines rather than zeros guards against any
		// rotation-by-content heuristics in implementations.
		let oneLine = String(repeating: "x", count: 1024) + "\n"  // ~1KB
		var seed = ""
		seed.reserveCapacity(11 * 1024 * 1024)
		for _ in 0..<(11 * 1024) {
			seed.append(oneLine)
		}
		try Data(seed.utf8).write(to: path)
		let preRotateSize = (try FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0
		XCTAssertGreaterThan(preRotateSize, 10 * 1024 * 1024)

		log.recordTransition(snapshot: makeSnapshot(.celebrating), previousState: .idle)

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: backup.path),
			"expected backup .log.1 to exist after rotation"
		)
		let backupSize = (try FileManager.default.attributesOfItem(atPath: backup.path)[.size] as? Int) ?? 0
		let activeSize = (try FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0
		XCTAssertGreaterThan(backupSize, 10 * 1024 * 1024, "backup retains the pre-rotation bytes")
		XCTAssertLessThan(
			activeSize, 10 * 1024 * 1024,
			"active log is reset after rotation; it should be much smaller than 10MB"
		)

		// One more rotation must overwrite the existing backup, not create
		// `.log.2`. Pad again and trigger.
		try Data(seed.utf8).write(to: path)
		log.recordTransition(snapshot: makeSnapshot(.idle), previousState: .celebrating)
		let secondBackup = dir.appendingPathComponent("state-transitions.log.2")
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: secondBackup.path),
			"single backup policy: .log.2 must never be created"
		)
	}
}

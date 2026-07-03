import Foundation
import XCTest

@testable import Codogotchi

final class StateJsonWriterTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("StateJsonWriterTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Helpers

	private func makeStateDir() -> URL {
		let dir = tmp.appendingPathComponent("state.d")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func writeSlice(_ filename: String, in dir: URL, json: [String: Any]) {
		let url = dir.appendingPathComponent(filename)
		let data = try! JSONSerialization.data(withJSONObject: json)
		try! data.write(to: url)
	}

	private func readSlice(_ filename: String, in dir: URL) -> [String: Any]? {
		let url = dir.appendingPathComponent(filename)
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		return obj
	}

	/// Runs the async `dismissAttention` and blocks until it completes.
	private func runDismissAttention(dir: URL, origins: Set<String>, now: Date = Date()) {
		let done = expectation(description: "dismissAttention")
		StateJsonWriter.dismissAttention(at: dir.path, origins: origins, now: now) {
			done.fulfill()
		}
		wait(for: [done], timeout: 5)
	}

	// MARK: - Single slice with attention

	func testDismissAttentionClearsAttentionAndSetsIdle() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"source_event": ["origin": "claude_code"],
				"attention": ["message": "look at me"],
			])

		runDismissAttention(dir: dir, origins: ["claude_code"])

		let result = readSlice("claude_code:session1.json", in: dir)!
		XCTAssertEqual(result["activity_state"] as? String, "idle")
		XCTAssertNil(result["attention"], "attention must be removed after dismissAttention")
	}

	// MARK: - Winner-only (only the displayed slice is cleared)

	func testDismissAttentionClearsOnlyTheWinnerSlice() {
		let dir = makeStateDir()
		// The bubble is drawn for the freshest slice; only that one must be cleared.
		writeSlice(
			"claude_code:old.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "red_tdd",
				"updated_at": "2026-07-01T10:00:00Z",
				"source_event": ["origin": "claude_code"],
				"attention": ["message": "old notice"],
			])
		writeSlice(
			"claude_code:new.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "red_tdd",
				"updated_at": "2026-07-01T11:00:00Z",
				"source_event": ["origin": "claude_code"],
				"attention": ["message": "current notice"],
			])

		runDismissAttention(dir: dir, origins: ["claude_code"])

		let winner = readSlice("claude_code:new.json", in: dir)!
		XCTAssertEqual(winner["activity_state"] as? String, "idle")
		XCTAssertNil(winner["attention"], "the displayed slice's attention must be removed")

		let older = readSlice("claude_code:old.json", in: dir)!
		XCTAssertEqual(older["activity_state"] as? String, "red_tdd",
			"an older, non-displayed slice must be left untouched")
		XCTAssertNotNil(older["attention"], "a non-winner slice's attention must survive")
	}

	// MARK: - Origin-scoped clearing (multi-pet)

	func testDismissAttentionClearsOnlyTargetedOrigins() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"source_event": ["origin": "claude_code"],
				"attention": ["message": "claude needs you"],
			])
		writeSlice(
			"cursor:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"source_event": ["origin": "cursor"],
				"attention": ["message": "cursor needs you"],
			])

		runDismissAttention(dir: dir, origins: ["claude_code"])

		let cleared = readSlice("claude_code:session1.json", in: dir)!
		XCTAssertEqual(cleared["activity_state"] as? String, "idle")
		XCTAssertNil(cleared["attention"], "dismissed origin's attention must be removed")

		let untouched = readSlice("cursor:session1.json", in: dir)!
		XCTAssertEqual(
			untouched["activity_state"] as? String, "implementing",
			"a different origin's slice must not be set to idle")
		XCTAssertNotNil(
			untouched["attention"], "a different origin's attention must survive a scoped dismiss")
	}

	// MARK: - Missing directory

	func testDismissAttentionNoOpsWhenDirectoryAbsent() {
		let missing = tmp.appendingPathComponent("state.d").path
		// Must not crash
		runDismissAttention(dir: URL(fileURLWithPath: missing), origins: ["claude_code"])
	}

	// MARK: - Slice without attention field

	func testDismissAttentionSetsIdleEvenWhenAttentionAbsent() {
		let dir = makeStateDir()
		writeSlice(
			"cursor:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"source_event": ["origin": "cursor"],
			])

		runDismissAttention(dir: dir, origins: ["cursor"])

		let result = readSlice("cursor:session1.json", in: dir)!
		XCTAssertEqual(result["activity_state"] as? String, "idle",
			"activity_state must be set to idle even when attention key was absent")
		XCTAssertNil(result["attention"])
	}

	// MARK: - Force Idle escape hatch

	/// Runs the async `forceIdle` and blocks until it completes so assertions see
	/// the finished writes.
	private func runForceIdle(dir: URL, origins: Set<String>, now: Date = Date()) {
		let done = expectation(description: "forceIdle")
		StateJsonWriter.forceIdle(at: dir.path, origins: origins, now: now) {
			done.fulfill()
		}
		wait(for: [done], timeout: 5)
	}

	private func setMTime(_ filename: String, in dir: URL, to date: Date) {
		try! FileManager.default.setAttributes(
			[.modificationDate: date],
			ofItemAtPath: dir.appendingPathComponent(filename).path)
	}

	func testForceIdleResetsStuckStateToIdle() {
		let dir = makeStateDir()
		// A prompt that failed (rate limit) leaves the slice on a stale in-flight
		// state with no terminal event; Force Idle must clear it.
		writeSlice(
			"codex:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"source_event": ["origin": "codex"],
			])

		runForceIdle(dir: dir, origins: ["codex"])

		let result = readSlice("codex:session1.json", in: dir)!
		XCTAssertEqual(result["activity_state"] as? String, "idle",
			"forceIdle must reset a stuck non-idle state to idle")
	}

	func testForceIdleResetsOnlyTargetedOrigins() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "testing",
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"cursor:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "testing",
				"source_event": ["origin": "cursor"],
			])

		runForceIdle(dir: dir, origins: ["claude_code"])

		XCTAssertEqual(
			readSlice("claude_code:session1.json", in: dir)!["activity_state"] as? String, "idle",
			"the targeted origin must be reset to idle")
		XCTAssertEqual(
			readSlice("cursor:session1.json", in: dir)!["activity_state"] as? String, "testing",
			"an origin outside the target set must survive — this is the combined-window "
				+ "over-reach that idled the independently-windowed Claude pet")
	}

	func testForceIdleResetsCombinedSetAcrossOrigins() {
		let dir = makeStateDir()
		for origin in ["antigravity", "codex", "vscode"] {
			writeSlice(
				"\(origin):session1.json", in: dir,
				json: [
					"schema_version": 6,
					"activity_state": "thinking",
					"source_event": ["origin": origin],
				])
		}
		writeSlice(
			"claude_code:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"source_event": ["origin": "claude_code"],
			])

		// Combined window folds antigravity+codex+vscode into one pet; claude_code
		// has its own window and must be untouched.
		runForceIdle(dir: dir, origins: ["antigravity", "codex", "vscode"])

		for origin in ["antigravity", "codex", "vscode"] {
			XCTAssertEqual(
				readSlice("\(origin):session1.json", in: dir)!["activity_state"] as? String, "idle",
				"\(origin) is in the combined set and must be reset")
		}
		XCTAssertEqual(
			readSlice("claude_code:session1.json", in: dir)!["activity_state"] as? String,
			"implementing",
			"claude_code is outside the combined set and must survive")
	}

	func testForceIdleRewritesOnlyTheFreshestWinnerSlice() {
		let dir = makeStateDir()
		// Two live sessions for the same origin; the reader renders the freshest
		// (max updated_at). Force Idle must touch only that winner — rewriting the
		// older session is wasted work and, on a real 100+ slice dir, the source of
		// the freeze.
		writeSlice(
			"claude_code:old.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "reading",
				"updated_at": "2026-07-01T10:00:00Z",
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"claude_code:new.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"updated_at": "2026-07-01T11:00:00Z",
				"source_event": ["origin": "claude_code"],
			])

		runForceIdle(dir: dir, origins: ["claude_code"])

		XCTAssertEqual(
			readSlice("claude_code:new.json", in: dir)!["activity_state"] as? String, "idle",
			"the freshest (winner) slice must be reset to idle")
		XCTAssertEqual(
			readSlice("claude_code:old.json", in: dir)!["activity_state"] as? String, "reading",
			"an older, non-displayed slice must be left untouched")
	}

	func testForceIdleSkipsStaleMTimeSlicesToAvoidResurrection() {
		let dir = makeStateDir()
		let filename = "codex:ancient.json"
		writeSlice(
			filename, in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"updated_at": "2026-07-01T09:00:00Z",
				"source_event": ["origin": "codex"],
			])
		// Age the file past the reader's 2h mtime TTL: the reader ignores it (no
		// visible pet), so Force Idle must NOT rewrite it — doing so refreshes its
		// mtime and resurrects an aged-out pet (the "3 pets suddenly appeared" bug).
		let now = Date()
		setMTime(filename, in: dir, to: now.addingTimeInterval(-3 * 60 * 60))

		runForceIdle(dir: dir, origins: ["codex"], now: now)

		XCTAssertEqual(
			readSlice(filename, in: dir)!["activity_state"] as? String, "thinking",
			"a stale-mtime slice must not be rewritten by Force Idle")
		let mtime = try! FileManager.default.attributesOfItem(
			atPath: dir.appendingPathComponent(filename).path)[.modificationDate] as! Date
		XCTAssertLessThan(
			mtime.timeIntervalSince(now), -2 * 60 * 60,
			"the stale slice's mtime must be left old so the reader keeps ignoring it")
	}

	func testForceIdleWithEmptyOriginsIsNoOp() {
		let dir = makeStateDir()
		writeSlice(
			"codex:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"source_event": ["origin": "codex"],
			])

		runForceIdle(dir: dir, origins: [])

		XCTAssertEqual(
			readSlice("codex:session1.json", in: dir)!["activity_state"] as? String, "thinking",
			"forceIdle with no target origins must change nothing")
	}

	// MARK: - Session-precise forceIdle / dismissAttention (P15.04 fix)

	private func runForceIdle(dir: URL, origin: String, sessionId: String, now: Date = Date()) {
		let done = expectation(description: "forceIdle-exact")
		StateJsonWriter.forceIdle(at: dir.path, origin: origin, sessionId: sessionId, now: now) {
			done.fulfill()
		}
		wait(for: [done], timeout: 5)
	}

	private func runDismissAttention(dir: URL, origin: String, sessionId: String, now: Date = Date()) {
		let done = expectation(description: "dismissAttention-exact")
		StateJsonWriter.dismissAttention(at: dir.path, origin: origin, sessionId: sessionId, now: now) {
			done.fulfill()
		}
		wait(for: [done], timeout: 5)
	}

	func testForceIdleWithExactSessionTargetsOnlyThatSliceEvenWhenASiblingIsFresher() {
		let dir = makeStateDir()
		// Two concurrent claude_code sessions; "new" is fresher and would be the
		// only one touched by the origin-scoped winner-selection overload. The
		// user right-clicked "old" specifically — Force Idle must reset exactly
		// that session, not the fresher sibling it happens to share an origin with.
		writeSlice(
			"claude_code:old.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "reading",
				"updated_at": "2026-07-01T10:00:00Z",
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"claude_code:new.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"updated_at": "2026-07-01T11:00:00Z",
				"source_event": ["origin": "claude_code"],
			])

		runForceIdle(dir: dir, origin: "claude_code", sessionId: "old")

		XCTAssertEqual(
			readSlice("claude_code:old.json", in: dir)!["activity_state"] as? String, "idle",
			"the exact clicked session must be reset to idle")
		XCTAssertEqual(
			readSlice("claude_code:new.json", in: dir)!["activity_state"] as? String, "thinking",
			"a fresher sibling session must survive untouched — this is the P15.04 bug fix")
	}

	func testDismissAttentionWithExactSessionTargetsOnlyThatSliceEvenWhenASiblingIsFresher() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:old.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"updated_at": "2026-07-01T10:00:00Z",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"claude_code:new.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"updated_at": "2026-07-01T11:00:00Z",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])

		runDismissAttention(dir: dir, origin: "claude_code", sessionId: "old")

		let old = readSlice("claude_code:old.json", in: dir)!
		XCTAssertEqual(old["activity_state"] as? String, "idle")
		XCTAssertNil(old["attention"], "the exact clicked session's attention must be cleared")

		let new = readSlice("claude_code:new.json", in: dir)!
		XCTAssertEqual(
			new["activity_state"] as? String, "waiting_for_input",
			"a fresher sibling session must survive untouched")
		XCTAssertNotNil(new["attention"], "a fresher sibling session's attention must survive untouched")
	}

	func testForceIdleWithExactSessionSkipsStaleMTimeSlice() {
		let dir = makeStateDir()
		let filename = "codex:ancient.json"
		writeSlice(
			filename, in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "thinking",
				"source_event": ["origin": "codex"],
			])
		let now = Date()
		setMTime(filename, in: dir, to: now.addingTimeInterval(-3 * 60 * 60))

		runForceIdle(dir: dir, origin: "codex", sessionId: "ancient", now: now)

		XCTAssertEqual(
			readSlice(filename, in: dir)!["activity_state"] as? String, "thinking",
			"a stale-mtime slice must not be rewritten even when targeted exactly")
	}

	func testForceIdleWithExactSessionIsNoOpWhenSliceIsAbsent() {
		let dir = makeStateDir()
		// Must not throw or crash when the exact slice does not exist.
		runForceIdle(dir: dir, origin: "claude_code", sessionId: "missing")
		XCTAssertNil(readSlice("claude_code:missing.json", in: dir))
	}

	// MARK: - dismissAllSessionsAttention (Focus/dismiss fan-out for session-pets bubbles)

	private func runDismissAllSessionsAttention(dir: URL, origin: String, now: Date = Date()) {
		let done = expectation(description: "dismissAllSessionsAttention")
		StateJsonWriter.dismissAllSessionsAttention(at: dir.path, origin: origin, now: now) {
			done.fulfill()
		}
		wait(for: [done], timeout: 5)
	}

	func testDismissAllSessionsAttentionClearsEverySessionOfTheOriginNotJustTheWinner() {
		let dir = makeStateDir()
		// Two live claude_code sessions, both carrying attention; a session-pets
		// Focus/dismiss can only raise the platform as a whole, so both must clear —
		// unlike the winner-only origin-scoped overload used by non-session-keyed windows.
		writeSlice(
			"claude_code:old.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"updated_at": "2026-07-01T10:00:00Z",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"claude_code:new.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"updated_at": "2026-07-01T11:00:00Z",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])

		runDismissAllSessionsAttention(dir: dir, origin: "claude_code")

		let old = readSlice("claude_code:old.json", in: dir)!
		XCTAssertEqual(old["activity_state"] as? String, "idle")
		XCTAssertNil(old["attention"], "the older sibling session must also clear")

		let new = readSlice("claude_code:new.json", in: dir)!
		XCTAssertEqual(new["activity_state"] as? String, "idle")
		XCTAssertNil(new["attention"], "the freshest session must clear")
	}

	func testDismissAllSessionsAttentionLeavesOtherOriginsUntouched() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:s1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])
		writeSlice(
			"cursor:s1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "cursor"],
			])

		runDismissAllSessionsAttention(dir: dir, origin: "claude_code")

		XCTAssertEqual(readSlice("claude_code:s1.json", in: dir)!["activity_state"] as? String, "idle")
		let untouched = readSlice("cursor:s1.json", in: dir)!
		XCTAssertEqual(
			untouched["activity_state"] as? String, "waiting_for_input",
			"a different origin must not be touched")
		XCTAssertNotNil(untouched["attention"])
	}

	func testDismissAllSessionsAttentionSkipsStaleMTimeSlices() {
		let dir = makeStateDir()
		let filename = "claude_code:ancient.json"
		writeSlice(
			filename, in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "waiting_for_input",
				"attention": ["kind": "needs_input"],
				"source_event": ["origin": "claude_code"],
			])
		let now = Date()
		setMTime(filename, in: dir, to: now.addingTimeInterval(-3 * 60 * 60))

		runDismissAllSessionsAttention(dir: dir, origin: "claude_code", now: now)

		XCTAssertEqual(
			readSlice(filename, in: dir)!["activity_state"] as? String, "waiting_for_input",
			"a stale-mtime slice must not be rewritten (would resurrect an aged-out pet)")
	}
}

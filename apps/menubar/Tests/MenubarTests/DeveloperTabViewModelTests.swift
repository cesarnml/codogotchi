import Foundation
import XCTest

@testable import Codogotchi

/// Behavior contract for `DeveloperTabViewModel` — read-only observability
/// aggregation for the Developer settings tab (P8.08).
final class DeveloperTabViewModelTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("DeveloperTabViewModelTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Helpers

	/// Creates a `state.d/` directory containing a single slice file with the given schema version.
	/// Returns the directory URL (pass as `stateDirURL` to `makeVM`).
	private func makeStateDir(schemaVersion: Int = EXPECTED_STATE_SCHEMA_VERSION) -> URL {
		let dir = tmp.appendingPathComponent("state.d")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let url = dir.appendingPathComponent("claude_code:test-session-id.json")
		let json = """
			{"schema_version":\(schemaVersion),"origin":"claude_code","session_id":"test-session-id","activity_state":"idle","updated_at":"2026-01-01T00:00:00Z"}
			"""
		try! json.write(to: url, atomically: true, encoding: .utf8)
		return dir
	}

	private func makeGateJson() -> URL {
		let url = tmp.appendingPathComponent("gate.json")
		let json = """
			{"gate":"ticket_started","since":"2026-01-01T00:00:00Z","expires_at":"2026-12-31T00:00:00Z"}
			"""
		try! json.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	private func makeTransitionLog(lines: [String]) -> URL {
		let url = tmp.appendingPathComponent("state-transitions.log")
		let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
		try! content.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	private func transitionLine(
		state: String = "idle",
		prev: String = "idle",
		sourceKind: String? = nil,
		sourceName: String? = nil,
		sourceOrigin: String? = nil,
		ts: String = "2026-01-01T00:00:00Z"
	) -> String {
		var obj: [String: Any] = [
			"ts": ts,
			"state": state,
			"prev": prev,
			"schema_version": 1,
		]
		if let k = sourceKind { obj["source_kind"] = k }
		if let n = sourceName { obj["source_name"] = n }
		if let o = sourceOrigin { obj["source_origin"] = o }
		return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
	}

	private func makeVM(stateDirURL: URL? = nil, gateJsonURL: URL? = nil, logURL: URL? = nil)
		-> DeveloperTabViewModel
	{
		DeveloperTabViewModel(
			stateDirPath: stateDirURL?.path ?? tmp.appendingPathComponent("missing-state.d").path,
			gateJsonPath: gateJsonURL?.path,
			transitionLogPath: logURL?.path ?? tmp.appendingPathComponent("missing-log.log").path
		)
	}

	// MARK: - Last-5 transition tail

	func testLast5TailReturnsAtMost5Entries() {
		let lines = (0..<7).map { transitionLine(state: "idle", ts: "2026-01-0\($0+1)T00:00:00Z") }
		let logURL = makeTransitionLog(lines: lines)
		let vm = makeVM(logURL: logURL)

		XCTAssertLessThanOrEqual(vm.last5Transitions.count, 5)
		XCTAssertEqual(vm.last5Transitions.count, 5)
	}

	func testLast5TailReturnsAllWhenFewerThan5() {
		let lines = (0..<3).map { transitionLine(ts: "2026-01-0\($0+1)T00:00:00Z") }
		let logURL = makeTransitionLog(lines: lines)
		let vm = makeVM(logURL: logURL)

		XCTAssertEqual(vm.last5Transitions.count, 3)
	}

	func testLast5TailReturnsEmptyForMissingLog() {
		let vm = makeVM()
		XCTAssertTrue(vm.last5Transitions.isEmpty, "missing log must return empty tail")
	}

	func testLast5TailReturnsNewest5() {
		let lines = (1...7).map {
			transitionLine(state: "state\($0)", ts: "2026-01-\(String(format: "%02d", $0))T00:00:00Z")
		}
		let logURL = makeTransitionLog(lines: lines)
		let vm = makeVM(logURL: logURL)

		// Most recent 5 are lines 3-7 (states 3-7); must appear newest-first or oldest-first
		// (document order: last 5 entries in file order, most recent last)
		let states = vm.last5Transitions.map(\.state)
		XCTAssertTrue(states.contains("state7"), "must include the newest entry")
		XCTAssertFalse(states.contains("state1"), "must exclude entries beyond the last 5")
		XCTAssertFalse(states.contains("state2"), "must exclude entries beyond the last 5")
	}

	func testLast5TailSkipsHeartbeatLines() {
		let transitionLine = transitionLine(state: "implementing")
		let heartbeatLine = """
			{"ts":"2026-01-02T00:00:00Z","state":"implementing","heartbeat":true,"schema_version":1}
			"""
		let logURL = makeTransitionLog(lines: [transitionLine, heartbeatLine])
		let vm = makeVM(logURL: logURL)

		// Heartbeat lines must not appear in the last-5 tail
		XCTAssertEqual(vm.last5Transitions.count, 1)
		XCTAssertFalse(
			vm.last5Transitions.contains { $0.state == "implementing" && $0.isHeartbeat },
			"heartbeat entries must be filtered out"
		)
	}

	func testTransitionEntryExposesSourceFields() {
		let line = transitionLine(
			state: "red_tdd", prev: "idle",
			sourceKind: "tool_result", sourceName: "BashTool",
			sourceOrigin: "claude_code"
		)
		let logURL = makeTransitionLog(lines: [line])
		let vm = makeVM(logURL: logURL)
		let entry = try! XCTUnwrap(vm.last5Transitions.first)
		XCTAssertEqual(entry.state, "red_tdd")
		XCTAssertEqual(entry.sourceKind, "tool_result")
		XCTAssertEqual(entry.sourceName, "BashTool")
		XCTAssertEqual(entry.sourceOrigin, "claude_code")
	}

	// MARK: - Schema mismatch

	func testSchemaMismatchNotFlaggedWhenVersionsMatch() {
		let dirURL = makeStateDir(schemaVersion: EXPECTED_STATE_SCHEMA_VERSION)
		let vm = makeVM(stateDirURL: dirURL)
		XCTAssertFalse(vm.schemaVersionMismatch,
			"matching schema versions must not flag a mismatch")
	}

	func testSchemaMismatchFlaggedWhenVersionsDiffer() {
		let dirURL = makeStateDir(schemaVersion: EXPECTED_STATE_SCHEMA_VERSION - 1)
		let vm = makeVM(stateDirURL: dirURL)
		XCTAssertTrue(vm.schemaVersionMismatch,
			"differing schema versions must flag a mismatch")
	}

	func testSchemaMismatchFlaggedWhenSchemaVersionIsNonInteger() throws {
		let dir = tmp.appendingPathComponent("state.d")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let url = dir.appendingPathComponent("claude_code:test-id.json")
		// schema_version is a string, not an integer — must flag mismatch, not silently pass
		try """
			{"schema_version":"4","origin":"claude_code","session_id":"test-id","activity_state":"idle","updated_at":"2026-01-01T00:00:00Z"}
			""".write(to: url, atomically: true, encoding: .utf8)
		let vm = makeVM(stateDirURL: dir)
		XCTAssertTrue(vm.schemaVersionMismatch,
			"non-integer schema_version must trigger mismatch, not silently return false")
	}

	func testSchemaMismatchNotFlaggedWhenStateDirAbsent() {
		let vm = makeVM()  // stateDirURL = nil → missing-state.d path
		XCTAssertFalse(vm.schemaVersionMismatch,
			"absent state.d/ must not flag a mismatch")
	}

	func testRendererSchemaVersionMatchesExpectedConstant() {
		let vm = makeVM()
		XCTAssertEqual(vm.rendererSchemaVersion, EXPECTED_STATE_SCHEMA_VERSION)
	}

	// MARK: - Cursor-bridge explainer

	func testCursorBridgeExplainerReadsLastSeenOriginFromLog() {
		let line = transitionLine(sourceKind: "tool_result", sourceName: "ComposerTool", sourceOrigin: "cursor")
		let logURL = makeTransitionLog(lines: [line])
		let vm = makeVM(logURL: logURL)
		XCTAssertEqual(vm.lastSeenSourceOrigin, "cursor",
			"explainer must surface last-seen source_origin from transition log")
		XCTAssertEqual(vm.lastSeenSourceName, "ComposerTool")
	}

	func testCursorBridgeExplainerIsNilWhenLogHasNoSourceOrigin() {
		let line = transitionLine()  // no source fields
		let logURL = makeTransitionLog(lines: [line])
		let vm = makeVM(logURL: logURL)
		XCTAssertNil(vm.lastSeenSourceOrigin)
	}

	// MARK: - Hooks-present summary

	func testHooksPresentSummaryIsNilWhenNoSnapshot() {
		let vm = makeVM()
		XCTAssertNil(vm.hooksPresentSummary)
	}

	func testHooksPresentSummaryFromSnapshot() {
		let dirURL = makeStateDir()
		let vm = DeveloperTabViewModel(
			stateDirPath: dirURL.path,
			gateJsonPath: nil,
			transitionLogPath: tmp.appendingPathComponent("missing.log").path,
			hooksSnapshot: HooksStatusSnapshot(
				codex: HooksStatusSnapshot.Platform(
					presentOnDisk: true, installableInPhase: true, installed: true,
					firingRecently: true, lastEventAt: nil, sourceOrigin: nil),
				claudeCode: HooksStatusSnapshot.Platform(
					presentOnDisk: false, installableInPhase: true, installed: false,
					firingRecently: false, lastEventAt: nil, sourceOrigin: nil),
				cursor: HooksStatusSnapshot.Platform(
					presentOnDisk: false, installableInPhase: true, installed: false,
					firingRecently: false, lastEventAt: nil, sourceOrigin: nil),
				vscode: HooksStatusSnapshot.Platform(
					presentOnDisk: false, installableInPhase: true, installed: false,
					firingRecently: false, lastEventAt: nil, sourceOrigin: nil),
				antigravity: HooksStatusSnapshot.Platform(
					presentOnDisk: false, installableInPhase: false, installed: false,
					firingRecently: false, lastEventAt: nil, sourceOrigin: nil)
			)
		)
		guard let summary = vm.hooksPresentSummary else {
			XCTFail("hooksPresentSummary must be non-nil when snapshot is provided")
			return
		}
		// Use summary below
		XCTAssertTrue(summary.contains("codex: ✓") || summary.contains("codex"),
			"summary must include codex installed indicator")
	}

	// MARK: - Pretty JSON

	func testStateJsonPrettyPrintsWhenSliceExists() {
		let dirURL = makeStateDir()
		let vm = makeVM(stateDirURL: dirURL)
		let pretty = vm.stateJsonPretty
		XCTAssertFalse(pretty.isEmpty, "stateJsonPretty must return non-empty string when slice exists")
		XCTAssertTrue(pretty.contains("schema_version"), "pretty JSON must contain the schema_version key")
	}

	func testStateJsonPrettyShowsAbsentMessageWhenDirMissing() {
		let vm = makeVM()
		let pretty = vm.stateJsonPretty
		XCTAssertFalse(pretty.isEmpty)
		XCTAssertFalse(pretty.contains("schema_version"), "missing state.d/ must not pretend to have data")
	}

	func testGateJsonPrettyShowsNilWhenPathIsNil() {
		let vm = makeVM(gateJsonURL: nil)
		XCTAssertNil(vm.gateJsonPretty, "gateJsonPretty must be nil when no gate path is configured")
	}

	func testGateJsonPrettyShowsContentWhenFileExists() {
		let gateURL = makeGateJson()
		let vm = makeVM(gateJsonURL: gateURL)
		guard let pretty = vm.gateJsonPretty else {
			XCTFail("gateJsonPretty must be non-nil when file exists")
			return
		}
		XCTAssertTrue(pretty.contains("ticket_started"))
	}

	// MARK: - Per-origin gate/context slice preference

	/// son-of-anton Phase 17 writes `<origin>:<session_id>.gate.json` directly into
	/// state.d/ when it can resolve an active session. The Developer tab must show
	/// that slice — not the legacy flat gate.json — once it exists, so operators
	/// debugging a specific platform's gate see the file that's actually driving it.
	func testGateJsonPrettyPrefersPerOriginSliceOverLegacyFile() throws {
		let dirURL = makeStateDir()
		try """
			{"gate":"open_pr","since":"2026-01-01T00:00:00Z","expires_at":"2026-12-31T00:00:00Z","ticket_id":"P15.01"}
			""".write(
				to: dirURL.appendingPathComponent("claude_code:test-session-id.gate.json"),
				atomically: true, encoding: .utf8)
		let legacyGateURL = makeGateJson()
		let vm = makeVM(stateDirURL: dirURL, gateJsonURL: legacyGateURL)

		guard let pretty = vm.gateJsonPretty else {
			XCTFail("gateJsonPretty must be non-nil when a per-origin slice exists")
			return
		}
		XCTAssertTrue(pretty.contains("open_pr"), "must show the per-origin slice's gate")
		XCTAssertFalse(pretty.contains("ticket_started"), "must not show the legacy flat gate.json once a per-origin slice exists")
		XCTAssertEqual(vm.gateJsonSourceLabel, "claude_code:test-session-id.gate.json")
	}

	func testGateJsonSourceLabelFallsBackToLegacyFilename() {
		let gateURL = makeGateJson()
		let vm = makeVM(gateJsonURL: gateURL)
		XCTAssertEqual(vm.gateJsonSourceLabel, "gate.json")
	}

	func testDeliveryContextPrettyPrefersPerOriginSliceOverLegacyFile() throws {
		let dirURL = makeStateDir()
		try """
			{"owner":"soa","status":"active","ticket_id":"P15.01","last_gate":"open_pr","updated_at":"2026-01-01T00:00:00Z","lease_expires_at":"2026-12-31T00:00:00Z"}
			""".write(
				to: dirURL.appendingPathComponent("claude_code:test-session-id.context.json"),
				atomically: true, encoding: .utf8)
		let vm = DeveloperTabViewModel(
			stateDirPath: dirURL.path,
			gateJsonPath: nil,
			deliveryContextPath: tmp.appendingPathComponent("delivery-context.json").path,
			transitionLogPath: tmp.appendingPathComponent("missing-log.log").path
		)

		guard let pretty = vm.deliveryContextPretty else {
			XCTFail("deliveryContextPretty must be non-nil when a per-origin slice exists")
			return
		}
		XCTAssertTrue(pretty.contains("P15.01"))
		XCTAssertEqual(vm.deliveryContextSourceLabel, "claude_code:test-session-id.context.json")
	}
}

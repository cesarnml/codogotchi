import XCTest

@testable import Codogotchi

/// Behavior contract for `GateJsonReader` and `resolveActivityState` merge resolver.
///
/// All gate.json fixtures are created as tmp files so the tests run cleanly
/// without requiring bundled fixtures.
final class GateJsonReaderTests: XCTestCase {

	// MARK: - GateJsonReader

	func testGateJsonDecodesFull() throws {
		// [red] GateJsonReader must decode all expected fields
		let json = """
			{
			  "gate": "ticket_started",
			  "since": "2026-05-29T12:00:00.000Z",
			  "expires_at": "2099-01-01T00:00:00.000Z",
			  "plan_key": "phase-07",
			  "ticket_id": "P7.01"
			}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNotNil(snapshot, "full gate.json must decode successfully")
		XCTAssertEqual(snapshot?.gate, "ticket_started")
		XCTAssertEqual(snapshot?.planKey, "phase-07")
		XCTAssertEqual(snapshot?.ticketId, "P7.01")
	}

	func testGateJsonMissingFileReturnsNil() {
		// [red] missing gate.json → nil (not an error)
		let snapshot = GateJsonReader.read(at: "/tmp/codogotchi-nonexistent-gate.json")
		XCTAssertNil(snapshot, "missing gate.json must return nil")
	}

	func testGateJsonMalformedReturnsNil() throws {
		// [red] malformed JSON → nil (best-effort, never throws)
		let tmp = writeTemp("{ not json")
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "malformed gate.json must return nil")
	}

	func testGateJsonMissingGateFieldReturnsNil() throws {
		let json = """
			{"since": "2026-05-29T12:00:00.000Z", "expires_at": "2099-01-01T00:00:00.000Z"}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "gate.json missing required 'gate' field must return nil")
	}

	func testGateJsonMissingExpiresAtFieldReturnsNil() throws {
		let json = """
			{"gate": "ticket_started", "since": "2026-05-29T12:00:00.000Z"}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "gate.json missing required 'expires_at' field must return nil")
	}

	func testUnparseableExpiresAtTreatedAsExpired() {
		// Corrupt expires_at must not activate the gate indefinitely
		let gate = makeGate(gate: "ticket_started", expiresAt: "not-a-date")
		let result = resolveActivityState(gate: gate, hookState: .implementing, now: Date())
		XCTAssertEqual(result, .implementing, "unparseable expires_at must fall through to hook state (treated as expired)")
	}

	// MARK: - resolveActivityState merge resolver

	func testUnexpiredGateWithRowRendersGateState() {
		// [red] unexpired gate with a sprite row → gate state wins over hook state
		let gate = makeGate(gate: "ticket_started", expiresAt: futureDate())
		let hookState = ActivityState.implementing
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .ticketStarted, "unexpired ticket_started gate with a row must render ticketStarted")
	}

	func testExpiredGateRendersHookState() {
		// [red] expired gate → fall through to hook state.json activity_state
		let gate = makeGate(gate: "ticket_started", expiresAt: pastDate())
		let hookState = ActivityState.implementing
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .implementing, "expired gate must fall through to hook state")
	}

	func testUnexpiredGateWithUnknownStateRendersHookState() {
		// [red] unexpired gate with an unknown/unmapped state → fall through (skew or artless)
		let gate = makeGate(gate: "some_unknown_gate_state", expiresAt: futureDate())
		let hookState = ActivityState.thinking
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .thinking, "gate with unknown state must fall through to hook state")
	}

	func testUnexpiredGateWithArtlessStateRendersHookState() {
		// [red] unexpired gate for a v4 state that has no sprite row → fall through
		// advance is in ActivityState but not in CodogotchiPet.rowMap
		let gate = makeGate(gate: "advance", expiresAt: futureDate())
		let hookState = ActivityState.idle
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .idle, "gate with no sprite row must fall through to hook state")
	}

	func testAbsentGateRendersHookState() {
		// [red] absent gate.json → hook state only
		let hookState = ActivityState.errored
		let result = resolveActivityState(gate: nil, hookState: hookState, now: Date())
		XCTAssertEqual(result, .errored, "absent gate must render hook state unchanged")
	}

	// MARK: - Helpers

	private func writeTemp(_ content: String) -> URL {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("gate-\(UUID().uuidString).json")
		try? content.write(to: tmp, atomically: true, encoding: .utf8)
		return tmp
	}

	private func futureDate() -> String {
		"2099-01-01T00:00:00.000Z"
	}

	private func pastDate() -> String {
		"2020-01-01T00:00:00.000Z"
	}

	private func makeGate(gate: String, expiresAt: String) -> GateSnapshot {
		GateSnapshot(
			gate: gate,
			since: "2026-05-29T12:00:00.000Z",
			expiresAt: expiresAt,
			planKey: "phase-07",
			ticketId: "P7.01"
		)
	}
}

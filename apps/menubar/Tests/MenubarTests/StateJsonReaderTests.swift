import XCTest

@testable import Codogotchi

/// Behavior contract for `StateJsonReader`.
///
/// Fixtures live in `apps/menubar/Fixtures/state-json/` and are resolved via
/// `#file` so the tests run cleanly under `xcodebuild ... test` without
/// needing the test bundle to embed the fixture folder. The renderer never
/// loads fixtures at runtime, so the test bundle does not need them either.
final class StateJsonReaderTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func fixtureURL(_ name: String) -> URL {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/state-json")
			.appendingPathComponent(name)
	}

	// MARK: - Floor states

	func testIdleFixtureParsesToIdle() {
		let result = StateJsonReader.read(at: fixtureURL("idle.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
		XCTAssertEqual(snapshot.schemaVersion, 1)
	}

	func testImplementingFixtureParsesToImplementing() {
		let result = StateJsonReader.read(at: fixtureURL("implementing.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .implementing)
	}

	func testRunningTestsFixtureFallsBackToIdle() {
		// running-tests is not a v4 state; the unknown-state fallback maps it to .idle
		let result = StateJsonReader.read(at: fixtureURL("running-tests.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	func testTestingFixtureParsesToTesting() {
		let result = StateJsonReader.read(at: fixtureURL("testing.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .testing)
	}

	func testTicketStartedFixtureParsesToTicketStarted() {
		let result = StateJsonReader.read(at: fixtureURL("ticket_started.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .ticketStarted)
	}

	func testCelebratingFixtureFallsBackToIdle() {
		// celebrating is not a v4 state; the unknown-state fallback maps it to .idle
		let result = StateJsonReader.read(at: fixtureURL("celebrating.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	// MARK: - Unknown-state fallback

	func testUnknownActivityStateFallsBackToIdle() {
		let result = StateJsonReader.read(at: fixtureURL("unknown-state.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	// MARK: - Schema policy

	func testNewerSchemaVersionFailsWithSchemaNewer() {
		let result = StateJsonReader.read(at: fixtureURL("schema-newer.json").path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .schemaNewer(let got, let expected) = error else {
			XCTFail("expected schemaNewer, got \(error)")
			return
		}
		XCTAssertEqual(got, 99)
		XCTAssertEqual(expected, 6)
	}

	func testExpectedSchemaVersionIs6() {
		XCTAssertEqual(EXPECTED_STATE_SCHEMA_VERSION, 6)
	}

	func testSchemaVersion4ParsesSuccessfullyAfterV4Bump() throws {
		// After the P7.01 v4 bump, a v4 payload with a valid v4 state must parse cleanly.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v4-ok2-\(UUID().uuidString).json")
		try #"{"schema_version": 4, "activity_state": "idle", "updated_at": "2026-05-29T00:00:00.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.schemaVersion, 4)
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	func testSchemaVersion3WithStandbyParsesSuccessfully() throws {
		// v3 payloads remain parseable under v4 forward-compat (schema_version ≤ 4 accepted).
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v3-standby-\(UUID().uuidString).json")
		try #"{"schema_version": 3, "activity_state": "standby", "updated_at": "2026-05-29T00:00:00.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .standby)
		XCTAssertEqual(snapshot.schemaVersion, 3)
	}

	func testBooleanSchemaVersionReturnsSchemaMissingOrInvalid() throws {
		// JSONSerialization bridges JSON booleans to NSNumber, which would
		// otherwise satisfy `as? Int` and coerce to `1`. The reader must reject
		// `true`/`false` as non-integer schema versions per the contract clause.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("bool-schema-\(UUID().uuidString).json")
		try #"{"schema_version": true, "activity_state": "idle", "updated_at": "x"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .schemaMissingOrInvalid = error else {
			XCTFail("expected schemaMissingOrInvalid, got \(error)")
			return
		}
	}

	func testFloatSchemaVersionReturnsSchemaMissingOrInvalid() throws {
		// `1.0` parses as a floating-point NSNumber from JSONSerialization.
		// The contract describes `schema_version` as an integer; floats are
		// rejected rather than rounded so a future fractional version cannot
		// silently coerce to the current expected value.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("float-schema-\(UUID().uuidString).json")
		try #"{"schema_version": 1.0, "activity_state": "idle", "updated_at": "x"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .schemaMissingOrInvalid = error else {
			XCTFail("expected schemaMissingOrInvalid, got \(error)")
			return
		}
	}

	func testMissingFileReturnsFileNotFound() {
		let result = StateJsonReader.read(
			at: fixtureURL("does-not-exist.json").path
		)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .fileNotFound = error else {
			XCTFail("expected fileNotFound, got \(error)")
			return
		}
	}

	func testMalformedJsonReturnsMalformed() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("malformed-\(UUID().uuidString).json")
		try "{ not json".write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .malformed = error else {
			XCTFail("expected malformed, got \(error)")
			return
		}
	}

	// MARK: - TTL policy (P6.07)

	func testStandbyWithExpiredTTLResolvesToIdle() throws {
		let json = """
			{"schema_version": 3, "activity_state": "standby", "updated_at": "2026-05-29T00:00:00.000Z", "attention": {"expires_at": "2020-01-01T00:00:00.000Z", "reason_kind": "input_requested", "summary": "x", "created_at": "2019-12-31T23:00:00.000Z"}}
			"""
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("ttl-expired-\(UUID().uuidString).json")
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	func testStandbyWithFutureTTLRemainsStandby() throws {
		let json = """
			{"schema_version": 3, "activity_state": "standby", "updated_at": "2026-05-29T00:00:00.000Z", "attention": {"expires_at": "2099-01-01T00:00:00.000Z", "reason_kind": "input_requested", "summary": "x", "created_at": "2026-05-29T00:00:00.000Z"}}
			"""
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("ttl-future-\(UUID().uuidString).json")
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .standby)
	}

	func testStandbyWithNoAttentionRemainsStandby() throws {
		let json = """
			{"schema_version": 3, "activity_state": "standby", "updated_at": "2026-05-29T00:00:00.000Z"}
			"""
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("ttl-absent-\(UUID().uuidString).json")
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .standby)
	}

	func testIdleWithExpiredTTLRemainsIdle() throws {
		let json = """
			{"schema_version": 3, "activity_state": "idle", "updated_at": "2026-05-29T00:00:00.000Z", "attention": {"expires_at": "2020-01-01T00:00:00.000Z", "reason_kind": "input_requested", "summary": "x", "created_at": "2019-12-31T23:00:00.000Z"}}
			"""
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("ttl-idle-expired-\(UUID().uuidString).json")
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	// MARK: - Schema v4 vocabulary (P7.01 — [red])

	func testExpectedSchemaVersionIsV4() {
		// Updated to v5 in P10.06, then v6 for the revive_until bump
		XCTAssertEqual(EXPECTED_STATE_SCHEMA_VERSION, 6)
	}

	func testTicketStartedIsAValidV4State() {
		// [red] ticket_started must be a first-class enum case in v4
		XCTAssertNotNil(ActivityState(rawValue: "ticket_started"))
	}

	func testTestingIsAValidV4State() {
		// [red] testing replaces running-tests in v4
		XCTAssertNotNil(ActivityState(rawValue: "testing"))
	}

	func testHypedIsNotAV4State() {
		// [red] hyped is removed from the closed enum in v4
		XCTAssertNil(ActivityState(rawValue: "hyped"))
	}

	func testRunningTestsIsNotAV4State() {
		// [red] running-tests is replaced by testing in v4
		XCTAssertNil(ActivityState(rawValue: "running-tests"))
	}

	func testSchemaVersion4ParsesSuccessfully() throws {
		// [red] a schema_version 4 payload must parse successfully after the v4 bump
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v4-ok-\(UUID().uuidString).json")
		try #"{"schema_version": 4, "activity_state": "idle", "updated_at": "2026-05-29T00:00:00.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.schemaVersion, 4)
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	func testSchemaVersion5ParsesSuccessfullyAfterV5Bump() throws {
		// [red] v5 must be accepted after the v5 bump
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v5-\(UUID().uuidString).json")
		try #"{"schema_version": 5, "activity_state": "idle", "updated_at": "2026-06-03T00:00:00.000Z", "level": 1, "level_fraction": 0.0, "half_hearts": 6, "last_activity_at": null}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.schemaVersion, 5)
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	// MARK: - Schema v5 RPG fields (P10.06 — [red])

	func testExpectedSchemaVersionIsV5() {
		// Bumped to v6 for the revive_until additive field
		XCTAssertEqual(EXPECTED_STATE_SCHEMA_VERSION, 6)
	}

	func testSchemaVersion6ParsesSuccessfullyAfterV6Bump() throws {
		// v6 adds the optional revive_until field; the reader accepts it and
		// tolerates the extra key (Decodable ignores it).
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v6-\(UUID().uuidString).json")
		try #"{"schema_version": 6, "activity_state": "idle", "updated_at": "2026-06-08T00:00:00.000Z", "level": 1, "level_fraction": 0.0, "half_hearts": 6, "last_activity_at": null, "revive_until": "2026-06-08T00:00:05.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.schemaVersion, 6)
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	func testV6PayloadDecodesReviveUntil() throws {
		// revive_until is carried onto the snapshot so the driver can play the
		// revive celebration during its TTL.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("v6-revive-\(UUID().uuidString).json")
		try #"{"schema_version": 6, "activity_state": "implementing", "updated_at": "2026-06-08T00:00:00.000Z", "level": 1, "level_fraction": 0.0, "half_hearts": 6, "last_activity_at": null, "revive_until": "2026-06-08T00:00:05.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.reviveUntil, "2026-06-08T00:00:05.000Z")
	}

	func testV6PayloadWithNullReviveUntilDecodesNil() throws {
		// Explicit JSON null and an absent key both collapse to nil.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("v6-revive-null-\(UUID().uuidString).json")
		try #"{"schema_version": 6, "activity_state": "idle", "updated_at": "2026-06-08T00:00:00.000Z", "level": 1, "level_fraction": 0.0, "half_hearts": 6, "last_activity_at": null, "revive_until": null}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertNil(snapshot.reviveUntil)
	}

	func testSchemaVersion7FailsWithSchemaNewer() throws {
		// [red] v7 must be refused with schemaNewer(7, 6) after the v6 bump
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("schema-v7-\(UUID().uuidString).json")
		try #"{"schema_version": 7, "activity_state": "idle", "updated_at": "x"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .schemaNewer(let got, let expected) = error else {
			XCTFail("expected schemaNewer, got \(error)")
			return
		}
		XCTAssertEqual(got, 7)
		XCTAssertEqual(expected, 6)
	}

	func testV5PayloadDecodesLevelHalfHeartsAndLevelFraction() throws {
		// [red] a v5 payload must decode level, level_fraction, half_hearts onto the snapshot
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("v5-rpg-fields-\(UUID().uuidString).json")
		try #"{"schema_version": 5, "activity_state": "idle", "updated_at": "2026-06-03T00:00:00.000Z", "level": 42, "level_fraction": 0.25, "half_hearts": 4, "last_activity_at": "2026-06-03T00:00:00.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.level, 42)
		XCTAssertEqual(snapshot.levelFraction, 0.25, accuracy: 0.001)
		XCTAssertEqual(snapshot.halfHearts, 4)
		XCTAssertNotNil(snapshot.lastActivityAt)
	}

	func testV5PayloadNullLastActivityAtDecodesAsNil() throws {
		// [red] null last_activity_at must decode as nil on the snapshot
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("v5-null-laa-\(UUID().uuidString).json")
		try #"{"schema_version": 5, "activity_state": "idle", "updated_at": "2026-06-03T00:00:00.000Z", "level": 1, "level_fraction": 0.0, "half_hearts": 6, "last_activity_at": null}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertNil(snapshot.lastActivityAt)
		XCTAssertEqual(snapshot.halfHearts, 6)
	}

	func testOlderPayloadRPGFieldsFallBackToSafeDefaults() throws {
		// [red] v4 payload missing RPG fields must fall back to safe defaults
		// (level 1, halfHearts 6, levelFraction 0.0, lastActivityAt nil)
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("v4-no-rpg-\(UUID().uuidString).json")
		try #"{"schema_version": 4, "activity_state": "idle", "updated_at": "2026-06-03T00:00:00.000Z"}"#
			.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.level, 1)
		XCTAssertEqual(snapshot.halfHearts, 6)
		XCTAssertEqual(snapshot.levelFraction, 0.0, accuracy: 0.001)
		XCTAssertNil(snapshot.lastActivityAt)
	}
}

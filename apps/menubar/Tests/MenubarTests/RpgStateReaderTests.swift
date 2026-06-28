import XCTest

@testable import Codogotchi

// [red] RpgStateReader and RpgSnapshot do not exist yet — this file causes a
// compile error until the GREEN implementation is added.
final class RpgStateReaderTests: XCTestCase {

	// MARK: - Absent file → safe defaults

	func testAbsentFileReturnsSafeDefaults() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("does-not-exist-rpg-\(UUID().uuidString).json")
		let snapshot = RpgStateReader.read(at: missing.path)
		XCTAssertEqual(snapshot.level, 1)
		XCTAssertEqual(snapshot.levelFraction, 0.0, accuracy: 0.001)
		XCTAssertEqual(snapshot.halfHearts, MAX_HALF_HEARTS)
		XCTAssertEqual(snapshot.activeMinutes, 0)
		XCTAssertNil(snapshot.lastActivityAt)
		XCTAssertNil(snapshot.reviveUntil)
	}

	// MARK: - Valid file → correct field parse

	func testValidFileDecodesAllFields() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("rpg-state-valid-\(UUID().uuidString).json")
		let json = """
			{
			  "level": 12,
			  "level_fraction": 0.75,
			  "half_hearts": 4,
			  "active_minutes": 33,
			  "last_activity_at": "2026-06-28T10:00:00.000Z",
			  "revive_until": "2026-06-28T10:00:05.000Z"
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = RpgStateReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.level, 12)
		XCTAssertEqual(snapshot.levelFraction, 0.75, accuracy: 0.001)
		XCTAssertEqual(snapshot.halfHearts, 4)
		XCTAssertEqual(snapshot.activeMinutes, 33)
		XCTAssertEqual(snapshot.lastActivityAt, "2026-06-28T10:00:00.000Z")
		XCTAssertEqual(snapshot.reviveUntil, "2026-06-28T10:00:05.000Z")
	}

	// MARK: - Missing individual fields → per-field safe defaults

	func testMissingOptionalFieldsFallBackToDefaults() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("rpg-state-partial-\(UUID().uuidString).json")
		// Only level is present; all others absent
		try #"{"level": 7}"#.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = RpgStateReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.level, 7)
		XCTAssertEqual(snapshot.levelFraction, 0.0, accuracy: 0.001)
		XCTAssertEqual(snapshot.halfHearts, MAX_HALF_HEARTS)
		XCTAssertEqual(snapshot.activeMinutes, 0)
		XCTAssertNil(snapshot.lastActivityAt)
		XCTAssertNil(snapshot.reviveUntil)
	}

	// MARK: - Malformed JSON → safe defaults

	func testMalformedJsonReturnsSafeDefaults() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("rpg-state-bad-\(UUID().uuidString).json")
		try "{ not valid json".write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = RpgStateReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.level, 1)
		XCTAssertEqual(snapshot.levelFraction, 0.0, accuracy: 0.001)
		XCTAssertEqual(snapshot.halfHearts, MAX_HALF_HEARTS)
		XCTAssertEqual(snapshot.activeMinutes, 0)
		XCTAssertNil(snapshot.lastActivityAt)
		XCTAssertNil(snapshot.reviveUntil)
	}
}

import XCTest

@testable import Codogotchi

// [red] CustomizationJsonReader, CustomizationSnapshot, and PlatformMode do not
// exist yet — this file causes a compile error until the GREEN implementation is added.
final class CustomizationJsonReaderTests: XCTestCase {

	// MARK: - Absent file → all defaults

	func testAbsentFileReturnsAllDefaults() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("does-not-exist-customization-\(UUID().uuidString).json")
		let snapshot = CustomizationJsonReader.read(at: missing.path)
		XCTAssertEqual(snapshot.platformModes, [:])
		XCTAssertEqual(snapshot.idleDismissTtlSeconds, 300)
		XCTAssertEqual(snapshot.menubarIconMonochrome, false)
		XCTAssertEqual(snapshot.idleImpatientSeconds, 300)
		XCTAssertEqual(snapshot.idleFrustratedSeconds, 600)
		XCTAssertEqual(
			snapshot.evictSessionPetsEnabled, true,
			"Evict Session Pets defaults enabled — a kill-switch on existing behavior, not an opt-in")
	}

	// MARK: - Idle escalation timing + evict-session-pets: round-trip and defaults

	func testIdleEscalationAndEvictionFieldsDecodePopulatedValues() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-escalation-\(UUID().uuidString).json")
		let json = """
			{
			  "idle_impatient_seconds": 1800,
			  "idle_frustrated_seconds": 3600,
			  "evict_session_pets_enabled": false
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.idleImpatientSeconds, 1800)
		XCTAssertEqual(snapshot.idleFrustratedSeconds, 3600)
		XCTAssertEqual(snapshot.evictSessionPetsEnabled, false)
	}

	func testNegativeIdleEscalationSecondsClampToDefaults() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-escalation-neg-\(UUID().uuidString).json")
		let json = """
			{
			  "idle_impatient_seconds": -5,
			  "idle_frustrated_seconds": -5
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.idleImpatientSeconds, 300, "negative impatient seconds must clamp to the 300s default")
		XCTAssertEqual(snapshot.idleFrustratedSeconds, 600, "negative frustrated seconds must clamp to the 600s default")
	}

	func testIdleEscalationZeroIsValidNeverSentinel() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-escalation-zero-\(UUID().uuidString).json")
		let json = """
			{
			  "idle_impatient_seconds": 0,
			  "idle_frustrated_seconds": 0
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.idleImpatientSeconds, 0, "0 must be accepted as the 'Never' sentinel, not clamped")
		XCTAssertEqual(snapshot.idleFrustratedSeconds, 0)
	}

	// MARK: - Valid file → correct parse of modes, TTL, monochrome flag

	func testValidFileDecodesAllFields() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-valid-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": {
			    "claude_code": "combined",
			    "cursor": "off",
			    "codex": "minimalist",
			    "zed": "own"
			  },
			  "idle_dismiss_ttl_seconds": 600,
			  "menubar_icon_monochrome": true
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.platformModes["claude_code"], .combined)
		XCTAssertEqual(snapshot.platformModes["cursor"], .off)
		XCTAssertEqual(snapshot.platformModes["codex"], .minimalist)
		XCTAssertEqual(snapshot.platformModes["zed"], .own)
		XCTAssertEqual(snapshot.idleDismissTtlSeconds, 600)
		XCTAssertEqual(snapshot.menubarIconMonochrome, true)
	}

	// MARK: - Unknown origin key → tolerated (not a parse error)

	func testUnknownOriginKeyInPlatformModesIsTolerated() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-unknown-key-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": {
			    "totally_unknown_platform": "own"
			  },
			  "idle_dismiss_ttl_seconds": 300,
			  "menubar_icon_monochrome": false
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		// Unknown origin key must be parsed without error; mode value is decoded normally
		XCTAssertEqual(snapshot.platformModes["totally_unknown_platform"], .own)
		XCTAssertEqual(snapshot.idleDismissTtlSeconds, 300)
	}

	// MARK: - Invalid mode string → degrades to .own

	func testInvalidModeStringDegradesToOwn() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-bad-mode-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": {
			    "claude_code": "not_a_valid_mode"
			  },
			  "idle_dismiss_ttl_seconds": 300,
			  "menubar_icon_monochrome": false
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.platformModes["claude_code"], .own, "invalid mode string must degrade to .own")
	}

	// MARK: - Negative idle_dismiss_ttl_seconds → clamped to 300

	func testNegativeTtlClampsToDefault() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-neg-ttl-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": {},
			  "idle_dismiss_ttl_seconds": -1,
			  "menubar_icon_monochrome": false
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.idleDismissTtlSeconds, 300, "negative TTL must be clamped to 300s default")
	}

	// MARK: - idle_dismiss_ttl_seconds: 0 → valid (Never)

	func testTtlZeroIsValidNeverDismiss() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-ttl-zero-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": {},
			  "idle_dismiss_ttl_seconds": 0,
			  "menubar_icon_monochrome": false
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.idleDismissTtlSeconds, 0, "ttl=0 must be accepted as a valid 'never dismiss' value")
	}

	// MARK: - Session pets: populated maps decode correctly

	func testSessionPetsFieldsDecodePopulatedMaps() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-session-pets-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": { "claude_code": "own" },
			  "session_pets_enabled": { "claude_code": true, "cursor": false },
			  "session_cap": { "claude_code": 3, "cursor": 5 }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.sessionPetsEnabled["claude_code"], true)
		XCTAssertEqual(snapshot.sessionPetsEnabled["cursor"], false)
		XCTAssertEqual(snapshot.sessionCap["claude_code"], 3)
		XCTAssertEqual(snapshot.sessionCap["cursor"], 5)
	}

	// MARK: - Session pets: absent → empty maps

	func testSessionPetsFieldsAbsentYieldEmptyMaps() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-no-session-pets-\(UUID().uuidString).json")
		let json = """
			{
			  "platform_modes": { "claude_code": "own" },
			  "idle_dismiss_ttl_seconds": 300
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.sessionPetsEnabled, [:], "absent session_pets_enabled must decode to an empty map")
		XCTAssertEqual(snapshot.sessionCap, [:], "absent session_cap must decode to an empty map")
	}

	// MARK: - Session cap: 0 preserved as Unlimited sentinel

	func testSessionCapZeroIsPreservedAsUnlimitedSentinel() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-session-cap-zero-\(UUID().uuidString).json")
		let json = """
			{
			  "session_pets_enabled": { "claude_code": true },
			  "session_cap": { "claude_code": 0 }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(
			snapshot.sessionCap["claude_code"], 0,
			"session_cap=0 must be preserved as the Unlimited sentinel, not clamped by the reader")
	}

	// MARK: - Session pets: malformed value degrades to safe default without throwing

	func testMalformedSessionPetsEnabledDegradesToSafeDefault() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-bad-session-pets-\(UUID().uuidString).json")
		let json = """
			{
			  "session_pets_enabled": { "claude_code": "not_a_bool" }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(
			snapshot.sessionPetsEnabled, [:],
			"a malformed session_pets_enabled value must degrade to the empty-map safe default without throwing")
		// A malformed value throws the whole payload decode, so sessionCap must
		// also fall to the empty-map default. Asserting both closes the gap where
		// a future partial-recovery refactor could keep one map while dropping the
		// other and still pass this test.
		XCTAssertEqual(
			snapshot.sessionCap, [:],
			"a malformed session_pets_enabled must also degrade session_cap to the empty-map safe default")
	}

	// MARK: - Grandfather/activity gate fields: populated maps decode correctly

	func testSessionPetsGateFieldsDecodePopulatedMaps() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-gate-\(UUID().uuidString).json")
		let json = """
			{
			  "session_pets_enabled": { "claude_code": true },
			  "session_pets_activated_at": { "claude_code": "2026-07-03T10:00:00.000Z" },
			  "session_pets_grandfathered_session_id": { "claude_code": "abc-123" }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.sessionPetsActivatedAt["claude_code"], "2026-07-03T10:00:00.000Z")
		XCTAssertEqual(snapshot.sessionPetsGrandfatheredSessionId["claude_code"], "abc-123")
	}

	// MARK: - Grandfather/activity gate fields: absent → empty maps (pre-gate data)

	func testSessionPetsGateFieldsAbsentYieldEmptyMaps() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-no-gate-\(UUID().uuidString).json")
		let json = """
			{
			  "session_pets_enabled": { "claude_code": true }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertEqual(
			snapshot.sessionPetsActivatedAt, [:],
			"absent session_pets_activated_at must decode to an empty map — pre-gate data admits everything")
		XCTAssertEqual(snapshot.sessionPetsGrandfatheredSessionId, [:])
	}

	// MARK: - Session cap: negative value passes through verbatim (no reader clamp)

	func testNegativeSessionCapPassesThroughVerbatim() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-neg-session-cap-\(UUID().uuidString).json")
		let json = """
			{
			  "session_pets_enabled": { "claude_code": true },
			  "session_cap": { "claude_code": -1 }
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = CustomizationJsonReader.read(at: tmp.path)
		// Consumers (P15.04/P15.07/P15.09) own default-3 resolution; the reader
		// must not clamp negatives (unlike the neighboring idle_dismiss_ttl guard)
		// and must not conflate -1 with the 0 Unlimited sentinel.
		XCTAssertEqual(
			snapshot.sessionCap["claude_code"], -1,
			"negative session_cap must pass through verbatim; the reader applies no clamp")
	}
}

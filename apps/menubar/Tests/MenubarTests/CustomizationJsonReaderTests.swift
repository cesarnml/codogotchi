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
}

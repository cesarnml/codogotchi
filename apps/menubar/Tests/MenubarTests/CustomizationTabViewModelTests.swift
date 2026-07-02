import XCTest

@testable import Codogotchi

// [red] CustomizationTabViewModel does not yet expose setSessionPetsEnabled /
// setSessionCap / effectiveSessionCap — this file fails to compile until the
// GREEN implementation lands.
final class CustomizationTabViewModelTests: XCTestCase {
	private func makeTmpPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-vm-\(UUID().uuidString).json").path
	}

	private func readPayload(at path: String) throws -> [String: Any] {
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		return try JSONSerialization.jsonObject(with: data) as! [String: Any]
	}

	// MARK: - setSessionPetsEnabled writes true and preserves platform_modes

	func testSetSessionPetsEnabledWritesTrueAndPreservesPlatformModes() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setMode(.minimalist, for: "claude_code")
		vm.setSessionPetsEnabled(true, for: "claude_code")

		let payload = try readPayload(at: path)
		let sessionPets = payload["session_pets_enabled"] as? [String: Bool]
		XCTAssertEqual(sessionPets?["claude_code"], true)

		let modes = payload["platform_modes"] as? [String: String]
		XCTAssertEqual(
			modes?["claude_code"], "minimalist",
			"setSessionPetsEnabled must merge without clobbering platform_modes")
	}

	// MARK: - setSessionCap writes the int; Unlimited persists as 0

	func testSetSessionCapWritesIntAndUnlimitedPersistsAsZero() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setSessionCap(5, for: "claude_code")
		var payload = try readPayload(at: path)
		var caps = payload["session_cap"] as? [String: Int]
		XCTAssertEqual(caps?["claude_code"], 5)

		vm.setSessionCap(0, for: "claude_code")
		payload = try readPayload(at: path)
		caps = payload["session_cap"] as? [String: Int]
		XCTAssertEqual(caps?["claude_code"], 0, "Unlimited must persist as the 0 sentinel")
	}

	// MARK: - Enabling for the first time yields the default cap 3 at the read point

	func testEnablingForFirstTimeYieldsDefaultCapAtReadPoint() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		XCTAssertNil(vm.sessionCap["claude_code"], "no cap has been persisted yet")
		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			vm.effectiveSessionCap(for: "claude_code"), 3,
			"first enable with no persisted cap must resolve to the default cap of 3 at the read point")
	}

	// MARK: - Toggling mode to Combined does not erase a previously stored cap

	func testTogglingModeToCombinedDoesNotEraseStoredCap() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setMode(.own, for: "claude_code")
		vm.setSessionPetsEnabled(true, for: "claude_code")
		vm.setSessionCap(7, for: "claude_code")

		vm.setMode(.combined, for: "claude_code")

		let payload = try readPayload(at: path)
		let caps = payload["session_cap"] as? [String: Int]
		XCTAssertEqual(
			caps?["claude_code"], 7,
			"switching mode to Combined must not erase a previously stored session cap")
		XCTAssertEqual(
			vm.effectiveSessionCap(for: "claude_code"), 7,
			"the in-memory cap must also survive the mode change")
	}
}

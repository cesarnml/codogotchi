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

	// MARK: - Grandfather/activity gate on off->on toggle (P15-QC)

	private func makeTmpStateDir() -> String {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-vm-state-d-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.path
	}

	private func writeSlice(_ dir: String, filename: String, origin: String, updatedAt: String) {
		try! """
			{ "activity_state": "idle", "updated_at": "\(updatedAt)", "source_event": { "origin": "\(origin)" } }
			""".write(
				to: URL(fileURLWithPath: dir).appendingPathComponent(filename),
				atomically: true, encoding: .utf8)
	}

	func testEnablingSessionPetsGrandfathersTheCurrentWinnerAsSessionOne() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		// Two live sessions; "newer" is the current winner (freshest updated_at).
		writeSlice(stateDir, filename: "claude_code:older.json", origin: "claude_code", updatedAt: "2026-07-03T09:00:00.000Z")
		writeSlice(stateDir, filename: "claude_code:newer.json", origin: "claude_code", updatedAt: "2026-07-03T09:00:05.000Z")
		let vm = CustomizationTabViewModel(filePath: path, stateDirectoryPath: stateDir)

		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			vm.sessionPetsGrandfatheredSessionId["claude_code"], "newer",
			"the current winner (freshest updated_at) must be grandfathered as Session 1")
		XCTAssertNotNil(
			vm.sessionPetsActivatedAt["claude_code"],
			"an activation timestamp must be recorded for the origin")

		let payload = try readPayload(at: path)
		let grandfathered = payload["session_pets_grandfathered_session_id"] as? [String: String]
		XCTAssertEqual(grandfathered?["claude_code"], "newer", "the grandfather must be persisted to disk")
		XCTAssertNotNil(
			payload["session_pets_activated_at"] as? [String: String],
			"the activation timestamp must be persisted to disk")
	}

	func testEnablingSessionPetsWithNoLiveSessionRecordsNoGrandfather() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		let vm = CustomizationTabViewModel(filePath: path, stateDirectoryPath: stateDir)

		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertNil(
			vm.sessionPetsGrandfatheredSessionId["claude_code"],
			"no live session exists to grandfather — the first session with activity after now becomes Session 1 naturally")
		XCTAssertNotNil(vm.sessionPetsActivatedAt["claude_code"])
	}

	func testReenablingAfterTogglingOffResetsTheActivationAndGrandfather() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		writeSlice(stateDir, filename: "claude_code:first.json", origin: "claude_code", updatedAt: "2026-07-03T09:00:00.000Z")
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let vm = CustomizationTabViewModel(
			filePath: path, stateDirectoryPath: stateDir, now: { currentTime })

		vm.setSessionPetsEnabled(true, for: "claude_code")
		let firstActivation = vm.sessionPetsActivatedAt["claude_code"]
		XCTAssertEqual(vm.sessionPetsGrandfatheredSessionId["claude_code"], "first")

		vm.setSessionPetsEnabled(false, for: "claude_code")
		// A new session becomes the winner before the origin is re-enabled, and
		// the clock advances so the two activations are unambiguously distinct.
		writeSlice(stateDir, filename: "claude_code:second.json", origin: "claude_code", updatedAt: "2026-07-03T09:05:00.000Z")
		currentTime = currentTime.addingTimeInterval(3600)
		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			vm.sessionPetsGrandfatheredSessionId["claude_code"], "second",
			"re-enabling must re-grandfather whichever session is winning at THIS toggle, not the previous one")
		XCTAssertNotEqual(
			vm.sessionPetsActivatedAt["claude_code"], firstActivation,
			"re-enabling must overwrite the activation timestamp, not keep the original toggle's")
	}

	func testEnablingSessionPetsCarriesOverThePlainOriginCustomLabelToTheGrandfather() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		let labelPath = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-labels-\(UUID().uuidString).json").path
		defer { try? FileManager.default.removeItem(atPath: labelPath) }
		writeSlice(stateDir, filename: "claude_code:winner.json", origin: "claude_code", updatedAt: "2026-07-03T09:00:00.000Z")
		SessionLabelStore.setLabel("My Renamed Pet", for: "claude_code", at: labelPath)
		let vm = CustomizationTabViewModel(
			filePath: path, stateDirectoryPath: stateDir, sessionLabelPath: labelPath)

		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			SessionLabelStore.label(for: "claude_code:winner", at: labelPath), "My Renamed Pet",
			"the plain-origin custom label must carry over to the grandfathered session's new key")
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

		let sessionPets = payload["session_pets_enabled"] as? [String: Bool]
		XCTAssertEqual(
			sessionPets?["claude_code"], true,
			"switching mode to Combined must not erase a previously stored session-pets enable flag")
	}

	// MARK: - effectiveSessionCap resolves a negative persisted cap to the default

	func testEffectiveSessionCapResolvesNegativeCapToDefault() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		// A negative session_cap can only reach disk via manual edit — the VM
		// itself never writes one — but CustomizationSnapshot's contract says
		// "absent or negative" resolves to the default at the read point.
		let json = """
			{ "session_cap": { "claude_code": -1 } }
			"""
		try json.write(toFile: path, atomically: true, encoding: .utf8)
		let vm = CustomizationTabViewModel(filePath: path)

		XCTAssertEqual(
			vm.effectiveSessionCap(for: "claude_code"), 3,
			"a negative persisted cap must resolve to the default cap of 3, not pass through verbatim")
	}

	// MARK: - effectiveSessionCap passes the Unlimited sentinel (0) through unchanged

	func testEffectiveSessionCapPassesUnlimitedSentinelThrough() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setSessionCap(0, for: "claude_code")

		XCTAssertEqual(
			vm.effectiveSessionCap(for: "claude_code"), 0,
			"0 is the real Unlimited value and must not be treated as absent/negative")
	}
}

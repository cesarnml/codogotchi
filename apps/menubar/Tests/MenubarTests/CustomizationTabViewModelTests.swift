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
			"no session has ever existed to grandfather — the first session with activity after now becomes Session 1 naturally")
		XCTAssertNotNil(vm.sessionPetsActivatedAt["claude_code"])
	}

	// The grandfather lookup must ignore the 2h rendering stale-TTL: toggling
	// sessions on for a platform that has been idle longer than that must
	// still carry the collapsed pet's session identity over, or the activity
	// gate silently excludes every pre-toggle session and the pet the user
	// just had on screen vanishes until brand-new activity.
	func testEnablingSessionPetsGrandfathersAStaleMtimeSlice() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		writeSlice(
			stateDir, filename: "cursor:dormant.json", origin: "cursor",
			updatedAt: "2026-07-03T09:00:00.000Z")
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSinceNow: -3 * 60 * 60)],
			ofItemAtPath: URL(fileURLWithPath: stateDir).appendingPathComponent("cursor:dormant.json").path
		)
		let vm = CustomizationTabViewModel(filePath: path, stateDirectoryPath: stateDir)

		vm.setSessionPetsEnabled(true, for: "cursor")

		XCTAssertEqual(
			vm.sessionPetsGrandfatheredSessionId["cursor"], "dormant",
			"a slice past the rendering stale-TTL must still be grandfathered on toggle")
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

	func testLabelCarryoverDoesNotClobberAPreExistingLabelAtTheGrandfatherKey() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		let labelPath = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-labels-\(UUID().uuidString).json").path
		defer { try? FileManager.default.removeItem(atPath: labelPath) }
		writeSlice(stateDir, filename: "claude_code:winner.json", origin: "claude_code", updatedAt: "2026-07-03T09:00:00.000Z")
		SessionLabelStore.setLabel("Plain Origin Label", for: "claude_code", at: labelPath)
		// The grandfathered session already has its OWN, more specific label —
		// e.g. from a direct rename during an earlier activation cycle.
		SessionLabelStore.setLabel("My Specific Rename", for: "claude_code:winner", at: labelPath)
		let vm = CustomizationTabViewModel(
			filePath: path, stateDirectoryPath: stateDir, sessionLabelPath: labelPath)

		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			SessionLabelStore.label(for: "claude_code:winner", at: labelPath), "My Specific Rename",
			"a pre-existing label already set at the grandfathered session's own key must survive, "
				+ "not be clobbered by the plain-origin label")
	}

	func testActivationTimestampPreservesSubSecondPrecision() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		let preciseNow = Date(timeIntervalSinceReferenceDate: 1_000_000.75)
		let vm = CustomizationTabViewModel(
			filePath: path, stateDirectoryPath: stateDir, now: { preciseNow })

		vm.setSessionPetsEnabled(true, for: "claude_code")

		let stamped = try XCTUnwrap(vm.sessionPetsActivatedAt["claude_code"])
		let parsed = try XCTUnwrap(StateJsonReader.parseISO8601Date(stamped))
		XCTAssertEqual(
			parsed.timeIntervalSinceReferenceDate, preciseNow.timeIntervalSinceReferenceDate,
			accuracy: 0.01,
			"the activation timestamp must preserve sub-second precision — a whole-seconds-only "
				+ "stamp truncates toward the past and can wrongly admit a sibling session that "
				+ "wrote just before the real toggle instant but within the same wall-clock second")
	}

	func testGrandfatherTieBreaksDeterministicallyOnEqualTimestamps() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let stateDir = makeTmpStateDir()
		defer { try? FileManager.default.removeItem(atPath: stateDir) }
		let tied = "2026-07-03T09:00:00.000Z"
		writeSlice(stateDir, filename: "claude_code:zzz-session.json", origin: "claude_code", updatedAt: tied)
		writeSlice(stateDir, filename: "claude_code:aaa-session.json", origin: "claude_code", updatedAt: tied)
		let vm = CustomizationTabViewModel(filePath: path, stateDirectoryPath: stateDir)

		vm.setSessionPetsEnabled(true, for: "claude_code")

		XCTAssertEqual(
			vm.sessionPetsGrandfatheredSessionId["claude_code"], "aaa-session",
			"an exact updated_at tie must resolve deterministically to the lexicographically "
				+ "smallest session id, matching RenderKeyResolver's own tie-break convention — "
				+ "not an arbitrary Dictionary-iteration-order-dependent winner")
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

	// MARK: - setIdleImpatientSeconds bumps Frustrated when it would become invalid

	func testSetIdleImpatientSecondsBumpsFrustratedWhenNoLongerAbove() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		// Defaults: impatient=300 (5m), frustrated=600 (10m). Raising impatient
		// to 30m (1800) leaves frustrated (600) no longer strictly above it.
		vm.setIdleImpatientSeconds(1800)

		XCTAssertEqual(vm.idleImpatientSeconds, 1800)
		XCTAssertEqual(vm.idleFrustratedSeconds, 3600, "frustrated must bump to the next option (60m) above the new impatient")

		let payload = try readPayload(at: path)
		XCTAssertEqual(payload["idle_impatient_seconds"] as? Int, 1800)
		XCTAssertEqual(payload["idle_frustrated_seconds"] as? Int, 3600)
	}

	func testSetIdleImpatientSecondsToNeverAlsoForcesFrustratedToNever() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setIdleFrustratedSeconds(3600)
		vm.setIdleImpatientSeconds(0)  // "Never"

		XCTAssertEqual(vm.idleImpatientSeconds, 0)
		XCTAssertEqual(
			vm.idleFrustratedSeconds, 0,
			"disabling Impatient must also disable Frustrated — otherwise escalation(forElapsed:) still fires .frustrated"
			+ " straight from idle since it's checked before impatientAfter")

		let payload = try readPayload(at: path)
		XCTAssertEqual(payload["idle_frustrated_seconds"] as? Int, 0)
	}

	func testSetIdleImpatientSecondsLeavesFrustratedAloneWhenAlreadyValid() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setIdleFrustratedSeconds(7200)
		vm.setIdleImpatientSeconds(600)

		XCTAssertEqual(vm.idleImpatientSeconds, 600)
		XCTAssertEqual(vm.idleFrustratedSeconds, 7200, "frustrated already sits above the new impatient — must not be touched")
	}

	func testSetIdleImpatientSecondsWrapsFrustratedToNeverPastLastOption() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setIdleImpatientSeconds(7200)  // 120 minutes — the last non-Never option

		XCTAssertEqual(vm.idleImpatientSeconds, 7200)
		XCTAssertEqual(vm.idleFrustratedSeconds, 0, "bumping past the last timed option must wrap frustrated to Never")
	}

	func testSetIdleFrustratedSecondsNeverAdjustsImpatient() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		vm.setIdleFrustratedSeconds(60)  // deliberately below the default impatient (300)

		XCTAssertEqual(vm.idleFrustratedSeconds, 60)
		XCTAssertEqual(vm.idleImpatientSeconds, 300, "setIdleFrustratedSeconds must never adjust impatient")
	}

	// MARK: - setEvictSessionPetsEnabled persists and round-trips

	func testSetEvictSessionPetsEnabledPersistsAndRoundTrips() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		XCTAssertTrue(vm.evictSessionPetsEnabled, "defaults enabled — a kill-switch on existing behavior")

		vm.setEvictSessionPetsEnabled(false)

		XCTAssertFalse(vm.evictSessionPetsEnabled)
		let payload = try readPayload(at: path)
		XCTAssertEqual(payload["evict_session_pets_enabled"] as? Bool, false)

		let reloaded = CustomizationTabViewModel(filePath: path)
		XCTAssertFalse(reloaded.evictSessionPetsEnabled, "value must round-trip through a fresh read")
	}

	// MARK: - reload() re-syncs from an external write

	func testReloadPicksUpAModeSwitchWrittenByAnotherViewModel() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		// The Settings tab's long-lived view model…
		let settingsVM = CustomizationTabViewModel(filePath: path)
		XCTAssertEqual(settingsVM.mode(for: "claude_code"), .own)

		// …goes stale when a right-click mode switch writes through its own
		// short-lived view model (the MenubarApp affordance handlers' path).
		let rightClickVM = CustomizationTabViewModel(filePath: path)
		rightClickVM.setMode(.minimalist, for: "claude_code")
		rightClickVM.setCombinedMinimalistEnabled(true)
		XCTAssertEqual(settingsVM.mode(for: "claude_code"), .own, "stale until reload()")

		settingsVM.reload()

		XCTAssertEqual(settingsVM.mode(for: "claude_code"), .minimalist)
		XCTAssertTrue(settingsVM.combinedMinimalistEnabled)
	}

	func testReloadPicksUpABadgeScaleWrittenByAnotherViewModel() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let settingsVM = CustomizationTabViewModel(filePath: path)
		XCTAssertEqual(settingsVM.minimalistBadgeScale, 1.0)

		// The Panel Size pill's write path (MenubarApp's onPanelSizeChanged
		// handler) uses its own short-lived view model, same as a mode switch.
		// 0.9 sits inside the achievable range, so it round-trips unclamped.
		let pillVM = CustomizationTabViewModel(filePath: path)
		pillVM.setMinimalistBadgeScale(0.9)

		settingsVM.reload()

		XCTAssertEqual(settingsVM.minimalistBadgeScale, 0.9)
	}

	func testSetMinimalistBadgeScaleClampsToTheAchievableCeiling() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let vm = CustomizationTabViewModel(filePath: path)

		// The achievable ceiling (~1.16, from FloatingFramePolicy's max pet
		// width) is well below the hard 1.5 cap — a dial value past it must
		// persist as the ceiling, exactly like the Customization slider.
		vm.setMinimalistBadgeScale(1.5)

		XCTAssertEqual(
			vm.minimalistBadgeScale, Double(GateBadgeLayout.achievableMaxScale),
			accuracy: 0.0001)
	}

	func testReloadRestoresTheDefaultWhenAModeSwitchRemovedTheEntry() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let settingsVM = CustomizationTabViewModel(filePath: path)
		settingsVM.setMode(.minimalist, for: "cursor")

		// "Pet Mode" writes .own, which removes the platform_modes entry
		// (own is the default) — reload must fall back to .own, not keep the
		// stale .minimalist.
		let rightClickVM = CustomizationTabViewModel(filePath: path)
		rightClickVM.setMode(.own, for: "cursor")

		settingsVM.reload()

		XCTAssertEqual(settingsVM.mode(for: "cursor"), .own)
	}
}

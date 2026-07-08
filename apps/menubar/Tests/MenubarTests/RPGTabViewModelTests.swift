import XCTest

@testable import Codogotchi

/// Behavior contract for `RPGTabViewModel` (P10.08).
///
/// All tests in this file are written before the implementation — they are
/// expected to FAIL with the stub shipped in the same `[red]` commit.
final class RPGTabViewModelTests: XCTestCase {
	private var tmp: URL!
	private var configURL: URL!
	private var assignmentsURL: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("RPGTabViewModelTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		configURL = tmp.appendingPathComponent("config.json")
		assignmentsURL = tmp.appendingPathComponent("assignments.json")
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Default state

	func testRPGHUDEnabledDefaultsToTrueWhenConfigAbsent() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertTrue(vm.rpgHUDEnabled, "HUD is enabled by default when config is absent")
	}

	// MARK: - Toggle persistence

	func testToggleOffSetsPropertyFalse() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setRPGHUDEnabled(false)
		XCTAssertFalse(vm.rpgHUDEnabled, "property must update immediately after setRPGHUDEnabled(false)")
	}

	func testToggleOffWritesConfigFlag() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setRPGHUDEnabled(false)
		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertFalse(vm2.rpgHUDEnabled, "rpg_hud_enabled=false must persist so a fresh VM reads false")
	}

	func testToggleOnWritesConfigFlag() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setRPGHUDEnabled(false)
		vm.setRPGHUDEnabled(true)
		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertTrue(vm2.rpgHUDEnabled, "rpg_hud_enabled=true must persist so a fresh VM reads true")
	}

	// MARK: - Preview state

	func testPreviewStateFallsBackToFullHearts() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.halfHearts, MAX_HALF_HEARTS)
		XCTAssertEqual(vm.hearts, [.full, .full, .full])
	}

	func testPreviewStateReadsRPGStateFile() throws {
		let stateURL = tmp.appendingPathComponent("rpg-state.json")
		try """
			{
			  "level": 47,
			  "level_fraction": 0.72,
			  "half_hearts": 5,
			  "active_minutes": 23
			}
			""".write(to: stateURL, atomically: true, encoding: .utf8)

		let vm = RPGTabViewModel(configURL: configURL, rpgStatePath: stateURL.path, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.level, 47)
		XCTAssertEqual(vm.ringFraction, 0.72, accuracy: 0.001)
		XCTAssertEqual(vm.xpPercentText, "72%")
		XCTAssertEqual(vm.hearts, [.full, .full, .half])
	}

	func testPreviewPetReadsDefaultAssignment() throws {
		try """
			{
			  "schema_version": 1,
			  "default": "maew"
			}
			""".write(to: assignmentsURL, atomically: true, encoding: .utf8)

		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)

		XCTAssertEqual(vm.petName, "maew")
	}

	func testRefreshRecomputesPreviewPetWhenDefaultAssignmentChanges() throws {
		try """
			{
			  "schema_version": 1,
			  "default": "dario"
			}
			""".write(to: assignmentsURL, atomically: true, encoding: .utf8)
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.petName, "dario")

		try """
			{
			  "schema_version": 1,
			  "default": "maew"
			}
			""".write(to: assignmentsURL, atomically: true, encoding: .utf8)
		vm.refresh()

		XCTAssertEqual(vm.petName, "maew")
	}

	func testHealthLogicDefaultsMatchHardcodedRuntimeValues() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.healthLogic.inactivityDecayHours, 8)
		XCTAssertEqual(vm.healthLogic.inactivityDecayHalfHearts, 1)
		XCTAssertEqual(vm.healthLogic.activityRegenMinutes, 60)
		XCTAssertEqual(vm.healthLogic.activityRegenHalfHearts, 1)
		XCTAssertTrue(vm.healthLogic.diseaseAnimationsEnabled)
	}

	func testHealthLogicPersistsDiseaseAnimationToggle() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setDiseaseAnimationsEnabled(false)

		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertFalse(vm2.healthLogic.diseaseAnimationsEnabled)
	}

	func testHealthLogicPersistsTimingSettings() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setInactivityDecayHours(12)
		vm.setActivityRegenMinutes(30)

		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm2.healthLogic.inactivityDecayHours, 12)
		XCTAssertEqual(vm2.healthLogic.inactivityDecayHalfHearts, 1)
		XCTAssertEqual(vm2.healthLogic.activityRegenMinutes, 30)
		XCTAssertEqual(vm2.healthLogic.activityRegenHalfHearts, 1)
	}
}

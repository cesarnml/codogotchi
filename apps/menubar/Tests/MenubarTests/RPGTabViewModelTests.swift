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

	func testHUDModeDefaultsToMostRecentWhenConfigAbsent() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.hudMode, .mostRecent, "HUD defaults to Most Recent Pet when config is absent")
	}

	// MARK: - Mode persistence

	func testSettingHiddenSetsPropertyImmediately() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setHUDMode(.hidden)
		XCTAssertEqual(vm.hudMode, .hidden, "property must update immediately after setHUDMode(.hidden)")
	}

	func testSettingHiddenWritesConfig() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setHUDMode(.hidden)
		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm2.hudMode, .hidden, "rpg_hud_mode=hidden must persist so a fresh VM reads it")
	}

	func testSettingAllWritesConfig() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setHUDMode(.hidden)
		vm.setHUDMode(.all)
		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm2.hudMode, .all, "rpg_hud_mode=all must persist so a fresh VM reads it")
	}

	// MARK: - Preview state

	func testPreviewStateFallsBackToFullHearts() {
		// rpgStatePath must be injected: the default points at the real
		// ~/.codogotchi/rpg-state.json, making the assertion depend on the
		// developer's live pet health.
		let vm = RPGTabViewModel(
			configURL: configURL,
			rpgStatePath: tmp.appendingPathComponent("absent-rpg-state.json").path,
			assignmentsURL: assignmentsURL)
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
		XCTAssertTrue(vm.healthLogic.skipWeekends)
		XCTAssertEqual(vm.healthLogic.mildSicknessHalfHearts, 2, "mild default = 1 heart")
		XCTAssertEqual(vm.healthLogic.severeSicknessHalfHearts, 1, "severe default = 1/2 heart")
	}

	func testSkipWeekendsPersists() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setSkipWeekends(true)

		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertTrue(vm2.healthLogic.skipWeekends)
	}

	func testSicknessTriggersPersist() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setMildSicknessHalfHearts(4)
		vm.setSevereSicknessHalfHearts(3)

		let vm2 = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm2.healthLogic.mildSicknessHalfHearts, 4)
		XCTAssertEqual(vm2.healthLogic.severeSicknessHalfHearts, 3)
	}

	func testLoweringMildSnapsInvalidSevereToMaximalValidOption() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		vm.setMildSicknessHalfHearts(4)
		vm.setSevereSicknessHalfHearts(3)

		// Severe (3) is no longer strictly below the new mild (2) → snaps to 1.
		vm.setMildSicknessHalfHearts(2)
		XCTAssertEqual(vm.healthLogic.severeSicknessHalfHearts, 1)

		// Mild = Never forces severe to Never too.
		vm.setMildSicknessHalfHearts(0)
		XCTAssertEqual(vm.healthLogic.severeSicknessHalfHearts, 0)
	}

	func testSevereRejectsValuesNotBelowMild() {
		let vm = RPGTabViewModel(configURL: configURL, assignmentsURL: assignmentsURL)
		XCTAssertEqual(vm.healthLogic.mildSicknessHalfHearts, 2)
		vm.setSevereSicknessHalfHearts(2)
		XCTAssertEqual(
			vm.healthLogic.severeSicknessHalfHearts, 1,
			"severe == mild is invalid; the prior value must survive")
	}

	func testSevereOptionsAreExclusivelyCappedByMild() {
		XCTAssertEqual(RPGTabViewModel.severeSicknessOptions(mild: 4), [0, 1, 2, 3])
		XCTAssertEqual(RPGTabViewModel.severeSicknessOptions(mild: 2), [0, 1])
		XCTAssertEqual(RPGTabViewModel.severeSicknessOptions(mild: 0), [0])
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

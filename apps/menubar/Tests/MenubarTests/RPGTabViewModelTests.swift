import XCTest

@testable import Codogotchi

/// Behavior contract for `RPGTabViewModel` (P10.08).
///
/// All tests in this file are written before the implementation — they are
/// expected to FAIL with the stub shipped in the same `[red]` commit.
final class RPGTabViewModelTests: XCTestCase {
	private var tmp: URL!
	private var configURL: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("RPGTabViewModelTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		configURL = tmp.appendingPathComponent("config.json")
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Default state

	func testRPGHUDEnabledDefaultsToTrueWhenConfigAbsent() {
		let vm = RPGTabViewModel(configURL: configURL)
		XCTAssertTrue(vm.rpgHUDEnabled, "HUD is enabled by default when config is absent")
	}

	// MARK: - Toggle persistence

	func testToggleOffSetsPropertyFalse() {
		let vm = RPGTabViewModel(configURL: configURL)
		vm.setRPGHUDEnabled(false)
		XCTAssertFalse(vm.rpgHUDEnabled, "property must update immediately after setRPGHUDEnabled(false)")
	}

	func testToggleOffWritesConfigFlag() {
		let vm = RPGTabViewModel(configURL: configURL)
		vm.setRPGHUDEnabled(false)
		let vm2 = RPGTabViewModel(configURL: configURL)
		XCTAssertFalse(vm2.rpgHUDEnabled, "rpg_hud_enabled=false must persist so a fresh VM reads false")
	}

	func testToggleOnWritesConfigFlag() {
		let vm = RPGTabViewModel(configURL: configURL)
		vm.setRPGHUDEnabled(false)
		vm.setRPGHUDEnabled(true)
		let vm2 = RPGTabViewModel(configURL: configURL)
		XCTAssertTrue(vm2.rpgHUDEnabled, "rpg_hud_enabled=true must persist so a fresh VM reads true")
	}

	// MARK: - Demo state

	func testDemoStateHasFullishHearts() {
		let vm = RPGTabViewModel(configURL: configURL)
		XCTAssertGreaterThan(vm.demoHalfHearts, 2, "demo should show full-ish hearts (>2 half-hearts)")
	}

	func testDemoStateHasMidLevel() {
		let vm = RPGTabViewModel(configURL: configURL)
		XCTAssertGreaterThan(vm.demoLevel, 1, "demo should show a mid-level (>1)")
	}

	func testDemoStateHasPartialRingFraction() {
		let vm = RPGTabViewModel(configURL: configURL)
		XCTAssertGreaterThan(vm.demoRingFraction, 0.0, "demo ring should be partially filled (>0)")
	}
}

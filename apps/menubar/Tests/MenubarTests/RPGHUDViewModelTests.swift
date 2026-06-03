import CoreGraphics
import XCTest

@testable import Codogotchi

/// Behavior contract for `RPGHUDViewModel` (P10.07).
///
/// All tests in this file are written before the implementation — they are
/// expected to FAIL with the stub shipped in the same `[red]` commit.
final class RPGHUDViewModelTests: XCTestCase {

	// MARK: - hearts(from:) — slot derivation

	/// 6 half-hearts → 3 full hearts
	func testHeartsAllFull() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 6), [.full, .full, .full])
	}

	/// 5 half-hearts → slot0 full, slot1 full, slot2 half
	func testHeartsOneDimmed() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 5), [.full, .full, .half])
	}

	/// 4 half-hearts → slot0 full, slot1 full, slot2 empty
	func testHeartsTwoFullOneEmpty() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 4), [.full, .full, .empty])
	}

	/// 3 half-hearts → slot0 full, slot1 half, slot2 empty
	func testHeartsOneFullOneHalfOneEmpty() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 3), [.full, .half, .empty])
	}

	/// 2 half-hearts → slot0 full, slot1 empty, slot2 empty
	func testHeartsOneFullTwoEmpty() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 2), [.full, .empty, .empty])
	}

	/// 1 half-heart → slot0 half, slot1 empty, slot2 empty
	func testHeartsOneHalfTwoEmpty() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 1), [.half, .empty, .empty])
	}

	/// 0 half-hearts → all empty
	func testHeartsAllEmpty() {
		XCTAssertEqual(RPGHUDViewModel.hearts(from: 0), [.empty, .empty, .empty])
	}

	/// Static helper always returns exactly 3 slots
	func testHeartsCountIsAlwaysThree() {
		for n in 0...6 {
			XCTAssertEqual(RPGHUDViewModel.hearts(from: n).count, 3, "count for halfHearts=\(n)")
		}
	}

	// MARK: - update — ring fraction and level

	func testRingFractionPropagates() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.75, level: 5, hudEnabled: true)
		XCTAssertEqual(vm.ringFraction, 0.75, accuracy: 1e-9)
	}

	func testLevelPropagates() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 7, hudEnabled: true)
		XCTAssertEqual(vm.level, 7)
	}

	/// `hearts` on the view-model should mirror the static helper after update.
	func testHeartsFieldMirrorsHelper() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 3, levelFraction: 0.5, level: 1, hudEnabled: true)
		XCTAssertEqual(vm.hearts, RPGHUDViewModel.hearts(from: 3))
	}

	// MARK: - Flash events — delta-driven, no flash on first render

	func testNoFlashOnFirstUpdate() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, hudEnabled: true)
		XCTAssertTrue(flashes.isEmpty, "first render must not fire any flash")
	}

	func testHeartInjuredFlashOnDecrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.heartInjured), "decrease should fire .heartInjured")
	}

	func testHeartHealedFlashOnIncrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 4, levelFraction: 0.0, level: 1, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.heartHealed), "increase should fire .heartHealed")
	}

	func testNoHeartFlashWhenHalfHeartsUnchanged() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, hudEnabled: true)
		let heartFlashes = flashes.filter { $0 == .heartInjured || $0 == .heartHealed }
		XCTAssertTrue(heartFlashes.isEmpty, "no flash when halfHearts unchanged")
	}

	// MARK: - Flash events — level-up and milestone

	func testLevelUpFlashOnLevelIncrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.1, level: 2, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.levelUp), "level increase should fire .levelUp")
	}

	func testNoLevelUpFlashWhenLevelUnchanged() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 5, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 5, hudEnabled: true)
		XCTAssertFalse(flashes.contains(.levelUp), "no level-up flash when level unchanged")
	}

	func testMilestoneBurstAtMilestoneLevel() {
		for milestone in [10, 25, 50, 75, 100] {
			let vm = RPGHUDViewModel()
			var flashes: [RPGFlashEvent] = []
			vm.onFlash = { flashes.append($0) }
			vm.update(halfHearts: 6, levelFraction: 0.0, level: milestone - 1, hudEnabled: true) // prime
			flashes.removeAll()
			vm.update(halfHearts: 6, levelFraction: 0.0, level: milestone, hudEnabled: true)
			XCTAssertTrue(
				flashes.contains(.milestoneBurst),
				"milestone burst expected at level \(milestone)"
			)
		}
	}

	func testNoMilestoneBurstAtNonMilestoneLevel() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 4, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 5, hudEnabled: true)
		XCTAssertFalse(
			flashes.contains(.milestoneBurst),
			"no milestone burst at non-milestone level 5"
		)
	}

	func testMilestoneBurstAlsoFiresLevelUp() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 9, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 10, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.levelUp), "milestone level should also fire .levelUp")
		XCTAssertTrue(flashes.contains(.milestoneBurst), "milestone level should fire .milestoneBurst")
	}

	// MARK: - HUD opt-out flag

	func testHUDEnabledWhenFlagTrue() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 1, hudEnabled: true)
		XCTAssertTrue(vm.isHUDEnabled)
	}

	func testHUDDisabledWhenFlagFalse() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 1, hudEnabled: false)
		XCTAssertFalse(vm.isHUDEnabled, "rpg_hud_enabled=false must set isHUDEnabled=false")
	}

	func testHUDOptOutSuppressesEvenWhenOtherFieldsValid() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.99, level: 50, hudEnabled: false)
		XCTAssertFalse(vm.isHUDEnabled, "opt-out suppresses HUD regardless of other values")
	}

	// MARK: - Layout: shrink-aware left offset

	/// A wide on-screen area so placement is never clamped to the screen edge.
	private static let roomyVisibleFrame = CGRect(x: 0, y: 0, width: 4000, height: 3000)

	private func hudFrame(petWidth: CGFloat, petMinX: CGFloat = 1000) -> CGRect {
		let petFrame = CGRect(x: petMinX, y: 800, width: petWidth, height: petWidth * 1.2)
		let metrics = RPGHUDLayout.metrics(for: petFrame)
		let size = RPGHUDLayout.panelSize(metrics)
		return RPGHUDLayout.frame(
			hudSize: size,
			metrics: metrics,
			relativeTo: petFrame,
			visibleFrame: Self.roomyVisibleFrame
		)
	}

	/// At max scale (pet width ≥ baseline×1.5) the HUD's panel left edge aligns
	/// with the pet frame's left edge — no extra leftward shift.
	func testNoLeftShiftAtMaxPetFrame() {
		let petMinX: CGFloat = 1000
		let frame = hudFrame(petWidth: 330, petMinX: petMinX)
		XCTAssertEqual(frame.minX, petMinX, accuracy: 0.5, "no left shift expected at max pet frame")
	}

	/// Below max scale the HUD slides left of the pet frame's left edge.
	func testLeftShiftWhenPetFrameShrinks() {
		let petMinX: CGFloat = 1000
		let mid = hudFrame(petWidth: 220, petMinX: petMinX)
		let small = hudFrame(petWidth: 165, petMinX: petMinX)
		XCTAssertLessThan(mid.minX, petMinX, "mid pet frame should shift HUD left of the frame edge")
		XCTAssertLessThan(
			small.minX, mid.minX, "smaller pet frame should shift the HUD further left than mid")
	}
}

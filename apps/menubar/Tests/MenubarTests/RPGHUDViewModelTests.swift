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

	/// Regression (P10.08-B): a live Settings toggle flips visibility without a
	/// new RPG poll. `setHUDEnabled` must update `isHUDEnabled` while leaving the
	/// last-rendered snapshot (hearts/ring/level) untouched and firing no flash.
	func testSetHUDEnabledFlipsVisibilityWithoutDisturbingSnapshotOrFlashing() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 3, levelFraction: 0.5, level: 7, hudEnabled: true)
		flashes.removeAll()

		vm.setHUDEnabled(false)
		XCTAssertFalse(vm.isHUDEnabled)
		vm.setHUDEnabled(true)
		XCTAssertTrue(vm.isHUDEnabled)

		// Snapshot preserved; no flash events from a visibility-only change.
		XCTAssertEqual(vm.hearts, RPGHUDViewModel.hearts(from: 3))
		XCTAssertEqual(vm.ringFraction, 0.5)
		XCTAssertEqual(vm.level, 7)
		XCTAssertTrue(flashes.isEmpty, "visibility toggle must not emit flash events")
	}

	// MARK: - Death state

	func testIsDeadOnlyWhenAllHeartsEmpty() {
		let vm = RPGHUDViewModel()
		XCTAssertFalse(vm.isDead, "no snapshot yet → not dead")
		vm.update(halfHearts: 1, levelFraction: 0, level: 1, hudEnabled: true)
		XCTAssertFalse(vm.isDead, "a half-heart remains → alive")
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, hudEnabled: true)
		XCTAssertTrue(vm.isDead, "0 half-hearts → dead")
	}

	/// The tombstone + grayscale belong to the RPG HUD: when the HUD is disabled
	/// the death presentation must be off even while the pet is dead, and it must
	/// return when the HUD is re-enabled.
	func testShowsDeathPresentationGatedByHUDEnabled() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, hudEnabled: true)
		XCTAssertTrue(vm.showsDeathPresentation, "dead + HUD enabled → death visuals show")

		// Live toggle off → death visuals suppressed though still dead.
		vm.setHUDEnabled(false)
		XCTAssertTrue(vm.isDead)
		XCTAssertFalse(vm.showsDeathPresentation, "HUD off must recolor pet + drop tombstone")

		// Re-enable → death visuals return (still dead).
		vm.setHUDEnabled(true)
		XCTAssertTrue(vm.showsDeathPresentation)

		// A poll arriving with the HUD opted out also suppresses death visuals.
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, hudEnabled: false)
		XCTAssertFalse(vm.showsDeathPresentation)
	}

	func testShowsDeathPresentationFalseWhenAlive() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 4, levelFraction: 0.2, level: 3, hudEnabled: true)
		XCTAssertFalse(vm.showsDeathPresentation)
	}

	// MARK: - Layout: opaque-bounds anchoring

	/// A wide on-screen area so placement is never clamped to the screen edge.
	private static let roomyVisibleFrame = CGRect(x: 0, y: 0, width: 4000, height: 3000)

	private func metrics(petWidth: CGFloat, petMinX: CGFloat = 1000)
		-> (RPGHUDLayout.Metrics, CGSize, CGRect)
	{
		let petFrame = CGRect(x: petMinX, y: 800, width: petWidth, height: petWidth * 1.2)
		let m = RPGHUDLayout.metrics(for: petFrame)
		return (m, RPGHUDLayout.panelSize(m), petFrame)
	}

	/// Without a sprite anchor the HUD falls back to the pet frame's top-left
	/// inset (content corner at the frame's left edge).
	func testFallbackAnchorsToFrameTopLeft() {
		let (m, size, petFrame) = metrics(petWidth: 220)
		let frame = RPGHUDLayout.frame(
			hudSize: size, metrics: m, relativeTo: petFrame, spriteAnchor: nil,
			visibleFrame: Self.roomyVisibleFrame)
		// Content corner = panel.minX + glowPad == petFrame.minX + inset.
		XCTAssertEqual(frame.minX + m.glowPad, petFrame.minX + m.inset, accuracy: 0.5)
	}

	/// With a sprite anchor, the HUD's content right edge sits a proportional gap
	/// to the left of the sprite's opaque left edge — independent of where the
	/// pet frame's own left edge is.
	func testAnchorsGapLeftOfSpriteOpaqueEdge() {
		let (m, size, petFrame) = metrics(petWidth: 220)
		let anchor = CGRect(x: 1180, y: 820, width: 150, height: 260)
		let frame = RPGHUDLayout.frame(
			hudSize: size, metrics: m, relativeTo: petFrame, spriteAnchor: anchor,
			visibleFrame: Self.roomyVisibleFrame)
		let gap = (anchor.width * RPGHUDLayout.gapFraction).rounded()
		let contentRight = frame.minX + m.glowPad + m.contentWidth
		XCTAssertEqual(contentRight, anchor.minX - gap, accuracy: 0.5)
	}

	/// The gap scales with the sprite's opaque width, keeping it proportional.
	func testGapScalesWithSpriteWidth() {
		let (m, size, petFrame) = metrics(petWidth: 220)
		func contentRight(forAnchorWidth w: CGFloat) -> CGFloat {
			let anchor = CGRect(x: 1180, y: 820, width: w, height: 260)
			let frame = RPGHUDLayout.frame(
				hudSize: size, metrics: m, relativeTo: petFrame, spriteAnchor: anchor,
				visibleFrame: Self.roomyVisibleFrame)
			return frame.minX + m.glowPad + m.contentWidth
		}
		// Wider sprite → larger gap → content right edge pushed further left.
		XCTAssertLessThan(contentRight(forAnchorWidth: 200), contentRight(forAnchorWidth: 120))
	}

	// MARK: - Layout: tombstone (death marker)

	/// The tombstone's left edge sits a proportional gap to the **right** of the
	/// sprite's opaque right edge (mirror of the HUD's left-side anchoring), sized
	/// to the XP ring.
	func testTombstoneAnchorsGapRightOfSpriteOpaqueEdge() {
		let (m, _, petFrame) = metrics(petWidth: 220)
		let anchor = CGRect(x: 1180, y: 820, width: 150, height: 260)
		let tomb = RPGHUDLayout.tombstoneFrame(
			relativeTo: petFrame, spriteAnchor: anchor, visibleFrame: Self.roomyVisibleFrame)
		let gap = (anchor.width * RPGHUDLayout.gapFraction).rounded()
		XCTAssertEqual(tomb.minX, anchor.maxX + gap, accuracy: 0.5)
		XCTAssertEqual(tomb.width, m.ringDiameter * 2, accuracy: 0.5)
		XCTAssertEqual(tomb.height, m.ringDiameter * 2, accuracy: 0.5)
	}

	/// The tombstone is vertically centered on the HUD's XP ring.
	func testTombstoneVerticallyCentersOnXPRing() {
		let (m, size, petFrame) = metrics(petWidth: 220)
		let anchor = CGRect(x: 1180, y: 820, width: 150, height: 260)
		let hud = RPGHUDLayout.frame(
			hudSize: size, metrics: m, relativeTo: petFrame, spriteAnchor: anchor,
			visibleFrame: Self.roomyVisibleFrame)
		// Ring sits at the panel's bottom-left, inset by glowPad.
		let ringCenterY = hud.minY + m.glowPad + m.ringDiameter / 2
		let tomb = RPGHUDLayout.tombstoneFrame(
			relativeTo: petFrame, spriteAnchor: anchor, visibleFrame: Self.roomyVisibleFrame)
		XCTAssertEqual(tomb.midY, ringCenterY, accuracy: 1.5)
	}

	/// Without a sprite anchor the tombstone hugs the right inside edge of the pet
	/// frame (mirror of the HUD's left-inset fallback).
	func testTombstoneFallbackHugsFrameRightInset() {
		let (m, _, petFrame) = metrics(petWidth: 220)
		let tomb = RPGHUDLayout.tombstoneFrame(
			relativeTo: petFrame, spriteAnchor: nil, visibleFrame: Self.roomyVisibleFrame)
		XCTAssertEqual(tomb.maxX, petFrame.maxX - m.inset, accuracy: 0.5)
	}
}

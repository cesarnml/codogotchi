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
		vm.update(halfHearts: 6, levelFraction: 0.75, level: 5, activeMinutes: 0, hudEnabled: true)
		XCTAssertEqual(vm.ringFraction, 0.75, accuracy: 1e-9)
	}

	func testLevelPropagates() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 7, activeMinutes: 0, hudEnabled: true)
		XCTAssertEqual(vm.level, 7)
	}

	/// `hearts` on the view-model should mirror the static helper after update.
	func testHeartsFieldMirrorsHelper() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 3, levelFraction: 0.5, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertEqual(vm.hearts, RPGHUDViewModel.hearts(from: 3))
	}

	// MARK: - Flash events — delta-driven, no flash on first render

	func testNoFlashOnFirstUpdate() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(flashes.isEmpty, "first render must not fire any flash")
	}

	func testHeartInjuredFlashOnDecrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.heartInjured), "decrease should fire .heartInjured")
	}

	func testHeartHealedFlashOnIncrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 4, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.heartHealed), "increase should fire .heartHealed")
	}

	func testNoHeartFlashWhenHalfHeartsUnchanged() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 5, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true)
		let heartFlashes = flashes.filter { $0 == .heartInjured || $0 == .heartHealed }
		XCTAssertTrue(heartFlashes.isEmpty, "no flash when halfHearts unchanged")
	}

	// MARK: - Flash events — level-up and milestone

	func testLevelUpFlashOnLevelIncrease() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 1, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.1, level: 2, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.levelUp), "level increase should fire .levelUp")
	}

	func testNoLevelUpFlashWhenLevelUnchanged() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 5, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 5, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(flashes.contains(.levelUp), "no level-up flash when level unchanged")
	}

	func testMilestoneBurstAtMilestoneLevel() {
		for milestone in [10, 25, 50, 75, 100] {
			let vm = RPGHUDViewModel()
			var flashes: [RPGFlashEvent] = []
			vm.onFlash = { flashes.append($0) }
			vm.update(halfHearts: 6, levelFraction: 0.0, level: milestone - 1, activeMinutes: 0, hudEnabled: true) // prime
			flashes.removeAll()
			vm.update(halfHearts: 6, levelFraction: 0.0, level: milestone, activeMinutes: 0, hudEnabled: true)
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
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 4, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 5, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(
			flashes.contains(.milestoneBurst),
			"no milestone burst at non-milestone level 5"
		)
	}

	func testMilestoneBurstAlsoFiresLevelUp() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 9, activeMinutes: 0, hudEnabled: true) // prime
		flashes.removeAll()
		vm.update(halfHearts: 6, levelFraction: 0.0, level: 10, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(flashes.contains(.levelUp), "milestone level should also fire .levelUp")
		XCTAssertTrue(flashes.contains(.milestoneBurst), "milestone level should fire .milestoneBurst")
	}

	// MARK: - HUD opt-out flag

	func testHUDEnabledWhenFlagTrue() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(vm.isHUDEnabled)
	}

	func testHUDDisabledWhenFlagFalse() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.5, level: 1, activeMinutes: 0, hudEnabled: false)
		XCTAssertFalse(vm.isHUDEnabled, "rpg_hud_enabled=false must set isHUDEnabled=false")
	}

	func testHUDOptOutSuppressesEvenWhenOtherFieldsValid() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 6, levelFraction: 0.99, level: 50, activeMinutes: 0, hudEnabled: false)
		XCTAssertFalse(vm.isHUDEnabled, "opt-out suppresses HUD regardless of other values")
	}

	/// Regression (P10.08-B): a live Settings toggle flips visibility without a
	/// new RPG poll. `setHUDEnabled` must update `isHUDEnabled` while leaving the
	/// last-rendered snapshot (hearts/ring/level) untouched and firing no flash.
	func testSetHUDEnabledFlipsVisibilityWithoutDisturbingSnapshotOrFlashing() {
		let vm = RPGHUDViewModel()
		var flashes: [RPGFlashEvent] = []
		vm.onFlash = { flashes.append($0) }
		vm.update(halfHearts: 3, levelFraction: 0.5, level: 7, activeMinutes: 0, hudEnabled: true)
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

	// MARK: - Ghost state

	func testIsGhostedOnlyWhenAllHeartsEmpty() {
		let vm = RPGHUDViewModel()
		XCTAssertFalse(vm.isGhosted, "no snapshot yet → not ghosted")
		vm.update(halfHearts: 1, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(vm.isGhosted, "a half-heart remains → alive")
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(vm.isGhosted, "0 half-hearts → ghosted")
	}

	/// The tombstone + grayscale belong to the RPG HUD: when the HUD is disabled
	/// the ghost presentation must be off even while the pet is ghosted, and it must
	/// return when the HUD is re-enabled.
	func testShowsGhostPresentationGatedByHUDEnabled() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(vm.showsGhostPresentation, "ghosted + HUD enabled → ghost visuals show")

		// Live toggle off → ghost visuals suppressed though still ghosted.
		vm.setHUDEnabled(false)
		XCTAssertTrue(vm.isGhosted)
		XCTAssertFalse(vm.showsGhostPresentation, "HUD off must recolor pet + drop tombstone")

		// Re-enable → ghost visuals return (still ghosted).
		vm.setHUDEnabled(true)
		XCTAssertTrue(vm.showsGhostPresentation)

		// A poll arriving with the HUD opted out also suppresses ghost visuals.
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: false)
		XCTAssertFalse(vm.showsGhostPresentation)
	}

	func testShowsGhostPresentationFalseWhenAlive() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 4, levelFraction: 0.2, level: 3, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(vm.showsGhostPresentation)
	}

	// MARK: - Revival meter

	/// While ghosted, the meter fraction tracks active-minute carry toward the first
	/// half-heart: 0/60 → 0.0, 30/60 → 0.5, and it clamps at 60/60 → 1.0.
	func testReviveProgressTracksActiveMinutes() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertEqual(vm.reviveProgress, 0.0, accuracy: 1e-9)
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 30, hudEnabled: true)
		XCTAssertEqual(vm.reviveProgress, 0.5, accuracy: 1e-9)
		// Carry should never exceed a full block, but clamp defensively anyway.
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 90, hudEnabled: true)
		XCTAssertEqual(vm.reviveProgress, 1.0, accuracy: 1e-9)
	}

	/// The meter shows under exactly the ghost-presentation condition (ghosted + HUD
	/// enabled) and vanishes the instant a half-heart returns — the revival event.
	func testShowsReviveMeterMatchesGhostStateAndVanishesOnRevival() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 45, hudEnabled: true)
		XCTAssertTrue(vm.showsReviveMeter, "ghosted + HUD enabled → meter shows")

		// Earning the first half-heart revives the pet → meter (and tombstone) go.
		vm.update(halfHearts: 1, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(vm.isGhosted)
		XCTAssertFalse(vm.showsReviveMeter, "revived → meter vanishes")
	}

	/// The meter belongs to the HUD: opting the HUD out hides it even mid-ghost.
	func testShowsReviveMeterGatedByHUDEnabled() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 20, hudEnabled: false)
		XCTAssertTrue(vm.isGhosted)
		XCTAssertFalse(vm.showsReviveMeter, "HUD off → no meter even while ghosted")
	}

	// MARK: - Heart-regen bar (alive-state)

	/// `isFull` is true only at 6 half-hearts and false before any snapshot.
	func testIsFullOnlyAtMaxHealth() {
		let vm = RPGHUDViewModel()
		XCTAssertFalse(vm.isFull, "no snapshot yet → not full")
		vm.update(halfHearts: 5, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(vm.isFull, "5 half-hearts → not full")
		vm.update(halfHearts: 6, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertTrue(vm.isFull, "6 half-hearts → full")
	}

	/// The regen bar fraction tracks the same active-minute carry as the revival
	/// meter: 0/60 → 0.0, 30/60 → 0.5, clamped at 60/60 → 1.0.
	func testHeartRegenProgressTracksActiveMinutes() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 3, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertEqual(vm.heartRegenProgress, 0.0, accuracy: 1e-9)
		vm.update(halfHearts: 3, levelFraction: 0, level: 1, activeMinutes: 30, hudEnabled: true)
		XCTAssertEqual(vm.heartRegenProgress, 0.5, accuracy: 1e-9)
		vm.update(halfHearts: 3, levelFraction: 0, level: 1, activeMinutes: 90, hudEnabled: true)
		XCTAssertEqual(vm.heartRegenProgress, 1.0, accuracy: 1e-9)
	}

	/// The bar shows only while alive, below max health, and HUD-enabled.
	func testShowsHeartRegenBarOnlyWhenAliveAndNotFull() {
		let vm = RPGHUDViewModel()
		XCTAssertFalse(vm.showsHeartRegenBar, "no snapshot yet → hidden")

		// Mid-health alive → shown.
		vm.update(halfHearts: 3, levelFraction: 0, level: 1, activeMinutes: 20, hudEnabled: true)
		XCTAssertTrue(vm.showsHeartRegenBar, "alive + below max → bar shows")

		// Full health → hidden (nothing to regen).
		vm.update(halfHearts: 6, levelFraction: 0, level: 1, activeMinutes: 0, hudEnabled: true)
		XCTAssertFalse(vm.showsHeartRegenBar, "full health → bar hidden")

		// Ghosted → hidden (the green revival meter owns the display).
		vm.update(halfHearts: 0, levelFraction: 0, level: 1, activeMinutes: 20, hudEnabled: true)
		XCTAssertFalse(vm.showsHeartRegenBar, "ghosted → bar hidden")
	}

	/// The bar belongs to the HUD: opting the HUD out hides it even when alive and
	/// below max health, and a live toggle flips it without a new poll.
	func testShowsHeartRegenBarGatedByHUDEnabled() {
		let vm = RPGHUDViewModel()
		vm.update(halfHearts: 4, levelFraction: 0, level: 1, activeMinutes: 10, hudEnabled: false)
		XCTAssertFalse(vm.showsHeartRegenBar, "HUD off → no bar even when alive + below max")

		vm.setHUDEnabled(true)
		XCTAssertTrue(vm.showsHeartRegenBar, "HUD re-enabled → bar returns")
	}

	// MARK: - Layout: regen-bar row height

	/// When the bar is requested, the content height grows by the bar row (bar
	/// height + a row gap); without it the height matches the hearts-over-ring
	/// stack.
	func testRegenBarGrowsContentHeight() {
		let petFrame = CGRect(x: 1000, y: 800, width: 220, height: 264)
		let withoutBar = RPGHUDLayout.metrics(for: petFrame, showsRegenBar: false)
		let withBar = RPGHUDLayout.metrics(for: petFrame, showsRegenBar: true)
		XCTAssertEqual(
			withBar.contentHeight - withoutBar.contentHeight,
			withBar.regenBarHeight + withBar.rowGap,
			accuracy: 0.5)
		// Width is unaffected — the bar spans the heart row, never wider.
		XCTAssertEqual(withBar.contentWidth, withoutBar.contentWidth, accuracy: 0.5)
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
		let gap = (anchor.width * RPGHUDLayout.hudGapFraction).rounded()
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
		let gap = (anchor.width * RPGHUDLayout.tombstoneGapFraction).rounded()
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

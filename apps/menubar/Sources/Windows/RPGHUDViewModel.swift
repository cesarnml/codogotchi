import Foundation

/// One slot in the 3-heart display. Full = both sub-halves filled;
/// half = left sub-half only; empty = no fill (dimmed outline).
enum HeartState: Equatable {
	case full
	case half
	case empty
}

/// Flash / particle events emitted by the HUD view-model when state deltas
/// cross the relevant thresholds. Consumers drive visual effects from these.
enum RPGFlashEvent: Equatable {
	case heartInjured   // half_hearts decreased
	case heartHealed    // half_hearts increased
	case levelUp        // level increased
	case milestoneBurst // level crossed a milestone (10/25/50/75/100)
}

/// Levels at which a sparkle/confetti burst fires (in addition to the
/// regular level-up flash). Persisted to `RPGHUDViewModel` as a constant.
let RPG_MILESTONE_LEVELS: Set<Int> = [10, 25, 50, 75, 100]

/// Active coding minutes needed to earn one half-heart. Mirrors contracts
/// `ACTIVE_MINUTES_PER_HALF_HEART = 60`. Drives the revival meter denominator:
/// bringing a ghosted pet (0 → 1 half-heart) back is exactly one full block of these.
let ACTIVE_MINUTES_PER_HALF_HEART: Int = 60

/// View-model that converts raw `StateSnapshot` RPG fields into display-ready
/// values and emits delta-driven flash events. All logic is pure/deterministic
/// and lives here so the view renders dumbly. Tests drive this in isolation.
///
/// Stub: fields default to wrong values; flash callback is never called.
/// All tests written against this stub will fail — that is the Red state.
final class RPGHUDViewModel {
	private(set) var hearts: [HeartState] = []
	private(set) var ringFraction: Double = 0.0
	private(set) var level: Int = 1
	private(set) var isHUDEnabled: Bool = true

	/// Active-minute carry toward the next half-heart (0…59) from the latest
	/// snapshot. While ghosted this is the raw progress toward revival.
	private(set) var activeMinutes: Int = 0

	/// Active minutes needed per half-heart — the revive/regen meter
	/// denominator. Tracks Settings → RPG → Activity Regeneration; defaults to
	/// the contract constant when the config is untouched.
	private(set) var regenMinutesPerHalfHeart: Int = ACTIVE_MINUTES_PER_HALF_HEART

	/// The pet is ghosted when every heart slot is empty (0 half-hearts). False
	/// before the first snapshot (no hearts yet) so the ghost presentation never flashes on.
	var isGhosted: Bool { !hearts.isEmpty && hearts.allSatisfy { $0 == .empty } }

	/// The pet is at max health when all three slots are full (6 half-hearts).
	/// False before the first snapshot so the regen bar never shows pre-data.
	var isFull: Bool { hearts.count == 3 && hearts.allSatisfy { $0 == .full } }

	/// Whether the ghost presentation (grayscale pet + tombstone) should show. The
	/// tombstone is part of the RPG HUD — alongside the hearts, XP ring, and level
	/// label — so it (and the grayscale) only appear while the HUD is enabled.
	var showsGhostPresentation: Bool { isGhosted && isHUDEnabled }

	/// Revival progress as a 0.0…1.0 fraction: how close the ghosted pet is to
	/// earning its first half-heart back. `activeMinutes / 60`, clamped. Only
	/// meaningful while ghosted — the meter consumer gates on `showsReviveMeter`.
	var reviveProgress: Double {
		let denominator = max(1, regenMinutesPerHalfHeart)
		let raw = Double(activeMinutes) / Double(denominator)
		return min(1.0, max(0.0, raw))
	}

	/// Whether the regeneration meter should show. It lives alongside the
	/// tombstone, so it appears under exactly the same condition — while the pet
	/// is ghosted and the HUD is enabled — and vanishes the instant the pet revives
	/// (regains a half-heart → `isGhosted` flips false).
	var showsReviveMeter: Bool { showsGhostPresentation }

	/// Progress toward the *next* half-heart earned by active coding, as a 0…1
	/// fraction. Identical math to `reviveProgress` (`activeMinutes / 60`); this
	/// name is used while the pet is alive, where "revive" would mislead. Drives
	/// the alive-state heart-regen bar that sits between the hearts and XP ring.
	var heartRegenProgress: Double { reviveProgress }

	/// Whether the alive-state heart-regen bar should show. Only while the HUD is
	/// enabled, the pet is alive (not ghosted), and not already at max health: at
	/// full health there is nothing to regen, and while ghosted the green revival
	/// meter owns the progress display instead. False before the first snapshot.
	var showsHeartRegenBar: Bool {
		isHUDEnabled && !hearts.isEmpty && !isGhosted && !isFull
	}

	/// Called (on the caller's thread) whenever a flash event fires.
	/// No event fires on the *first* call to `update` — deltas require a prior state.
	var onFlash: ((RPGFlashEvent) -> Void)?

	private var previousHalfHearts: Int? = nil
	private var previousLevel: Int? = nil

	/// Push a new RPG snapshot into the view-model.
	/// - Parameters:
	///   - halfHearts: 0…6 raw half-heart count from state.json
	///   - levelFraction: 0.0…1.0 XP ring fill from state.json
	///   - level: 1…100 level number from state.json
	///   - activeMinutes: 0…59 active-minute carry toward the next half-heart
	///   - hudEnabled: `false` suppresses all HUD chrome regardless of hover
	func update(
		halfHearts: Int,
		levelFraction: Double,
		level: Int,
		activeMinutes: Int,
		hudEnabled: Bool,
		regenMinutesPerHalfHeart: Int = ACTIVE_MINUTES_PER_HALF_HEART
	) {
		let prevHalfHearts = previousHalfHearts
		let prevLevel = previousLevel

		self.hearts = Self.hearts(from: halfHearts)
		self.ringFraction = levelFraction
		self.level = level
		self.activeMinutes = activeMinutes
		self.regenMinutesPerHalfHeart = max(1, regenMinutesPerHalfHeart)
		self.isHUDEnabled = hudEnabled

		previousHalfHearts = halfHearts
		previousLevel = level

		// No delta events on the first call — no prior state to compare.
		guard prevHalfHearts != nil, prevLevel != nil else { return }

		if halfHearts < prevHalfHearts! {
			onFlash?(.heartInjured)
		} else if halfHearts > prevHalfHearts! {
			onFlash?(.heartHealed)
		}

		if level > prevLevel! {
			onFlash?(.levelUp)
			if RPG_MILESTONE_LEVELS.contains(level) {
				onFlash?(.milestoneBurst)
			}
		}
	}

	/// Flip HUD visibility without touching the displayed snapshot. Used when
	/// the resolved `rpg_hud_mode` changes which window(s) should show the
	/// HUD: there is no new RPG poll to ride, so the live value must be
	/// updated directly. Does not emit flash events — it is a visibility
	/// change, not a state delta.
	func setHUDEnabled(_ enabled: Bool) {
		isHUDEnabled = enabled
	}

	/// Derive the 3-slot heart array from a raw `halfHearts` count (0…6).
	/// Slot 0 is the leftmost heart and fills first. Each slot covers 2 half-hearts:
	/// slot 0 = halves 5–6, slot 1 = halves 3–4, slot 2 = halves 1–2.
	static func hearts(from halfHearts: Int) -> [HeartState] {
		let clamped = max(0, min(6, halfHearts))
		return (0..<3).map { slot in
			// Remaining half-hearts after filling this slot's predecessors.
			let remaining = clamped - slot * 2
			if remaining >= 2 { return .full }
			if remaining == 1 { return .half }
			return .empty
		}
	}
}

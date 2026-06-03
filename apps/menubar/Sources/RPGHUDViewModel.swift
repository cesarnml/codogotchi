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
	///   - hudEnabled: `false` suppresses all HUD chrome regardless of hover
	func update(halfHearts: Int, levelFraction: Double, level: Int, hudEnabled: Bool) {
		// Stub — leaves fields at wrong defaults so all tests fail.
		_ = halfHearts
		_ = levelFraction
		_ = level
		_ = hudEnabled
	}

	/// Derive the 3-slot heart array from a raw `halfHearts` count (0…6).
	/// Each slot covers 2 half-hearts: [slot0 = halves 5-6, slot1 = halves 3-4, slot2 = halves 1-2].
	/// The leftmost slot fills first (highest half-heart values).
	static func hearts(from halfHearts: Int) -> [HeartState] {
		// Stub — returns empty so count assertions fail.
		return []
	}
}

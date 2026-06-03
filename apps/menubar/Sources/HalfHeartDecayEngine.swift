import Foundation

/// Decay period derived from contracts/decay-constants.ts `HALF_HEART_DECAY_HOURS = 8`.
/// Stored as seconds so `timeIntervalSince` can be compared directly.
/// If the TS source ever changes to a non-whole-hour value, update both.
let HALF_HEART_DECAY_SECONDS: Double = 8 * 3600

/// Maximum half-hearts from contracts/decay-constants.ts `MAX_HALF_HEARTS = 6`.
let MAX_HALF_HEARTS: Int = 6

/// Pure decay math helper.
///
/// The CLI writer is authoritative on heals. Swift only ever decays below
/// the written value — it never invents heals. The formula is:
///   `displayed = max(0, written − floor(elapsed / HALF_HEART_DECAY_SECONDS))`
/// where `elapsed` is wall-clock seconds since `lastActivityAt`.
/// `nil` `lastActivityAt` means no activity recorded → no decay.
enum HalfHeartDecayEngine {
	static func displayed(written: Int, lastActivityAt: Date?, now: Date) -> Int {
		guard let last = lastActivityAt else { return written }
		let elapsed = now.timeIntervalSince(last)
		guard elapsed > 0 else { return written }
		let decayed = Int(floor(elapsed / HALF_HEART_DECAY_SECONDS))
		return max(0, written - decayed)
	}
}

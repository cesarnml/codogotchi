import Foundation

/// Decay period from contracts/decay-constants.ts — one half-heart per 8 idle hours.
/// Using wall-clock elapsed so sleep/wake is handled correctly on resume.
let HALF_HEART_DECAY_SECONDS: Double = 8 * 3600

/// Maximum half-hearts from contracts/decay-constants.ts.
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

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
/// where `elapsed` is wall-clock seconds since `lastActivityAt`, minus any
/// weekend seconds when `skipWeekends` is on (Settings → RPG → Skip Weekends).
/// `nil` `lastActivityAt` means no activity recorded → no decay.
enum HalfHeartDecayEngine {
	static func displayed(
		written: Int,
		lastActivityAt: Date?,
		now: Date,
		skipWeekends: Bool = false,
		decaySeconds: Double = HALF_HEART_DECAY_SECONDS,
		calendar: Calendar = .current
	) -> Int {
		guard let last = lastActivityAt else { return written }
		var elapsed = now.timeIntervalSince(last)
		guard elapsed > 0 else { return written }
		if skipWeekends {
			elapsed -= weekendSeconds(from: last, to: now, calendar: calendar)
		}
		// Guard against a zero/negative/NaN block from a hand-edited config —
		// never divide into a runaway decay.
		let block = decaySeconds.isFinite && decaySeconds > 0 ? decaySeconds : HALF_HEART_DECAY_SECONDS
		let decayed = Int(floor(elapsed / block))
		return max(0, written - decayed)
	}

	/// Seconds of `[start, end]` that fall on a Saturday or Sunday in the
	/// calendar's time zone. Walks day boundaries so a window spanning several
	/// weeks charges exactly the weekday portion. Deliberately hardcodes
	/// Sat/Sun (not the locale's `isDateInWeekend`) to stay in lockstep with
	/// the CLI's authoritative decay in engine/hearts.ts `weekendMsBetween` —
	/// if the two disagreed, the displayed hearts would drift from the written
	/// value on the next hook event.
	static func weekendSeconds(from start: Date, to end: Date, calendar: Calendar = .current) -> TimeInterval {
		guard end > start else { return 0 }
		var total: TimeInterval = 0
		var dayStart = calendar.startOfDay(for: start)
		while dayStart < end {
			guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
			let weekday = calendar.component(.weekday, from: dayStart)
			if weekday == 1 || weekday == 7 {
				let overlapStart = max(start, dayStart)
				let overlapEnd = min(end, nextDay)
				if overlapEnd > overlapStart {
					total += overlapEnd.timeIntervalSince(overlapStart)
				}
			}
			dayStart = nextDay
		}
		return total
	}
}

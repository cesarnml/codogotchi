import XCTest

@testable import Codogotchi

/// Behavior contract for `HalfHeartDecayEngine` — the pure decay math helper
/// introduced in P10.06. Swift only ever decays below the written value; the
/// CLI writer is authoritative on heals.
///
/// Decay formula: `displayed = max(0, written − floor(elapsed / decayPeriod))`
/// where `decayPeriod = HALF_HEART_DECAY_SECONDS` (8 h = 28 800 s).
/// Wall-clock elapsed is used so sleep/wake is handled correctly on resume.
final class HalfHeartDecayTests: XCTestCase {
	// MARK: - Decay constant

	func testDecayConstantMatchesContract() {
		// [red] HALF_HEART_DECAY_SECONDS must equal 8 h in seconds
		XCTAssertEqual(HALF_HEART_DECAY_SECONDS, 8 * 3600)
	}

	// MARK: - Decay math

	func testEightHourElapsedDecaysByOne() {
		// [red] floor(28800 / 28800) = 1; written 3 − 1 = displayed 2
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 8 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 3, lastActivityAt: base, now: now),
			2
		)
	}

	func testFortyEightHourElapsedFloorsAtZero() {
		// [red] floor(172800 / 28800) = 6; max(0, 4 − 6) = 0
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 48 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 4, lastActivityAt: base, now: now),
			0
		)
	}

	func testLessThanEightHoursNoDecay() {
		// [red] floor(14400 / 28800) = 0; written 3 unchanged
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 4 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 3, lastActivityAt: base, now: now),
			3
		)
	}

	func testNilLastActivityAtNoDecay() {
		// [red] nil lastActivityAt ⇒ no decay — return written value unchanged
		let now = Date(timeIntervalSinceReferenceDate: 500_000)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 5, lastActivityAt: nil, now: now),
			5
		)
	}

	func testFloorAtZeroWhenOverDecayed() {
		// [red] 1000 h: floor(3_600_000 / 28800) = 125; max(0, 3 − 125) = 0
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 1000 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 3, lastActivityAt: base, now: now),
			0
		)
	}

	func testFreshHealWriteOverridesDecay() {
		// [red] writer just healed to 6; now == lastActivityAt ⇒ 0 elapsed ⇒ displayed 6
		let t = Date(timeIntervalSinceReferenceDate: 9999)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 6, lastActivityAt: t, now: t),
			6
		)
	}

	func testZeroElapsedNoDecay() {
		// [red] elapsed == 0 ⇒ floor(0) = 0 ⇒ written unchanged
		let t = Date(timeIntervalSinceReferenceDate: 1234)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(written: 4, lastActivityAt: t, now: t),
			4
		)
	}

	func testMaxHalfHeartsConstantMatchesContract() {
		// [red] MAX_HALF_HEARTS must equal 6 per contracts/decay-constants.ts
		XCTAssertEqual(MAX_HALF_HEARTS, 6)
	}

	// MARK: - Configurable decay block

	func testCustomDecaySecondsChangesBlockSize() {
		// 24h elapsed at a 24h block = exactly one half-heart of decay.
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 24 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(
				written: 6, lastActivityAt: base, now: now, decaySeconds: 24 * 3600),
			5
		)
	}

	func testNonPositiveDecaySecondsFallsBackToDefaultBlock() {
		let base = Date(timeIntervalSinceReferenceDate: 0)
		let now = Date(timeIntervalSinceReferenceDate: 8 * 3600)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(
				written: 6, lastActivityAt: base, now: now, decaySeconds: 0),
			5
		)
	}

	// MARK: - Skip Weekends

	/// Fixed UTC Gregorian calendar so weekend boundaries are deterministic
	/// regardless of the machine's locale and time zone.
	private var utcCalendar: Calendar {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone(identifier: "UTC")!
		return cal
	}

	/// 2026-07-03 is a Friday; 2026-07-04/05 are the weekend.
	private func date(_ iso: String) -> Date {
		ISO8601DateFormatter().date(from: iso)!
	}

	func testWeekendSecondsFullWeekendInsideWindow() {
		// Friday noon → Monday noon spans exactly Sat+Sun = 48 h of weekend.
		let seconds = HalfHeartDecayEngine.weekendSeconds(
			from: date("2026-07-03T12:00:00Z"),
			to: date("2026-07-06T12:00:00Z"),
			calendar: utcCalendar
		)
		XCTAssertEqual(seconds, 48 * 3600)
	}

	func testWeekendSecondsPartialOverlap() {
		// Saturday 18:00 → Sunday 06:00 is 12 h, all of it weekend.
		let seconds = HalfHeartDecayEngine.weekendSeconds(
			from: date("2026-07-04T18:00:00Z"),
			to: date("2026-07-05T06:00:00Z"),
			calendar: utcCalendar
		)
		XCTAssertEqual(seconds, 12 * 3600)
	}

	func testWeekendSecondsZeroForMidweekWindow() {
		let seconds = HalfHeartDecayEngine.weekendSeconds(
			from: date("2026-07-06T09:00:00Z"),
			to: date("2026-07-08T09:00:00Z"),
			calendar: utcCalendar
		)
		XCTAssertEqual(seconds, 0)
	}

	func testSkipWeekendsSuppressesWeekendOnlyDecay() {
		// Friday 22:00 → Sunday 22:00 = 48 h elapsed. Without skip: −6 → 0.
		// With skip: only Fri 22:00–24:00 (2 h) counts ⇒ floor(2/8) = 0 decay.
		let last = date("2026-07-03T22:00:00Z")
		let now = date("2026-07-05T22:00:00Z")
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(
				written: 6, lastActivityAt: last, now: now, calendar: utcCalendar),
			0
		)
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(
				written: 6, lastActivityAt: last, now: now,
				skipWeekends: true, calendar: utcCalendar),
			6
		)
	}

	func testSkipWeekendsStillDecaysWeekdayHours() {
		// Friday 00:00 → Monday 16:00 = 88 h elapsed, 48 h of it weekend.
		// Effective 40 h ⇒ floor(40/8) = 5 half-hearts of decay.
		let last = date("2026-07-03T00:00:00Z")
		let now = date("2026-07-06T16:00:00Z")
		XCTAssertEqual(
			HalfHeartDecayEngine.displayed(
				written: 6, lastActivityAt: last, now: now,
				skipWeekends: true, calendar: utcCalendar),
			1
		)
	}
}

import Foundation

/// Per-platform (per-origin) free-list numbering for session-keyed panels.
///
/// Each origin gets its own independent numbering sequence starting at 1.
/// `assign` returns the lowest free number for that origin — either a number
/// released by an earlier `release` call, or the next number past the
/// origin's current high-water mark when no released number is available. A
/// session already carrying a number always gets that same number back; a
/// live session's number is never reassigned to another session ("never
/// renumber a live session").
///
/// Under an origin's Unlimited cap (`sessionCap == 0`, see
/// `CustomizationJsonReader`), numbering stays purely monotonic: `release`
/// simply forgets the session without returning its number to a free list,
/// so freed numbers are never reused and the free-list never grows —
/// Unlimited mode has no bounded pool to reuse within.
///
/// Purely in-memory and intentionally holds no persisted state: it is
/// rebuilt at launch from the sessions observed on the first poll ticks.
final class SessionNumberAllocator {
	private struct OriginState {
		/// sessionId → assigned number, for currently-live sessions.
		var assigned: [String: Int] = [:]
		/// Numbers released by a bounded (non-Unlimited) origin, available for reuse.
		/// A sorted set so "lowest free number" is a cheap `.first`.
		var freeNumbers: Set<Int> = []
		/// High-water mark: the next number to hand out when no free number exists.
		var nextNumber: Int = 1
	}

	/// Per-origin Unlimited flag, updated from `sessionCap` (cap == 0) at the
	/// point of use by the caller (the pool, on each tick). Origins default to
	/// bounded (reuse-eligible) until told otherwise.
	private var unlimitedOrigins: Set<String> = []
	private var origins: [String: OriginState] = [:]

	init() {}

	/// Marks whether `origin` is currently under an Unlimited cap. Call this
	/// before `assign`/`release` for the origin on each tick so the mode
	/// reflects the live `sessionCap` setting. Toggling from bounded back to
	/// Unlimited (or vice versa) does not retroactively touch already-assigned
	/// numbers — it only changes what `release` does going forward.
	func setUnlimited(_ unlimited: Bool, origin: String) {
		if unlimited {
			unlimitedOrigins.insert(origin)
		} else {
			unlimitedOrigins.remove(origin)
		}
	}

	/// Returns the number assigned to `(origin, sessionId)`, assigning a new one
	/// (the lowest free number, or the next monotonic number) if this is the
	/// first time this session has been seen for this origin. A still-live
	/// session always gets its existing number back — it is never renumbered.
	@discardableResult
	func assign(origin: String, sessionId: String) -> Int {
		var state = origins[origin] ?? OriginState()
		defer { origins[origin] = state }

		if let existing = state.assigned[sessionId] {
			return existing
		}

		let number: Int
		if let lowestFree = state.freeNumbers.min() {
			number = lowestFree
			state.freeNumbers.remove(lowestFree)
		} else {
			number = state.nextNumber
			state.nextNumber += 1
		}
		state.assigned[sessionId] = number
		return number
	}

	/// Releases the number held by `(origin, sessionId)`, if any. Under a
	/// bounded (non-Unlimited) origin the number returns to the free list for
	/// reuse by the next `assign`. Under an Unlimited origin the number is
	/// simply forgotten — it is never reclaimed, and no free-list bookkeeping
	/// is needed since it will never be referenced again.
	func release(origin: String, sessionId: String) {
		guard var state = origins[origin], let number = state.assigned.removeValue(forKey: sessionId) else {
			return
		}
		if !unlimitedOrigins.contains(origin) {
			state.freeNumbers.insert(number)
		}
		origins[origin] = state
	}
}

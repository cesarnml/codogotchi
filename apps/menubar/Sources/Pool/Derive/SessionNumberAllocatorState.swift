import Foundation

/// Pure, `Equatable` value-type transcription of `SessionNumberAllocator`
/// (see `Pool/State/SessionNumberAllocator.swift`) — same per-origin
/// free-list numbering semantics, but composable inside `PoolMemory` instead
/// of held as a reference-type side table on `FloatingPetWindowPool`.
///
/// Each origin gets its own independent numbering sequence starting at 1.
/// `assign` returns the lowest free number for that origin — either a number
/// released by an earlier `release` call, or the next number past the
/// origin's current high-water mark when no released number is available. A
/// session already carrying a number always gets that same number back.
///
/// Under an origin's Unlimited cap (`sessionCap == 0`), numbering stays
/// purely monotonic: `release` simply forgets the session without returning
/// its number to a free list, so freed numbers are never reused.
///
/// `release` reads no external identity — the caller (`PoolMemory`'s
/// transition functions and `PoolDerive`'s teardown-diff pass) is
/// responsible for resolving `(origin, sessionId)` from the identity
/// captured at assign time (`PoolMemory.windowSessionIdentities`), never
/// from the current tick's snapshot — see that field's doc comment for the
/// exact leak-under-cap bug this avoids.
struct SessionNumberAllocatorState: Equatable {
	private struct OriginState: Equatable {
		/// sessionId → assigned number, for currently-live sessions.
		var assigned: [String: Int] = [:]
		/// Numbers released by a bounded (non-Unlimited) origin, available for reuse.
		var freeNumbers: Set<Int> = []
		/// High-water mark: the next number to hand out when no free number exists.
		var nextNumber: Int = 1
	}

	/// Per-origin Unlimited flag, updated from `sessionCap` (cap == 0) at the
	/// point of use by the caller (`PoolDerive`, once per tick per origin
	/// touched). Origins default to bounded (reuse-eligible) until told
	/// otherwise.
	private var unlimitedOrigins: Set<String> = []
	private var origins: [String: OriginState] = [:]

	init() {}

	/// Marks whether `origin` is currently under an Unlimited cap. Toggling
	/// from bounded back to Unlimited (or vice versa) does not retroactively
	/// touch already-assigned numbers — it only changes what `release` does
	/// going forward.
	mutating func setUnlimited(_ unlimited: Bool, origin: String) {
		if unlimited {
			unlimitedOrigins.insert(origin)
		} else {
			unlimitedOrigins.remove(origin)
		}
	}

	/// Returns the number assigned to `(origin, sessionId)`, assigning a new
	/// one (the lowest free number, or the next monotonic number) if this is
	/// the first time this session has been seen for this origin. A still-live
	/// session always gets its existing number back — it is never renumbered.
	@discardableResult
	mutating func assign(origin: String, sessionId: String) -> Int {
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
	/// simply forgotten.
	mutating func release(origin: String, sessionId: String) {
		guard var state = origins[origin], let number = state.assigned.removeValue(forKey: sessionId) else {
			return
		}
		if !unlimitedOrigins.contains(origin) {
			state.freeNumbers.insert(number)
		}
		origins[origin] = state
	}
}

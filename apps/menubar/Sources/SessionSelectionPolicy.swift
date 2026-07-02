import Foundation

/// Pure per-origin cap/eviction policy for session-keyed render keys (P15.07).
///
/// Stateless by design: recomputed from the current `[windowKey → ActivityState]`
/// set and the origin's cap on every pool tick. No separate "held" bookkeeping is
/// needed — "promotion" falls out of recomputing the same partition once a
/// rendered key disappears from the input (pruned, TTL-expired, or simply no
/// longer present) or a competing session's state changes, rather than requiring
/// dedicated promotion logic.
enum SessionSelectionPolicy {
	/// Result of partitioning one origin's live session-keyed windows against
	/// its cap.
	struct Selection: Equatable {
		/// Window keys that should have a real panel this tick.
		let rendered: Set<String>
		/// Window keys held back — a reversible de-render. Their `state.d` slice
		/// stays on disk untouched; only Prune and TTL expiry ever delete it.
		let pending: Set<String>
		/// True when cap pressure blocked an in-flight ("active") session from
		/// rendering even though every session — rendered and pending — is itself
		/// in-flight, so there is no evictable target. Consumed by P15.08's
		/// conflict bubble; this policy only computes the signal, never renders it.
		let blocked: Bool
	}

	/// Evictability rank: lower ranks are trimmed first when a per-origin
	/// session count exceeds its cap (most evictable → least evictable).
	/// `.idle`/`.standby` share the bottom rank — both are "at rest" per
	/// `ActivityState.isInFlight`. `.waitingForInput` sits above `.errored`:
	/// a live approval gate must not be yielded before a plain idle/errored
	/// session. Every other state is in-flight (`ActivityState.isInFlight ==
	/// true`) and is never evicted — rank 3 is exactly that set.
	static func evictionRank(for state: ActivityState) -> Int {
		switch state {
		case .idle, .standby: return 0
		case .errored: return 1
		case .waitingForInput: return 2
		default: return 3
		}
	}

	/// Partitions `sessions` (window key → its current `ActivityState`) into
	/// rendered/pending against `cap`. `cap == 0` is the Unlimited sentinel
	/// (`CustomizationSnapshot.sessionCap`): every session renders, nothing is
	/// ever held, and `blocked` is always false. Otherwise `cap` is the maximum
	/// number of concurrently rendered panels for this origin.
	///
	/// `currentlyRendered` is the set of window keys that hold a real panel
	/// going into this tick. It only ever breaks a same-rank tie in favor of an
	/// incumbent over a newcomer — a freshly-arrived active session must never
	/// bump an already-rendered active session, since active-tier sessions are
	/// otherwise indistinguishable by rank alone (both rank 3). Without this,
	/// two active sessions competing for the same slot would resolve by
	/// arbitrary key order, letting a newcomer evict a working incumbent —
	/// exactly what "never de-rendered for a newcomer" forbids.
	static func select(
		sessions: [String: ActivityState],
		cap: Int,
		currentlyRendered: Set<String> = []
	) -> Selection {
		guard cap > 0, sessions.count > cap else {
			return Selection(rendered: Set(sessions.keys), pending: [], blocked: false)
		}

		// Sort least-evictable-last (ascending rank, incumbents-last within a
		// rank) with a deterministic key tie-break so equal-rank, equal-incumbency
		// sessions always partition the same way — unspecified Dictionary
		// iteration order must never decide which session is held.
		let ordered = sessions.keys.sorted { a, b in
			let rankA = evictionRank(for: sessions[a]!)
			let rankB = evictionRank(for: sessions[b]!)
			if rankA != rankB { return rankA < rankB }
			let incumbentA = currentlyRendered.contains(a)
			let incumbentB = currentlyRendered.contains(b)
			if incumbentA != incumbentB { return incumbentB }
			return a < b
		}
		let pending = Set(ordered.prefix(ordered.count - cap))
		let rendered = Set(ordered.suffix(cap))
		// Blocked only when a genuinely in-flight session is the one held back —
		// an idle/errored/waiting session held by cap pressure is ordinary
		// eviction, not a conflict worth signaling.
		let blocked = pending.contains { sessions[$0]?.isInFlight ?? false }
		return Selection(rendered: rendered, pending: pending, blocked: blocked)
	}
}

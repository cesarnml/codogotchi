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
	///
	/// `updatedAt` (window key → ISO 8601 `updated_at`) breaks a same-rank,
	/// same-incumbency tie in favor of the more recently updated session —
	/// e.g. on a cold app relaunch, where nothing is yet incumbent, this is
	/// what makes the session you were last actually using win a slot over
	/// other idle/ended sessions instead of an arbitrary session-id sort. A
	/// missing or unparseable entry sorts as `.distantPast` (most evictable).
	/// Every other winner-selection path in this codebase (render-key
	/// election, the grandfather-on-toggle winner, the combined-window
	/// winner) already uses recency as its primary rule; this is the one
	/// spot that didn't, and a raw session-id string carries no user-facing
	/// meaning as a tie-break. Only sessions sharing the exact same
	/// (or absent) timestamp fall through to the lexicographic key
	/// tie-break below, purely for full determinism.
	///
	/// `incumbentsProtected` is the Settings > Customization "Evict Session
	/// Pets" kill-switch (P15.10): `false` (default) preserves today's
	/// behavior — an incumbent is only protected as a same-rank tie-break, so
	/// a higher-ranked newcomer (e.g. in-flight) can still evict a
	/// lower-ranked incumbent (e.g. idle) when the cap is full. `true` checks
	/// incumbency BEFORE rank, so every incumbent sorts as least-evictable
	/// regardless of its rank — no incumbent is ever evicted for a newcomer.
	/// A newcomer can still fill any slot that isn't already held by an
	/// incumbent; only eviction of an existing occupant is suppressed.
	///
	/// `restrictNewPromotionsToInFlight` is the P15.07-QC prune-armed gate: once
	/// an origin has had a manual Prune this app session, a session that was
	/// NOT already rendered may only newly promote into a freed slot while it
	/// is in-flight. An incumbent (`currentlyRendered`) is never re-evaluated
	/// by this gate — only fresh promotions are. When the gate rejects every
	/// remaining candidate for a slot, that slot is simply left empty rather
	/// than backfilled with a non-in-flight session, matching "empty is fine
	/// while nothing is actually running" from the P15.07-QC decision. Without
	/// this, pruning one rendered session immediately hands its slot to
	/// whichever idle/standby session was merely being held by cap pressure —
	/// a session the user never asked to see, indistinguishable in the UI from
	/// the pruned one reappearing.
	static func select(
		sessions: [String: ActivityState],
		cap: Int,
		currentlyRendered: Set<String> = [],
		updatedAt: [String: String] = [:],
		incumbentsProtected: Bool = false,
		restrictNewPromotionsToInFlight: Bool = false
	) -> Selection {
		guard cap > 0 else {
			return Selection(rendered: Set(sessions.keys), pending: [], blocked: false)
		}

		func recency(_ key: String) -> Date {
			updatedAt[key].flatMap(StateJsonReader.parseISO8601Date) ?? .distantPast
		}

		// Sort least-evictable-last (ascending rank, incumbents-last, most-recent
		// last within a rank) with a deterministic key tie-break so equal-rank,
		// equal-incumbency, equal-recency sessions always partition the same way
		// — unspecified Dictionary iteration order must never decide which
		// session is held.
		let ordered = sessions.keys.sorted { a, b in
			let incumbentA = currentlyRendered.contains(a)
			let incumbentB = currentlyRendered.contains(b)
			if incumbentsProtected, incumbentA != incumbentB { return incumbentB }
			let rankA = evictionRank(for: sessions[a]!)
			let rankB = evictionRank(for: sessions[b]!)
			if rankA != rankB { return rankA < rankB }
			if incumbentA != incumbentB { return incumbentB }
			let dateA = recency(a)
			let dateB = recency(b)
			if dateA != dateB { return dateA < dateB }
			return a < b
		}
		// When sessions.count <= cap this renders every session, matching the
		// pre-QC guard clause's unconditional "render all" — unless the
		// prune-armed gate below trims a fresh, non-in-flight promotion out of it.
		let renderCount = min(cap, ordered.count)
		let rankedRendered = Set(ordered.suffix(renderCount))
		let rendered: Set<String>
		if restrictNewPromotionsToInFlight {
			rendered = rankedRendered.filter {
				currentlyRendered.contains($0) || (sessions[$0]?.isInFlight ?? false)
			}
		} else {
			rendered = rankedRendered
		}
		let pending = Set(sessions.keys).subtracting(rendered)
		// Blocked only when a genuinely in-flight session is the one held back —
		// an idle/errored/waiting session held by cap pressure is ordinary
		// eviction, not a conflict worth signaling.
		let blocked = pending.contains { sessions[$0]?.isInFlight ?? false }
		return Selection(rendered: rendered, pending: pending, blocked: blocked)
	}
}

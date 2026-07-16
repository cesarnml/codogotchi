import Foundation

/// Selects which session-keyed window key P15.08's conflict bubble anchors to
/// for a blocked origin: the longest-lived currently-rendered session
/// (earliest first-seen), so the bubble does not hop between panels tick to
/// tick while the conflict persists.
enum ConflictBubbleTargetSelector {
	/// `firstSeenAt` must already be filtered by the caller to the blocked
	/// origin's currently-rendered session-keyed window keys. Returns the key
	/// with the earliest timestamp, or `nil` when there are no candidates.
	/// Ties break on `key.rawValue` — never bare `min(by:)`, whose result on a
	/// tie depends on this Dictionary's internal hash-bucket layout, not a
	/// canonical rule (`PoolDerive`'s inline equivalent already does this).
	static func longestLivedKey(firstSeenAt: [WindowKey: Date]) -> WindowKey? {
		firstSeenAt.min { lhs, rhs in
			lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue < rhs.key.rawValue
		}?.key
	}
}

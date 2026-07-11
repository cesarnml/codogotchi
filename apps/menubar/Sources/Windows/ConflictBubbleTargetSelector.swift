import Foundation

/// Selects which session-keyed window key P15.08's conflict bubble anchors to
/// for a blocked origin: the longest-lived currently-rendered session
/// (earliest first-seen), so the bubble does not hop between panels tick to
/// tick while the conflict persists.
enum ConflictBubbleTargetSelector {
	/// `firstSeenAt` must already be filtered by the caller to the blocked
	/// origin's currently-rendered session-keyed window keys. Returns the key
	/// with the earliest timestamp, or `nil` when there are no candidates.
	static func longestLivedKey(firstSeenAt: [WindowKey: Date]) -> WindowKey? {
		firstSeenAt.min(by: { $0.value < $1.value })?.key
	}
}

import Foundation

/// Executes a manual "Prune Session" request (P15.07): destroys a session's
/// backing state across all three stores it touches — the `state.d/` slice
/// file, the free-list session number, and the `session-labels.json` rename
/// key — so a pruned session lands at the identical end-state as automatic
/// TTL expiry (P15.04) plus the automatic orphan-label sweep
/// (`SlicePruner.pruneOrphanLabels`).
///
/// `windowKey` is the resolved `"origin:session_id"` render key — the same
/// string `SessionLabelStore` keys on and that names the slice file
/// (`state.d/<windowKey>.json`).
enum SessionPruner {
	/// Deletes the slice, releases the session number, and removes the label
	/// key for `windowKey`. Each step is independently best-effort (a missing
	/// slice, an unassigned number, or an unset label is a safe no-op), so a
	/// partial prior state never blocks the remaining steps — the goal is "no
	/// orphan left behind" in any of the three stores, not all-or-nothing
	/// transactional rollback.
	static func pruneSession(
		windowKey: String,
		origin: String,
		sessionId: String,
		stateDirectory: String,
		allocator: SessionNumberAllocator,
		labelPath: String = SessionLabelStore.path()
	) {
		let slicePath = (stateDirectory as NSString).appendingPathComponent("\(windowKey).json")
		try? FileManager.default.removeItem(atPath: slicePath)
		allocator.release(origin: origin, sessionId: sessionId)
		SessionLabelStore.removeLabel(for: windowKey, at: labelPath)
	}
}

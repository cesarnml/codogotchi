import Foundation

/// Executes a manual "Prune Session" request (P15.07): destroys a session's
/// backing state across all four stores it touches — the `state.d/` slice
/// file, the free-list session number, the `session-labels.json` rename key,
/// and `retrieved-session-labels.json`'s cached platform thread title — so a
/// pruned session lands at the identical end-state as automatic TTL expiry
/// (P15.04) plus the automatic orphan sweeps (`SlicePruner.pruneOrphanLabels`,
/// `SlicePruner.pruneOrphanRetrievedTitles`).
///
/// `windowKey` is the resolved `"origin:session_id"` render key — the same
/// string `SessionLabelStore`/`RetrievedSessionTitleStore` key on and that
/// names the slice file (`state.d/<windowKey>.json`).
enum SessionPruner {
	/// Deletes the slice, releases the session number, and removes the label
	/// and cached-title keys for `windowKey`. Each step is independently
	/// best-effort (a missing slice, an unassigned number, or an unset
	/// label/title is a safe no-op), so a partial prior state never blocks
	/// the remaining steps — the goal is "no orphan left behind" in any of
	/// the four stores, not all-or-nothing transactional rollback.
	static func pruneSession(
		windowKey: String,
		origin: String,
		sessionId: String,
		stateDirectory: String,
		allocator: SessionNumberAllocator,
		labelPath: String = SessionLabelStore.path(),
		retrievedTitlePath: String = RetrievedSessionTitleStore.path()
	) {
		let slicePath = (stateDirectory as NSString).appendingPathComponent("\(windowKey).json")
		try? FileManager.default.removeItem(atPath: slicePath)
		allocator.release(origin: origin, sessionId: sessionId)
		SessionLabelStore.removeLabel(for: windowKey, at: labelPath)
		RetrievedSessionTitleStore.removeTitle(for: windowKey, at: retrievedTitlePath)
	}
}

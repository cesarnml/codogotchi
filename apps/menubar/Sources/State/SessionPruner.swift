import Foundation

/// Executes a manual "Prune Session" request: destroys a session's disk
/// backing — the `state.d/` slice file, the `session-labels.json` rename key,
/// `retrieved-session-labels.json`'s cached platform thread title, and
/// `app-state.json`'s per-window `floating_pet_positions`/`floating_pet_hidden`
/// entries — so a pruned session lands at the identical disk end-state as
/// automatic TTL expiry plus the automatic orphan sweeps.
///
/// Session-number release is owned solely by `PoolMemory` /
/// `SessionNumberAllocatorState` (e.g. `memory.pruning` before this runs).
/// This type is disk-only and never touches numbering.
///
/// `windowKey` is the resolved `"origin:session_id"` render key — the same
/// string `SessionLabelStore`/`RetrievedSessionTitleStore` key on and that
/// names the slice file (`state.d/<windowKey>.json`).
enum SessionPruner {
	/// Deletes the slice, removes the label and cached-title keys, and removes
	/// the `app-state.json` position/hidden entries for `windowKey`. Each step
	/// is independently best-effort (a missing slice, an unset label/title, or
	/// no app-state entry is a safe no-op), so a partial prior state never
	/// blocks the remaining steps.
	static func pruneSession(
		windowKey: String,
		origin _: String,
		sessionId _: String,
		stateDirectory: String,
		labelPath: String = SessionLabelStore.path(),
		retrievedTitlePath: String = RetrievedSessionTitleStore.path()
	) {
		let slicePath = (stateDirectory as NSString).appendingPathComponent("\(windowKey).json")
		try? FileManager.default.removeItem(atPath: slicePath)
		SessionLabelStore.removeLabel(for: windowKey, at: labelPath)
		RetrievedSessionTitleStore.removeTitle(for: windowKey, at: retrievedTitlePath)
		if let key = WindowKey(rawValue: windowKey) {
			try? AppStateStore.removeWindowEntries(for: key)
		}
	}
}

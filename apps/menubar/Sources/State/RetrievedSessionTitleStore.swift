import Foundation

/// Persisted cache of platform-auto-generated (or manually renamed within the
/// source app) thread titles that `SessionTitleResolver` fetched, keyed by
/// the same `"origin:session_id"` render key `SessionLabelStore` uses.
/// `~/.codogotchi/retrieved-session-labels.json` — deliberately a SEPARATE
/// file from `session-labels.json`, not a second key namespace in it:
/// `session-labels.json` means "the user chose this label" (a manual rename,
/// or an explicit "Sync Label" click); this file means "we once fetched this
/// off the platform's own disk storage" — a best-effort default, not a
/// decision. Keeping them apart means a future "reset to default" affordance,
/// or anything else that needs to tell the two apart, never has to guess.
///
/// Exists purely so `FloatingPetWindowPool` doesn't pay the resolution cost
/// again on every relaunch (a Claude Code directory walk, a Cursor `sqlite3`
/// subprocess, …) for a session it already resolved a title for. The pool's
/// own `resolvedSessionTitles` in-memory cache is the hot path; this file is
/// what survives a restart.
enum RetrievedSessionTitleStore {
	static func path(homeDirectory: String = CodogotchiFolders.dataFolderURL().path) -> String {
		URL(fileURLWithPath: homeDirectory).appendingPathComponent("retrieved-session-labels.json").path
	}

	/// The cached title for `key`, or `nil` when never resolved. A missing or
	/// malformed file degrades to "unset" rather than throwing.
	static func title(for key: String, at path: String = RetrievedSessionTitleStore.path()) -> String? {
		read(at: path)[key]
	}

	/// Trims `title` — but does NOT cap it at `SessionLabelStore.maxLength`,
	/// since a platform's own thread title is exempt from the 24-char limit
	/// applied to a manual Codogotchi rename — and writes it for `key`.
	/// Read-merge-write, matching `SessionLabelStore`, so resolving one
	/// session's title never clobbers another's cached moments earlier.
	static func setTitle(_ title: String, for key: String, at path: String = RetrievedSessionTitleStore.path()) {
		var titles = read(at: path)
		titles[key] = title.trimmingCharacters(in: .whitespacesAndNewlines)
		write(titles, at: path)
	}

	/// Drops `key`'s cached title — called by the same orphan-label sweep and
	/// manual "Prune Session" path that clean up `session-labels.json`, so
	/// this file never outlives every trace of the session it names. No-op
	/// if `key` was never cached.
	static func removeTitle(for key: String, at path: String = RetrievedSessionTitleStore.path()) {
		var titles = read(at: path)
		guard titles.removeValue(forKey: key) != nil else { return }
		write(titles, at: path)
	}

	private static func read(at path: String) -> [String: String] {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
		return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
	}

	private static func write(_ titles: [String: String], at path: String) {
		let url = URL(fileURLWithPath: path)
		try? FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		guard let data = try? JSONEncoder().encode(titles) else { return }
		try? data.write(to: url, options: .atomic)
	}
}

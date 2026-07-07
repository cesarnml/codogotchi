import Foundation

/// Swift-app-owned sidecar mapping a session render key (`"origin:session_id"`)
/// to a user-set rename label. `~/.codogotchi/session-labels.json` — the CLI
/// never writes this file, so writers are single-process; every write still
/// reads the current file first so a rename of one key never clobbers another
/// key written moments earlier (read-merge-write).
enum SessionLabelStore {
	/// User-visible cap on a rename label. Counted in `Character`s (grapheme
	/// clusters), not UTF-16 code units, so a composed emoji or accented
	/// character counts once — matching what the user actually typed.
	static let maxLength = 24

	static func path(homeDirectory: String = CodogotchiFolders.dataFolderURL().path) -> String {
		URL(fileURLWithPath: homeDirectory).appendingPathComponent("session-labels.json").path
	}

	/// The rename label for `key`, or `nil` when unset. A missing or malformed
	/// file degrades to "unset" rather than throwing.
	static func label(for key: String, at path: String = SessionLabelStore.path()) -> String? {
		read(at: path)[key]
	}

	/// Trims and caps `label`, writes it for `key`, and returns the stored
	/// (normalized) value.
	@discardableResult
	static func setLabel(_ label: String, for key: String, at path: String = SessionLabelStore.path()) -> String {
		store(normalize(label), for: key, at: path)
	}

	/// Trims but does NOT cap `label` at `maxLength` before writing it for
	/// `key`. Used by the right-click "Sync Label" affordance to adopt a
	/// platform's own auto-generated (or manually renamed) thread title
	/// verbatim — that title is itself exempt from the 24-char cap applied to
	/// a manual Codogotchi rename, so pulling it in here must not truncate it
	/// either.
	@discardableResult
	static func setLabelExemptFromCap(_ label: String, for key: String, at path: String = SessionLabelStore.path())
		-> String
	{
		store(label.trimmingCharacters(in: .whitespacesAndNewlines), for: key, at: path)
	}

	@discardableResult
	private static func store(_ normalized: String, for key: String, at path: String) -> String {
		var labels = read(at: path)
		labels[key] = normalized
		write(labels, at: path)
		return normalized
	}

	/// Drops `key`'s label, e.g. when its session is pruned. No-op if `key`
	/// was never set.
	static func removeLabel(for key: String, at path: String = SessionLabelStore.path()) {
		var labels = read(at: path)
		guard labels.removeValue(forKey: key) != nil else { return }
		write(labels, at: path)
	}

	/// Trims surrounding whitespace/newlines, then caps at `maxLength`
	/// characters.
	static func normalize(_ label: String) -> String {
		let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count > maxLength else { return trimmed }
		return String(trimmed.prefix(maxLength))
	}

	private static func read(at path: String) -> [String: String] {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
		return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
	}

	private static func write(_ labels: [String: String], at path: String) {
		let url = URL(fileURLWithPath: path)
		try? FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		guard let data = try? JSONEncoder().encode(labels) else { return }
		try? data.write(to: url, options: .atomic)
	}
}

import AppKit
import Foundation

/// Canonical on-disk locations the user can open from Settings:
/// the data folder (Developer tab) and the pet store (Pet tab).
/// Both respect `CODOGOTCHI_HOME`.
enum CodogotchiFolders {
	/// `~/.codogotchi/` — home of `state.json`, `gate.json`, and the transition log.
	static func dataFolderURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"),
			let home = String(validatingUTF8: cStr),
			!home.isEmpty
		{
			return URL(fileURLWithPath: home, isDirectory: true)
		}
		return FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi", isDirectory: true)
	}

	/// `~/.codogotchi/pets/` — the canonical pet store directory.
	static func petFolderURL() -> URL {
		dataFolderURL().appendingPathComponent("pets", isDirectory: true)
	}

	/// `~/.codogotchi/rpg-state.json` — RPG progression written by the CLI.
	static func rpgStatePath() -> String {
		dataFolderURL().appendingPathComponent("rpg-state.json").path
	}

	/// `~/.codogotchi/customization.json` — per-platform display overrides written by Settings.
	static func customizationPath() -> String {
		dataFolderURL().appendingPathComponent("customization.json").path
	}

	/// `~/.codogotchi/assignments.json` — per-platform pet assignment written by Settings.
	static func assignmentsPath() -> String {
		dataFolderURL().appendingPathComponent("assignments.json").path
	}

	/// `~/.codogotchi/prompt-attention.json` — latest prompt summaries written by hooks.
	static func promptAttentionPath() -> String {
		dataFolderURL().appendingPathComponent("prompt-attention.json").path
	}

	/// Create the folder if missing, then reveal it in Finder. Creating first
	/// keeps a first-launch open (folder not yet written) from silently no-oping.
	/// `createDirectory(withIntermediateDirectories:)` is idempotent.
	@discardableResult
	static func reveal(
		_ url: URL,
		fileManager: FileManager = .default,
		open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
	) -> Bool {
		try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
		return open(url)
	}
}

/// Reads latest prompt summaries written by hooks under `prompt-attention.json`.
/// The file is optional; any missing, stale, or malformed shape degrades to an empty badge.
enum PromptAttentionReader {
	static func latestSummary(
		origin: String,
		at path: String = CodogotchiFolders.promptAttentionPath()
	) -> String {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return "" }
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let payload = try? decoder.decode(PromptAttentionPayload.self, from: data) else {
			return ""
		}
		let prefix = "\(origin):"
		let latest = payload.bySession
			.compactMap { key, entry -> (date: Date, summary: String)? in
				guard key.hasPrefix(prefix),
					let summary = entry.summary,
					!summary.isEmpty,
					let date = parseDate(entry.updatedAt)
				else {
					return nil
				}
				return (date: date, summary: summary)
			}
			.max { lhs, rhs in lhs.date < rhs.date }
		return latest?.summary ?? ""
	}

	/// The last submitted prompt summary for one exact session, keyed by the
	/// full `"origin:session_id"` string — unlike `latestSummary(origin:)`,
	/// which collapses every session under an origin and returns whichever is
	/// newest, this looks up a single `by_session` entry directly so a
	/// per-session tooltip never leaks another session's prompt.
	static func summary(
		forSessionKey key: String,
		at path: String = CodogotchiFolders.promptAttentionPath()
	) -> String {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return "" }
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let payload = try? decoder.decode(PromptAttentionPayload.self, from: data) else {
			return ""
		}
		return payload.bySession[key]?.summary ?? ""
	}

	private static func parseDate(_ value: String?) -> Date? {
		guard let value else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: value) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: value)
	}
}

private struct PromptAttentionPayload: Decodable {
	let bySession: [String: PromptAttentionEntry]
}

private struct PromptAttentionEntry: Decodable {
	let updatedAt: String?
	let summary: String?
}

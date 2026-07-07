import Foundation

/// Resolves the LLM-auto-generated thread title a coding-agent platform's own
/// app already assigned to a session, for use as a session-keyed window's
/// default label — a friendlier fallback than "Session N" when the platform
/// happens to have already titled the thread. Every store this reads lives
/// entirely outside `~/.codogotchi/` (each is owned by the platform's own
/// app), so every lookup here is read-only, best-effort, and degrades to
/// `nil` on any missing file, permission error, or shape mismatch — never
/// throws, and never invents a title.
///
/// Only origins whose hook payload carries a real per-thread id are
/// supported (`claude_code`, `codex`, `cursor`); every other origin resolves
/// to `nil` so its window falls back to the existing "Session N" default.
enum SessionTitleResolver {
	/// Looks up `sessionId`'s auto-generated title for `origin`, or `nil` when
	/// unsupported, not-yet-titled, or unreadable. Callers should cache a
	/// non-nil result (titles rarely change after generation) and retry a
	/// `nil` result on a later tick — the title may not exist yet the moment
	/// a session's window first spawns.
	static func title(forOrigin origin: String, sessionId: String) -> String? {
		switch origin {
		case "claude_code":
			return claudeCodeTitle(sessionId: sessionId)
		case "codex":
			return codexTitle(sessionId: sessionId)
		case "cursor":
			return cursorTitle(sessionId: sessionId)
		default:
			return nil
		}
	}

	// MARK: - Claude Code (desktop app)

	/// `~/Library/Application Support/Claude/claude-code-sessions/<workspace>/<subworkspace>/local_*.json`
	/// — one JSON object per session, keyed by `cliSessionId` (the same id
	/// Claude Code's CLI calls `session_id`, and the id Codogotchi's hooks
	/// receive). `title` is written by the desktop app regardless of whether
	/// it came from its own auto-titling or a manual user rename
	/// (`titleSource`) — both are equally valid labels here, so the source is
	/// never inspected.
	static func claudeCodeTitle(
		sessionId: String,
		rootDirectory: String = NSHomeDirectory()
			+ "/Library/Application Support/Claude/claude-code-sessions"
	) -> String? {
		let fileManager = FileManager.default
		guard let workspaces = try? fileManager.contentsOfDirectory(atPath: rootDirectory) else {
			return nil
		}
		for workspace in workspaces {
			let workspacePath = "\(rootDirectory)/\(workspace)"
			guard let subworkspaces = try? fileManager.contentsOfDirectory(atPath: workspacePath) else {
				continue
			}
			for subworkspace in subworkspaces {
				let subworkspacePath = "\(workspacePath)/\(subworkspace)"
				guard let files = try? fileManager.contentsOfDirectory(atPath: subworkspacePath) else {
					continue
				}
				for file in files where file.hasPrefix("local_") && file.hasSuffix(".json") {
					let fileURL = URL(fileURLWithPath: "\(subworkspacePath)/\(file)")
					guard let data = try? Data(contentsOf: fileURL),
						let session = try? JSONDecoder().decode(ClaudeCodeSession.self, from: data),
						session.cliSessionId == sessionId
					else { continue }
					return nonEmpty(session.title)
				}
			}
		}
		return nil
	}

	private struct ClaudeCodeSession: Decodable {
		let cliSessionId: String
		let title: String?
	}

	// MARK: - Codex

	/// `~/.codex/session_index.jsonl` — append-only, one JSON line per
	/// update to a thread's metadata. The same `id` re-appears with a
	/// fresher `thread_name` after a rename, so the LAST matching line in
	/// file order wins.
	static func codexTitle(
		sessionId: String,
		path: String = NSHomeDirectory() + "/.codex/session_index.jsonl"
	) -> String? {
		guard let contents = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
			return nil
		}
		let decoder = JSONDecoder()
		var resolved: String?
		for line in contents.split(separator: "\n") {
			guard let lineData = line.data(using: .utf8),
				let entry = try? decoder.decode(CodexSessionIndexEntry.self, from: lineData),
				entry.id == sessionId
			else { continue }
			if let name = nonEmpty(entry.threadName) {
				resolved = name
			}
		}
		return resolved
	}

	private struct CodexSessionIndexEntry: Decodable {
		let id: String
		let threadName: String?

		enum CodingKeys: String, CodingKey {
			case id
			case threadName = "thread_name"
		}
	}

	// MARK: - Cursor (best-guess mapping)

	/// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
	/// — a SQLite key/value store; its `composer.composerHeaders` row holds
	/// a JSON registry of every chat thread ("composer"), each carrying its
	/// own auto-generated `name` once titled. Read via the system `sqlite3`
	/// CLI (already how this app shells out to helper binaries elsewhere)
	/// rather than linking libsqlite3 directly.
	///
	/// Cursor's hook payload's `conversation_id` — Codogotchi's `session_id`
	/// for this origin — is assumed to be the same id as `composerId` here:
	/// Cursor's own naming treats `conversation_id` as identifying the
	/// composer/chat thread, but this mapping has not been confirmed against
	/// a live hook payload (best guess, not verified — see project notes). A
	/// wrong guess only ever costs a missed title, never a wrong one:
	/// `composerId` is a UUID, so an accidental collision with an unrelated
	/// thread is not realistically possible.
	static func cursorTitle(
		sessionId: String,
		databasePath: String = NSHomeDirectory()
			+ "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
		sqliteBinaryPath: String = "/usr/bin/sqlite3"
	) -> String? {
		guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: sqliteBinaryPath)
		process.arguments = [
			databasePath,
			"SELECT value FROM ItemTable WHERE key='composer.composerHeaders';",
		]
		let stdoutPipe = Pipe()
		process.standardOutput = stdoutPipe
		process.standardError = Pipe()
		do {
			try process.run()
		} catch {
			return nil
		}
		let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0,
			let registry = try? JSONDecoder().decode(CursorComposerHeaders.self, from: data)
		else { return nil }
		return registry.allComposers
			.first { $0.composerId == sessionId }
			.flatMap { nonEmpty($0.name) }
	}

	private struct CursorComposerHeaders: Decodable {
		let allComposers: [CursorComposerHeader]
	}

	private struct CursorComposerHeader: Decodable {
		let composerId: String
		let name: String?
	}

	// MARK: - Shared

	private static func nonEmpty(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

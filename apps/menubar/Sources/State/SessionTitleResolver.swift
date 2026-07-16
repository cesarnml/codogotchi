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
/// supported (`claude_code`, `codex`, `cursor`, `vscode`, `antigravity`);
/// every other origin resolves to `nil` so its window falls back to the
/// existing "Session N" default.
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
		case "vscode":
			return vscodeTitle(sessionId: sessionId)
		case "antigravity":
			return antigravityTitle(sessionId: sessionId)
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
	/// — Cursor's SQLite store of chat/agent threads ("composers"). Newer
	/// Cursor builds (Agents / Glass sidebar) persist titles in a first-class
	/// `composerHeaders` table (`composerId` PK, `value` JSON with `name`);
	/// older builds kept a single `ItemTable` blob at key
	/// `composer.composerHeaders` (`allComposers[].name`). Prefer the table,
	/// then fall back to the legacy blob so both eras resolve. Read via the
	/// system `sqlite3` CLI (already how this app shells out to helper
	/// binaries elsewhere) rather than linking libsqlite3 directly.
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
		return cursorTitleFromComposerHeadersTable(
			sessionId: sessionId,
			databasePath: databasePath,
			sqliteBinaryPath: sqliteBinaryPath
		) ?? cursorTitleFromItemTableBlob(
			sessionId: sessionId,
			databasePath: databasePath,
			sqliteBinaryPath: sqliteBinaryPath
		)
	}

	/// Newer Cursor: `composerHeaders` rows keyed by `composerId`.
	static func cursorTitleFromComposerHeadersTable(
		sessionId: String,
		databasePath: String,
		sqliteBinaryPath: String = "/usr/bin/sqlite3"
	) -> String? {
		let escapedSessionId = sessionId.replacingOccurrences(of: "'", with: "''")
		guard
			let data = sqliteQuery(
				databasePath: databasePath,
				sqliteBinaryPath: sqliteBinaryPath,
				sql: "SELECT value FROM composerHeaders WHERE composerId='\(escapedSessionId)';"
			),
			let header = try? JSONDecoder().decode(CursorComposerHeader.self, from: data)
		else { return nil }
		return nonEmpty(header.name)
	}

	/// Legacy Cursor: single `ItemTable` registry blob.
	static func cursorTitleFromItemTableBlob(
		sessionId: String,
		databasePath: String,
		sqliteBinaryPath: String = "/usr/bin/sqlite3"
	) -> String? {
		guard
			let data = sqliteQuery(
				databasePath: databasePath,
				sqliteBinaryPath: sqliteBinaryPath,
				sql: "SELECT value FROM ItemTable WHERE key='composer.composerHeaders';"
			),
			let registry = try? JSONDecoder().decode(CursorComposerHeaders.self, from: data)
		else { return nil }
		return registry.allComposers
			.first { $0.composerId == sessionId }
			.flatMap { nonEmpty($0.name) }
	}

	private static func sqliteQuery(
		databasePath: String,
		sqliteBinaryPath: String,
		sql: String
	) -> Data? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: sqliteBinaryPath)
		process.arguments = [databasePath, sql]
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
		guard process.terminationStatus == 0, !data.isEmpty else { return nil }
		return data
	}

	private struct CursorComposerHeaders: Decodable {
		let allComposers: [CursorComposerHeader]
	}

	private struct CursorComposerHeader: Decodable {
		let composerId: String
		let name: String?
	}

	// MARK: - VS Code (GitHub Copilot Chat + Copilot CLI)

	/// Tries the VS Code app's own chat-session index first — the store the
	/// editor's chat UI actually reads its titles from — falling back to the
	/// standalone Copilot CLI's session-state directory, which only covers
	/// sessions started from the `copilot` CLI outside the editor (and which
	/// newer CLI engine versions may no longer write at all).
	static func vscodeTitle(sessionId: String) -> String? {
		vscodeChatSessionTitle(sessionId: sessionId)
			?? vscodeCopilotCliTitle(sessionId: sessionId)
	}

	/// The default VS Code user-data roots this resolver checks, Insiders
	/// first (its sessions are likelier to be live on a machine that has it
	/// installed at all — a stock-only user just misses on the first root).
	static let vscodeDefaultUserDirectories = [
		NSHomeDirectory() + "/Library/Application Support/Code - Insiders/User",
		NSHomeDirectory() + "/Library/Application Support/Code/User",
	]

	/// `<userDir>/workspaceStorage/<hash>/state.vscdb` (one per workspace) and
	/// `<userDir>/globalStorage/state.vscdb` (empty-window chats) — SQLite
	/// key/value stores whose `chat.ChatSessionStore.index` row holds a JSON
	/// registry of every chat session, keyed by the same `session_id`
	/// Copilot's hook payload sends, each entry carrying the `title` the
	/// editor's chat UI displays. Read via the system `sqlite3` CLI, exactly
	/// like `cursorTitle` (Cursor is the same VS Code fork storage layout).
	///
	/// The literal placeholder title "New Chat" resolves to `nil`: it is the
	/// editor's untitled default, not a generated title, and "Session N" is
	/// the more honest fallback.
	static func vscodeChatSessionTitle(
		sessionId: String,
		userDirectories: [String] = vscodeDefaultUserDirectories,
		sqliteBinaryPath: String = "/usr/bin/sqlite3"
	) -> String? {
		let fileManager = FileManager.default
		for userDirectory in userDirectories {
			var databasePaths = ["\(userDirectory)/globalStorage/state.vscdb"]
			let workspaceRoot = "\(userDirectory)/workspaceStorage"
			if let workspaces = try? fileManager.contentsOfDirectory(atPath: workspaceRoot) {
				databasePaths += workspaces.map { "\(workspaceRoot)/\($0)/state.vscdb" }
			}
			for databasePath in databasePaths {
				guard
					let title = chatSessionStoreTitle(
						sessionId: sessionId,
						databasePath: databasePath,
						sqliteBinaryPath: sqliteBinaryPath
					)
				else { continue }
				return title
			}
		}
		return nil
	}

	private static func chatSessionStoreTitle(
		sessionId: String,
		databasePath: String,
		sqliteBinaryPath: String
	) -> String? {
		guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: sqliteBinaryPath)
		process.arguments = [
			databasePath,
			"SELECT value FROM ItemTable WHERE key='chat.ChatSessionStore.index';",
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
			let index = try? JSONDecoder().decode(VscodeChatSessionIndex.self, from: data),
			let title = nonEmpty(index.entries[sessionId]?.title),
			title != "New Chat"
		else { return nil }
		return title
	}

	private struct VscodeChatSessionIndex: Decodable {
		let entries: [String: VscodeChatSessionEntry]
	}

	private struct VscodeChatSessionEntry: Decodable {
		let title: String?
	}

	/// `~/.copilot/session-state/<sessionId>/workspace.yaml` — one directory
	/// per session, id-named to match the `session_id` Copilot's hook payload
	/// sends. The file is flat `key: value` YAML with a `summary` field
	/// Copilot generates from the session's content; no YAML parser is
	/// needed since every value here is a single unquoted scalar on its own
	/// line.
	static func vscodeCopilotCliTitle(
		sessionId: String,
		rootDirectory: String = NSHomeDirectory() + "/.copilot/session-state"
	) -> String? {
		let path = "\(rootDirectory)/\(sessionId)/workspace.yaml"
		guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
			return nil
		}
		for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
			guard line.hasPrefix("summary:") else { continue }
			return nonEmpty(String(line.dropFirst("summary:".count)))
		}
		return nil
	}

	// MARK: - Antigravity

	/// Tries the cheap, reliable per-conversation source first (own
	/// transcript's CHECKPOINT title), falling back to the expensive
	/// cross-conversation scan only when that's absent — e.g. a conversation
	/// short enough to never trigger a context-window checkpoint.
	static func antigravityTitle(
		sessionId: String,
		rootDirectory: String = NSHomeDirectory() + "/.gemini/antigravity/brain",
		maxFilesScanned: Int = 20
	) -> String? {
		antigravityOwnTranscriptTitle(sessionId: sessionId, rootDirectory: rootDirectory)
			?? antigravityCrossConversationTitle(
				sessionId: sessionId,
				rootDirectory: rootDirectory,
				maxFilesScanned: maxFilesScanned
			)
	}

	/// `brain/<sessionId>/.system_generated/logs/transcript.jsonl` — once a
	/// conversation grows long enough to need context-window truncation,
	/// Antigravity writes a CHECKPOINT system event summarizing the truncated
	/// history for its own future reference, and that summary always opens
	/// with `# USER Objective:\n<title>`. This is a direct, single-file read
	/// keyed exactly by `sessionId` — far cheaper and more reliable than the
	/// cross-conversation scan below — but only appears after that
	/// truncation threshold; a short conversation never gets a CHECKPOINT and
	/// this resolves to `nil`.
	static func antigravityOwnTranscriptTitle(
		sessionId: String,
		rootDirectory: String = NSHomeDirectory() + "/.gemini/antigravity/brain"
	) -> String? {
		let path = "\(rootDirectory)/\(sessionId)/.system_generated/logs/transcript.jsonl"
		guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
		guard let pattern = try? NSRegularExpression(pattern: "# USER Objective:\\n(.+)") else { return nil }
		for line in contents.split(separator: "\n") {
			guard let lineData = line.data(using: .utf8),
				let event = try? JSONDecoder().decode(AntigravityTranscriptLine.self, from: lineData),
				event.type == "CHECKPOINT",
				let content = event.content
			else { continue }
			let searchRange = NSRange(content.startIndex..., in: content)
			guard let match = pattern.firstMatch(in: content, range: searchRange),
				let titleRange = Range(match.range(at: 1), in: content)
			else { continue }
			if let title = nonEmpty(String(content[titleRange])) {
				return title
			}
		}
		return nil
	}

	/// Fallback when `antigravityOwnTranscriptTitle` finds nothing: Antigravity
	/// has no per-conversation title file for a conversation that never got
	/// checkpointed — but the title can still resurface later, quoted inside
	/// a DIFFERENT, more-recent conversation's transcript, in a "Conversation
	/// History" system block Antigravity writes summarizing recent threads
	/// (format: `## Conversation <id>: <title>`). Recovering a title for
	/// `sessionId` this way means scanning other conversations' transcripts
	/// for a mention of it — there is no direct lookup. Bounded to the
	/// `maxFilesScanned` most recently modified transcripts, checked
	/// newest-first (a later conversation's recap is more likely to carry the
	/// freshest title, and this keeps a best-effort read from scanning an
	/// unbounded, ever-growing directory). A title that was never summarized
	/// by a later conversation, or fell outside the scan window, resolves to
	/// `nil` — same as any other not-yet-titled session.
	static func antigravityCrossConversationTitle(
		sessionId: String,
		rootDirectory: String = NSHomeDirectory() + "/.gemini/antigravity/brain",
		maxFilesScanned: Int = 20
	) -> String? {
		let fileManager = FileManager.default
		guard let conversationDirs = try? fileManager.contentsOfDirectory(atPath: rootDirectory) else {
			return nil
		}
		let candidates: [(path: String, modified: Date)] = conversationDirs.compactMap { dir in
			let path = "\(rootDirectory)/\(dir)/.system_generated/logs/transcript.jsonl"
			guard let attributes = try? fileManager.attributesOfItem(atPath: path),
				let modified = attributes[.modificationDate] as? Date
			else { return nil }
			return (path, modified)
		}
		let mostRecentFirst = candidates.sorted { $0.modified > $1.modified }.prefix(maxFilesScanned)

		guard
			let pattern = try? NSRegularExpression(
				pattern: "## Conversation \(NSRegularExpression.escapedPattern(for: sessionId)): (.+)"
			)
		else { return nil }

		for candidate in mostRecentFirst {
			guard let contents = try? String(contentsOfFile: candidate.path, encoding: .utf8) else { continue }
			for line in contents.split(separator: "\n") {
				guard let lineData = line.data(using: .utf8),
					let event = try? JSONDecoder().decode(AntigravityTranscriptLine.self, from: lineData),
					event.type == "CONVERSATION_HISTORY",
					let content = event.content
				else { continue }
				let searchRange = NSRange(content.startIndex..., in: content)
				guard let match = pattern.firstMatch(in: content, range: searchRange),
					let titleRange = Range(match.range(at: 1), in: content)
				else { continue }
				if let title = nonEmpty(String(content[titleRange])) {
					return title
				}
			}
		}
		return nil
	}

	private struct AntigravityTranscriptLine: Decodable {
		let type: String?
		let content: String?
	}

	// MARK: - Shared

	private static func nonEmpty(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

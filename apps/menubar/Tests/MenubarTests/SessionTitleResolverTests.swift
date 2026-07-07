import XCTest

@testable import Codogotchi

final class SessionTitleResolverTests: XCTestCase {

	private func tempDirectory() -> String {
		let path = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-title-resolver-\(UUID().uuidString)")
			.path
		try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
		return path
	}

	// MARK: - title(forOrigin:) dispatch

	func testUnsupportedOriginResolvesToNil() {
		XCTAssertNil(SessionTitleResolver.title(forOrigin: "manual", sessionId: "s1"))
	}

	// MARK: - Claude Code

	func testClaudeCodeTitleFindsMatchingSessionAcrossNestedWorkspaceDirs() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		let subworkspace = "\(root)/workspace-a/subworkspace-a"
		try FileManager.default.createDirectory(atPath: subworkspace, withIntermediateDirectories: true)
		try #"{"cliSessionId":"abc-123","title":"Locate session auto label"}"#
			.write(toFile: "\(subworkspace)/local_x.json", atomically: true, encoding: .utf8)

		XCTAssertEqual(
			SessionTitleResolver.claudeCodeTitle(sessionId: "abc-123", rootDirectory: root),
			"Locate session auto label"
		)
	}

	func testClaudeCodeTitleReturnsNilWhenNoSessionMatches() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		let subworkspace = "\(root)/workspace-a/subworkspace-a"
		try FileManager.default.createDirectory(atPath: subworkspace, withIntermediateDirectories: true)
		try #"{"cliSessionId":"other-session","title":"Unrelated"}"#
			.write(toFile: "\(subworkspace)/local_x.json", atomically: true, encoding: .utf8)

		XCTAssertNil(SessionTitleResolver.claudeCodeTitle(sessionId: "abc-123", rootDirectory: root))
	}

	func testClaudeCodeTitleReturnsNilWhenRootDirectoryMissing() {
		XCTAssertNil(
			SessionTitleResolver.claudeCodeTitle(
				sessionId: "abc-123",
				rootDirectory: tempDirectory() + "/does-not-exist"
			)
		)
	}

	func testClaudeCodeTitleReturnsNilForEmptyTitle() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		let subworkspace = "\(root)/workspace-a/subworkspace-a"
		try FileManager.default.createDirectory(atPath: subworkspace, withIntermediateDirectories: true)
		try #"{"cliSessionId":"abc-123","title":""}"#
			.write(toFile: "\(subworkspace)/local_x.json", atomically: true, encoding: .utf8)

		XCTAssertNil(SessionTitleResolver.claudeCodeTitle(sessionId: "abc-123", rootDirectory: root))
	}

	// MARK: - Codex

	func testCodexTitleReturnsThreadNameForMatchingId() throws {
		let path = tempDirectory() + "/session_index.jsonl"
		let contents = """
			{"id":"019f39b0-f6fe","thread_name":"Locate session auto label","updated_at":"2026-07-06T23:09:09Z"}
			"""
		try contents.write(toFile: path, atomically: true, encoding: .utf8)

		XCTAssertEqual(
			SessionTitleResolver.codexTitle(sessionId: "019f39b0-f6fe", path: path),
			"Locate session auto label"
		)
	}

	// Codex's session index is append-only: a rename re-appends the same id
	// with a fresh thread_name, so the LAST matching line must win, not the
	// first.
	func testCodexTitleUsesLastMatchingLineWhenIdReappears() throws {
		let path = tempDirectory() + "/session_index.jsonl"
		let contents = """
			{"id":"019f39b0-f6fe","thread_name":"Locate session auto label","updated_at":"2026-07-06T23:09:09Z"}
			{"id":"019f39b0-f6fe","thread_name":"Renamed SessionLabel research","updated_at":"2026-07-06T23:19:30Z"}
			"""
		try contents.write(toFile: path, atomically: true, encoding: .utf8)

		XCTAssertEqual(
			SessionTitleResolver.codexTitle(sessionId: "019f39b0-f6fe", path: path),
			"Renamed SessionLabel research"
		)
	}

	func testCodexTitleReturnsNilWhenNoIdMatches() throws {
		let path = tempDirectory() + "/session_index.jsonl"
		try #"{"id":"other","thread_name":"Unrelated","updated_at":"2026-07-06T23:09:09Z"}"#
			.write(toFile: path, atomically: true, encoding: .utf8)

		XCTAssertNil(SessionTitleResolver.codexTitle(sessionId: "019f39b0-f6fe", path: path))
	}

	func testCodexTitleReturnsNilWhenFileMissing() {
		XCTAssertNil(
			SessionTitleResolver.codexTitle(sessionId: "019f39b0-f6fe", path: tempDirectory() + "/missing.jsonl")
		)
	}

	// MARK: - Cursor (best-guess composerId mapping)

	private func makeCursorDatabase(allComposersJSON: String) throws -> String {
		let dbPath = tempDirectory() + "/state.vscdb"
		let payload = #"{"allComposers":\#(allComposersJSON)}"#
		let sql = """
			CREATE TABLE ItemTable(key TEXT UNIQUE, value TEXT);
			INSERT INTO ItemTable(key, value) VALUES ('composer.composerHeaders', '\(payload.replacingOccurrences(of: "'", with: "''"))');
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
		process.arguments = [dbPath, sql]
		try process.run()
		process.waitUntilExit()
		return dbPath
	}

	func testCursorTitleFindsMatchingComposerName() throws {
		let dbPath = try makeCursorDatabase(
			allComposersJSON: #"[{"composerId":"14394ae7-e345","name":"Locate session auto label"}]"#
		)
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		XCTAssertEqual(
			SessionTitleResolver.cursorTitle(sessionId: "14394ae7-e345", databasePath: dbPath),
			"Locate session auto label"
		)
	}

	func testCursorTitleReturnsNilWhenComposerHasNoNameYet() throws {
		let dbPath = try makeCursorDatabase(
			allComposersJSON: #"[{"composerId":"14394ae7-e345"}]"#
		)
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		XCTAssertNil(SessionTitleResolver.cursorTitle(sessionId: "14394ae7-e345", databasePath: dbPath))
	}

	func testCursorTitleReturnsNilWhenNoComposerIdMatches() throws {
		let dbPath = try makeCursorDatabase(
			allComposersJSON: #"[{"composerId":"other","name":"Unrelated"}]"#
		)
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		XCTAssertNil(SessionTitleResolver.cursorTitle(sessionId: "14394ae7-e345", databasePath: dbPath))
	}

	func testCursorTitleReturnsNilWhenDatabaseMissing() {
		XCTAssertNil(
			SessionTitleResolver.cursorTitle(
				sessionId: "14394ae7-e345",
				databasePath: tempDirectory() + "/missing.vscdb"
			)
		)
	}

	// MARK: - VS Code (chat-session index in state.vscdb)

	private func makeVscodeUserDirectory(
		indexJSON: String,
		inGlobalStorage: Bool = false,
		workspaceHash: String = "workspace-hash-a"
	) throws -> String {
		let userDir = tempDirectory()
		let dbDir =
			inGlobalStorage
			? "\(userDir)/globalStorage"
			: "\(userDir)/workspaceStorage/\(workspaceHash)"
		try FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
		let sql = """
			CREATE TABLE ItemTable(key TEXT UNIQUE, value TEXT);
			INSERT INTO ItemTable(key, value) VALUES ('chat.ChatSessionStore.index', '\(indexJSON.replacingOccurrences(of: "'", with: "''"))');
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
		process.arguments = ["\(dbDir)/state.vscdb", sql]
		try process.run()
		process.waitUntilExit()
		return userDir
	}

	func testVscodeChatSessionTitleFindsMatchInWorkspaceStore() throws {
		let userDir = try makeVscodeUserDirectory(
			indexJSON: #"{"version":1,"entries":{"377658c9-4d46":{"sessionId":"377658c9-4d46","title":"Once again ... immediately do nothing"}}}"#
		)
		defer { try? FileManager.default.removeItem(atPath: userDir) }

		XCTAssertEqual(
			SessionTitleResolver.vscodeChatSessionTitle(
				sessionId: "377658c9-4d46", userDirectories: [userDir]),
			"Once again ... immediately do nothing"
		)
	}

	func testVscodeChatSessionTitleFindsMatchInGlobalStore() throws {
		let userDir = try makeVscodeUserDirectory(
			indexJSON: #"{"version":1,"entries":{"63f085ae-fcda":{"sessionId":"63f085ae-fcda","title":"Fun facts about bees"}}}"#,
			inGlobalStorage: true
		)
		defer { try? FileManager.default.removeItem(atPath: userDir) }

		XCTAssertEqual(
			SessionTitleResolver.vscodeChatSessionTitle(
				sessionId: "63f085ae-fcda", userDirectories: [userDir]),
			"Fun facts about bees"
		)
	}

	// "New Chat" is VS Code's untitled placeholder, not a generated title —
	// surfacing it would replace the more honest "Session N" fallback.
	func testVscodeChatSessionTitleTreatsNewChatPlaceholderAsNil() throws {
		let userDir = try makeVscodeUserDirectory(
			indexJSON: #"{"version":1,"entries":{"s1":{"sessionId":"s1","title":"New Chat"}}}"#
		)
		defer { try? FileManager.default.removeItem(atPath: userDir) }

		XCTAssertNil(
			SessionTitleResolver.vscodeChatSessionTitle(sessionId: "s1", userDirectories: [userDir])
		)
	}

	func testVscodeChatSessionTitleReturnsNilWhenNoSessionMatches() throws {
		let userDir = try makeVscodeUserDirectory(
			indexJSON: #"{"version":1,"entries":{"other":{"sessionId":"other","title":"Unrelated"}}}"#
		)
		defer { try? FileManager.default.removeItem(atPath: userDir) }

		XCTAssertNil(
			SessionTitleResolver.vscodeChatSessionTitle(sessionId: "missing", userDirectories: [userDir])
		)
	}

	func testVscodeChatSessionTitleReturnsNilWhenUserDirectoryMissing() {
		XCTAssertNil(
			SessionTitleResolver.vscodeChatSessionTitle(
				sessionId: "s1",
				userDirectories: [tempDirectory() + "/does-not-exist"]
			)
		)
	}

	// MARK: - VS Code (standalone Copilot CLI fallback)

	func testVscodeTitleReturnsSummaryForMatchingSession() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		let sessionDir = "\(root)/188792af-15ca-44f4-8980-385fd46086ce"
		try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
		let yaml = """
			id: 188792af-15ca-44f4-8980-385fd46086ce
			cwd: /Users/cesar
			summary: List Directory Contents
			summary_count: 0
			"""
		try yaml.write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)

		XCTAssertEqual(
			SessionTitleResolver.vscodeCopilotCliTitle(sessionId: "188792af-15ca-44f4-8980-385fd46086ce", rootDirectory: root),
			"List Directory Contents"
		)
	}

	func testVscodeTitleReturnsNilWhenSummaryEmpty() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		let sessionDir = "\(root)/s1"
		try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
		try "id: s1\nsummary: \n"
			.write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)

		XCTAssertNil(SessionTitleResolver.vscodeCopilotCliTitle(sessionId: "s1", rootDirectory: root))
	}

	func testVscodeTitleReturnsNilWhenSessionDirMissing() {
		XCTAssertNil(
			SessionTitleResolver.vscodeCopilotCliTitle(sessionId: "missing", rootDirectory: tempDirectory())
		)
	}

	// MARK: - Antigravity

	private func writeAntigravityTranscript(
		rootDirectory: String,
		conversationDir: String,
		historyContent: String
	) throws {
		let logsDir = "\(rootDirectory)/\(conversationDir)/.system_generated/logs"
		try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
		let event: [String: String] = ["type": "CONVERSATION_HISTORY", "content": historyContent]
		let line = String(data: try JSONEncoder().encode(event), encoding: .utf8)!
		try line.write(toFile: "\(logsDir)/transcript.jsonl", atomically: true, encoding: .utf8)
	}

	private func writeAntigravityCheckpoint(
		rootDirectory: String,
		sessionId: String,
		checkpointContent: String
	) throws {
		let logsDir = "\(rootDirectory)/\(sessionId)/.system_generated/logs"
		try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
		let event: [String: String] = ["type": "CHECKPOINT", "content": checkpointContent]
		let line = String(data: try JSONEncoder().encode(event), encoding: .utf8)!
		try line.write(toFile: "\(logsDir)/transcript.jsonl", atomically: true, encoding: .utf8)
	}

	func testAntigravityOwnTranscriptTitleFindsUserObjectiveInCheckpoint() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityCheckpoint(
			rootDirectory: root,
			sessionId: "94f7eb48-7bbc-459c-af5b-baa60e077e7a",
			checkpointContent: """
				{{ CHECKPOINT 0 }}
				# USER Objective:
				Ten Fascinating Bear Facts

				# User Requests
				"""
		)

		XCTAssertEqual(
			SessionTitleResolver.antigravityOwnTranscriptTitle(
				sessionId: "94f7eb48-7bbc-459c-af5b-baa60e077e7a",
				rootDirectory: root
			),
			"Ten Fascinating Bear Facts"
		)
	}

	func testAntigravityOwnTranscriptTitleReturnsNilWhenNoCheckpointYet() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "s1",
			historyContent: "irrelevant"
		)

		XCTAssertNil(SessionTitleResolver.antigravityOwnTranscriptTitle(sessionId: "s1", rootDirectory: root))
	}

	func testAntigravityTitlePrefersOwnTranscriptOverCrossConversationScan() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityCheckpoint(
			rootDirectory: root,
			sessionId: "s1",
			checkpointContent: "# USER Objective:\nOwn Transcript Title"
		)
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "later-convo",
			historyContent: "## Conversation s1: Cross Conversation Title"
		)

		XCTAssertEqual(
			SessionTitleResolver.antigravityTitle(sessionId: "s1", rootDirectory: root),
			"Own Transcript Title"
		)
	}

	func testAntigravityTitleFallsBackToCrossConversationScanWhenNoCheckpoint() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "later-convo",
			historyContent: "## Conversation s1: Cross Conversation Title"
		)

		XCTAssertEqual(
			SessionTitleResolver.antigravityTitle(sessionId: "s1", rootDirectory: root),
			"Cross Conversation Title"
		)
	}

	func testAntigravityCrossConversationTitleFindsMatchInAnotherConversationsTranscript() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "later-convo",
			historyContent: """
				## Conversation d6ee322b-fa97-4a7e-867f-b697c3edc786: Pause All Immediate Actions
				- Created: 2026-07-07T18:47:08Z
				"""
		)

		XCTAssertEqual(
			SessionTitleResolver.antigravityCrossConversationTitle(
				sessionId: "d6ee322b-fa97-4a7e-867f-b697c3edc786",
				rootDirectory: root
			),
			"Pause All Immediate Actions"
		)
	}

	func testAntigravityCrossConversationTitlePrefersMostRecentlyModifiedTranscript() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "stale-convo",
			historyContent: "## Conversation target-id: Stale Title"
		)
		let staleTranscript = "\(root)/stale-convo/.system_generated/logs/transcript.jsonl"
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSinceNow: -3600)],
			ofItemAtPath: staleTranscript
		)
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "fresh-convo",
			historyContent: "## Conversation target-id: Fresh Title"
		)

		XCTAssertEqual(
			SessionTitleResolver.antigravityCrossConversationTitle(sessionId: "target-id", rootDirectory: root),
			"Fresh Title"
		)
	}

	func testAntigravityCrossConversationTitleReturnsNilWhenNoConversationMentionsSession() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "other-convo",
			historyContent: "## Conversation unrelated-id: Some Title"
		)

		XCTAssertNil(SessionTitleResolver.antigravityCrossConversationTitle(sessionId: "target-id", rootDirectory: root))
	}

	func testAntigravityCrossConversationTitleRespectsMaxFilesScannedBound() throws {
		let root = tempDirectory()
		defer { try? FileManager.default.removeItem(atPath: root) }
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "only-match",
			historyContent: "## Conversation target-id: Should Not Be Found"
		)
		let onlyMatchTranscript = "\(root)/only-match/.system_generated/logs/transcript.jsonl"
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSinceNow: -3600)],
			ofItemAtPath: onlyMatchTranscript
		)
		try writeAntigravityTranscript(
			rootDirectory: root,
			conversationDir: "newer-convo",
			historyContent: "## Conversation other-id: Unrelated"
		)

		XCTAssertNil(
			SessionTitleResolver.antigravityCrossConversationTitle(sessionId: "target-id", rootDirectory: root, maxFilesScanned: 1)
		)
	}

	func testAntigravityCrossConversationTitleReturnsNilWhenRootDirectoryMissing() {
		XCTAssertNil(
			SessionTitleResolver.antigravityCrossConversationTitle(
				sessionId: "target-id",
				rootDirectory: tempDirectory() + "/does-not-exist"
			)
		)
	}
}

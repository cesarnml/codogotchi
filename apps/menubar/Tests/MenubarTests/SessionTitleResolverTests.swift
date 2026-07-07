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
		XCTAssertNil(SessionTitleResolver.title(forOrigin: "vscode", sessionId: "s1"))
		XCTAssertNil(SessionTitleResolver.title(forOrigin: "antigravity", sessionId: "s1"))
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
}

import XCTest

@testable import Codogotchi

// [red] SessionLabelStore does not exist yet — this file causes a compile
// error until the GREEN implementation is added.
final class SessionLabelStoreTests: XCTestCase {

	private func tempPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("session-labels-\(UUID().uuidString).json")
			.path
	}

	// MARK: - Absent file reads as empty without throwing

	func testAbsentFileReadsAsEmpty() {
		let path = tempPath()
		XCTAssertNil(SessionLabelStore.label(for: "claude_code:sess1", at: path))
	}

	// MARK: - Write then read returns it for that key

	func testWriteThenReadReturnsLabel() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		SessionLabelStore.setLabel("Refactor pass", for: "claude_code:sess1", at: path)

		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess1", at: path), "Refactor pass")
	}

	// MARK: - Read-merge-write: a second key write preserves the first

	func testSecondKeyWritePreservesFirst() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		SessionLabelStore.setLabel("First session", for: "claude_code:sess1", at: path)
		SessionLabelStore.setLabel("Second session", for: "claude_code:sess2", at: path)

		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess1", at: path), "First session")
		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess2", at: path), "Second session")
	}

	// MARK: - 24-char cap: stored truncated at the boundary

	func testLabelLongerThan24CharsIsTruncated() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let longLabel = String(repeating: "x", count: 40)
		SessionLabelStore.setLabel(longLabel, for: "claude_code:sess1", at: path)

		let stored = SessionLabelStore.label(for: "claude_code:sess1", at: path)
		XCTAssertEqual(stored, String(repeating: "x", count: 24))
	}

	func testLabelExactly24CharsIsUnchanged() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let label = String(repeating: "y", count: 24)
		SessionLabelStore.setLabel(label, for: "claude_code:sess1", at: path)

		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess1", at: path), label)
	}

	// MARK: - Whitespace is trimmed before the cap is applied

	func testLabelIsTrimmed() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		SessionLabelStore.setLabel("  padded  ", for: "claude_code:sess1", at: path)

		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess1", at: path), "padded")
	}

	// MARK: - removeLabel drops exactly one key

	func testRemoveLabelDropsOnlyThatKey() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		SessionLabelStore.setLabel("First session", for: "claude_code:sess1", at: path)
		SessionLabelStore.setLabel("Second session", for: "claude_code:sess2", at: path)

		SessionLabelStore.removeLabel(for: "claude_code:sess1", at: path)

		XCTAssertNil(SessionLabelStore.label(for: "claude_code:sess1", at: path))
		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:sess2", at: path), "Second session")
	}

	func testRemoveLabelOnAbsentFileDoesNotThrow() {
		let path = tempPath()
		SessionLabelStore.removeLabel(for: "claude_code:sess1", at: path)
		XCTAssertNil(SessionLabelStore.label(for: "claude_code:sess1", at: path))
	}
}

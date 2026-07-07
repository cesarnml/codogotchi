import XCTest

@testable import Codogotchi

final class RetrievedSessionTitleStoreTests: XCTestCase {

	private func tempPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("retrieved-session-labels-\(UUID().uuidString).json")
			.path
	}

	func testAbsentFileReadsAsNil() {
		let path = tempPath()
		XCTAssertNil(RetrievedSessionTitleStore.title(for: "codex:s1", at: path))
	}

	func testSetTitleThenReadReturnsIt() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		RetrievedSessionTitleStore.setTitle("Locate session auto label", for: "codex:s1", at: path)

		XCTAssertEqual(
			RetrievedSessionTitleStore.title(for: "codex:s1", at: path), "Locate session auto label")
	}

	// The 24-char cap on `SessionLabelStore` deliberately does not apply here —
	// a platform's own thread title is exempt, just like the "Sync Label"
	// write path.
	func testSetTitleDoesNotCapLongTitles() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let longTitle = String(repeating: "x", count: 40)
		RetrievedSessionTitleStore.setTitle(longTitle, for: "codex:s1", at: path)

		XCTAssertEqual(RetrievedSessionTitleStore.title(for: "codex:s1", at: path), longTitle)
	}

	func testSetTitleTrimsWhitespace() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		RetrievedSessionTitleStore.setTitle("  Locate session auto label  ", for: "codex:s1", at: path)

		XCTAssertEqual(
			RetrievedSessionTitleStore.title(for: "codex:s1", at: path), "Locate session auto label")
	}

	func testSecondKeyWritePreservesFirst() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		RetrievedSessionTitleStore.setTitle("First session", for: "codex:s1", at: path)
		RetrievedSessionTitleStore.setTitle("Second session", for: "codex:s2", at: path)

		XCTAssertEqual(RetrievedSessionTitleStore.title(for: "codex:s1", at: path), "First session")
		XCTAssertEqual(RetrievedSessionTitleStore.title(for: "codex:s2", at: path), "Second session")
	}

	func testRemoveTitleDropsOnlyThatKey() {
		let path = tempPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		RetrievedSessionTitleStore.setTitle("First session", for: "codex:s1", at: path)
		RetrievedSessionTitleStore.setTitle("Second session", for: "codex:s2", at: path)

		RetrievedSessionTitleStore.removeTitle(for: "codex:s1", at: path)

		XCTAssertNil(RetrievedSessionTitleStore.title(for: "codex:s1", at: path))
		XCTAssertEqual(RetrievedSessionTitleStore.title(for: "codex:s2", at: path), "Second session")
	}

	func testRemoveTitleOnAbsentFileDoesNotThrow() {
		let path = tempPath()
		RetrievedSessionTitleStore.removeTitle(for: "codex:s1", at: path)
		XCTAssertNil(RetrievedSessionTitleStore.title(for: "codex:s1", at: path))
	}
}

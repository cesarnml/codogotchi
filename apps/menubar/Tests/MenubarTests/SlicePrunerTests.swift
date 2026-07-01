import Foundation
import XCTest

@testable import Codogotchi

final class SlicePrunerTests: XCTestCase {
	private var dir: URL!

	override func setUp() {
		super.setUp()
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("SlicePrunerTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
		super.tearDown()
	}

	// MARK: - Helpers

	private func writeSlice(_ name: String, mtimeAgo: TimeInterval, now: Date = Date()) {
		let url = dir.appendingPathComponent(name)
		try! Data("{\"activity_state\":\"idle\"}".utf8).write(to: url)
		try! FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-mtimeAgo)], ofItemAtPath: url.path)
	}

	private func exists(_ name: String) -> Bool {
		FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
	}

	// MARK: - Age-based deletion

	func testPrunesSlicesOlderThanMaxAge() {
		let now = Date()
		writeSlice("codex:old.json", mtimeAgo: 48 * 60 * 60, now: now)
		writeSlice("codex:fresh.json", mtimeAgo: 60, now: now)

		let deleted = SlicePruner.prune(at: dir.path, maxAge: 24 * 60 * 60, now: now)

		XCTAssertEqual(deleted, 1)
		XCTAssertFalse(exists("codex:old.json"), "a slice past maxAge must be deleted")
		XCTAssertTrue(exists("codex:fresh.json"), "a fresh slice must survive")
	}

	func testKeepsSlicesWithinReaderStaleTTL() {
		let now = Date()
		// 1h old — still inside the reader's 2h staleTTL, so it may be rendered and
		// must never be pruned regardless of the (larger) prune horizon.
		writeSlice("claude_code:recent.json", mtimeAgo: 60 * 60, now: now)

		let deleted = SlicePruner.prune(at: dir.path, maxAge: 24 * 60 * 60, now: now)

		XCTAssertEqual(deleted, 0)
		XCTAssertTrue(exists("claude_code:recent.json"))
	}

	func testDefaultMaxAgeExceedsReaderStaleTTL() {
		// Guards the invariant that pruning never removes a slice the reader would
		// still render (reader staleTTL is 2h).
		XCTAssertGreaterThan(SlicePruner.defaultMaxAge, 2 * 60 * 60)
	}

	// MARK: - Partial / non-slice files

	func testSweepsAbandonedTmpPartialsRegardlessOfAge() {
		let now = Date()
		let partial = dir.appendingPathComponent(".tmp-partial.json")
		try! Data("{}".utf8).write(to: partial)
		// Fresh mtime — still swept because it is a leftover atomic-write partial.
		try! FileManager.default.setAttributes(
			[.modificationDate: now], ofItemAtPath: partial.path)

		let deleted = SlicePruner.prune(at: dir.path, maxAge: 24 * 60 * 60, now: now)

		XCTAssertEqual(deleted, 1)
		XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
	}

	func testIgnoresNonJsonFiles() {
		let now = Date()
		let note = dir.appendingPathComponent("README.txt")
		try! Data("hello".utf8).write(to: note)
		try! FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-48 * 60 * 60)], ofItemAtPath: note.path)

		let deleted = SlicePruner.prune(at: dir.path, maxAge: 24 * 60 * 60, now: now)

		XCTAssertEqual(deleted, 0)
		XCTAssertTrue(FileManager.default.fileExists(atPath: note.path),
			"a non-.json file must never be pruned")
	}

	func testDoesNotRemoveDirectoriesNamedLikeSlices() {
		let now = Date()
		let subdir = dir.appendingPathComponent("codex:weird.json")
		try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
		try! FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-72 * 60 * 60)], ofItemAtPath: subdir.path)

		let deleted = SlicePruner.prune(at: dir.path, maxAge: 24 * 60 * 60, now: now)

		XCTAssertEqual(deleted, 0)
		XCTAssertTrue(FileManager.default.fileExists(atPath: subdir.path),
			"a directory must not be deleted even if its name ends in .json and it is old")
	}

	// MARK: - Missing directory

	func testMissingDirectoryReturnsZero() {
		let missing = dir.appendingPathComponent("nope").path
		XCTAssertEqual(SlicePruner.prune(at: missing), 0)
	}
}

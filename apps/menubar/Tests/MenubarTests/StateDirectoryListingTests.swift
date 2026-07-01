import XCTest

@testable import Codogotchi

/// Focused coverage for the P15.02 shared per-tick directory listing. The poll
/// path relies on `scan` faithfully reproducing what each consumer's own
/// `contentsOfDirectory` + `attributesOfItem` produced, so the branches that
/// matter are: missing directory → nil, present directory → one entry per child
/// with an mtime, and empty directory → non-nil empty listing.
final class StateDirectoryListingTests: XCTestCase {

	private func makeTempDir() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("state-dir-listing-\(UUID().uuidString)", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	func testScanMissingDirectoryReturnsNil() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
		XCTAssertNil(
			StateDirectoryListing.scan(at: missing.path),
			"a missing directory must return nil so callers keep their missing-directory branch")
	}

	func testScanEmptyDirectoryReturnsEmptyListing() {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let listing = StateDirectoryListing.scan(at: dir.path)
		XCTAssertNotNil(listing, "an existing empty directory must return a non-nil listing, not nil")
		XCTAssertEqual(listing?.entries.count, 0, "an empty directory yields zero entries")
	}

	func testScanReturnsOneEntryPerChildWithMtime() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		try "{}".write(
			to: dir.appendingPathComponent("claude_code:abc.json"), atomically: true, encoding: .utf8)
		try "{}".write(
			to: dir.appendingPathComponent("cursor:def.json"), atomically: true, encoding: .utf8)

		let listing = try XCTUnwrap(StateDirectoryListing.scan(at: dir.path))
		let names = Set(listing.entries.map(\.name))
		XCTAssertEqual(names, ["claude_code:abc.json", "cursor:def.json"])
		for entry in listing.entries {
			XCTAssertNotNil(entry.mtime, "a real regular file must carry a filesystem mtime")
		}
	}
}

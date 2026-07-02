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

	// MARK: - Listing branch ≡ self-scan branch (the P15.03 seam)

	/// The pre-existing suite only exercises the self-scan (`listing == nil`)
	/// path; nothing proves the shared-listing branch yields identical results.
	/// This equivalence check locks that guarantee for `readPerPlatformDirectory`,
	/// which is the exact consumer P15.03 extends to per-session granularity.
	func testListingBranchMatchesSelfScanForReadPerPlatformDirectory() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		func slice(origin: String, state: String) -> String {
			"""
			{ "activity_state": "\(state)", "updated_at": "\(iso)", "source_event": { "origin": "\(origin)" } }
			"""
		}
		try slice(origin: "claude_code", state: "focused")
			.write(to: dir.appendingPathComponent("claude_code:s1.json"), atomically: true, encoding: .utf8)
		try slice(origin: "cursor", state: "editing")
			.write(to: dir.appendingPathComponent("cursor:s1.json"), atomically: true, encoding: .utf8)

		let listing = try XCTUnwrap(StateDirectoryListing.scan(at: dir.path))
		let selfScan = StateJsonReader.readPerPlatformDirectory(at: dir.path, now: now)
		let viaListing = StateJsonReader.readPerPlatformDirectory(at: dir.path, now: now, listing: listing)

		guard case .success(let selfMap) = selfScan, case .success(let listingMap) = viaListing else {
			return XCTFail("both the self-scan and shared-listing reads must succeed")
		}
		XCTAssertEqual(
			selfMap, listingMap,
			"the shared-listing branch must produce results identical to the self-scan branch")
		XCTAssertEqual(Set(selfMap.keys), ["claude_code", "cursor"], "both origins must be grouped")
	}
}

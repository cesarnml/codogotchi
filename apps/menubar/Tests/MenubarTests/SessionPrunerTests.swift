import XCTest

@testable import Codogotchi

/// P15.07 behavior contract for manual "Prune Session": deletes the slice,
/// releases the free-list number, and removes the session-labels.json key —
/// the same end-state as automatic TTL expiry.
final class SessionPrunerTests: XCTestCase {
	private var dir: URL!
	private var labelsFile: URL!

	override func setUp() {
		super.setUp()
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("SessionPrunerTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		labelsFile = dir.appendingPathComponent("session-labels.json")
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
		super.tearDown()
	}

	func testPruneSessionDeletesSliceReleasesNumberAndRemovesLabel() {
		let sliceURL = dir.appendingPathComponent("claude_code:s1.json")
		try! Data("{\"activity_state\":\"idle\"}".utf8).write(to: sliceURL)
		SessionLabelStore.setLabel("My Session", for: "claude_code:s1", at: labelsFile.path)

		let allocator = SessionNumberAllocator()
		let assignedNumber = allocator.assign(origin: "claude_code", sessionId: "s1")
		XCTAssertEqual(assignedNumber, 1)

		SessionPruner.pruneSession(
			windowKey: "claude_code:s1",
			origin: "claude_code",
			sessionId: "s1",
			stateDirectory: dir.path,
			allocator: allocator,
			labelPath: labelsFile.path
		)

		XCTAssertFalse(
			FileManager.default.fileExists(atPath: sliceURL.path), "the slice file must be deleted")
		XCTAssertNil(
			SessionLabelStore.label(for: "claude_code:s1", at: labelsFile.path),
			"the label key must be removed")

		// Released number must be reusable by the next session on the same origin —
		// proof the release actually reached the free list, not just a forgotten entry.
		let reassigned = allocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(reassigned, 1, "a released number must be the lowest free number for the next session")
	}

	func testPruneSessionIsSafeWhenSliceAndLabelNeverExisted() {
		let allocator = SessionNumberAllocator()

		SessionPruner.pruneSession(
			windowKey: "claude_code:ghost",
			origin: "claude_code",
			sessionId: "ghost",
			stateDirectory: dir.path,
			allocator: allocator,
			labelPath: labelsFile.path
		)

		// No crash, and a subsequent real session still numbers from 1 — proves
		// the no-op release did not corrupt allocator state.
		XCTAssertEqual(allocator.assign(origin: "claude_code", sessionId: "real"), 1)
	}

	func testPruneSessionDoesNotAffectASiblingSessionsSliceOrLabel() {
		let siblingSlice = dir.appendingPathComponent("claude_code:s2.json")
		try! Data("{\"activity_state\":\"implementing\"}".utf8).write(to: siblingSlice)
		SessionLabelStore.setLabel("Sibling", for: "claude_code:s2", at: labelsFile.path)
		let targetSlice = dir.appendingPathComponent("claude_code:s1.json")
		try! Data("{\"activity_state\":\"idle\"}".utf8).write(to: targetSlice)

		let allocator = SessionNumberAllocator()
		allocator.assign(origin: "claude_code", sessionId: "s1")
		allocator.assign(origin: "claude_code", sessionId: "s2")

		SessionPruner.pruneSession(
			windowKey: "claude_code:s1",
			origin: "claude_code",
			sessionId: "s1",
			stateDirectory: dir.path,
			allocator: allocator,
			labelPath: labelsFile.path
		)

		XCTAssertTrue(FileManager.default.fileExists(atPath: siblingSlice.path))
		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:s2", at: labelsFile.path), "Sibling")
		// Sibling's number must stay stable — pruning s1 must not renumber s2.
		XCTAssertEqual(allocator.assign(origin: "claude_code", sessionId: "s2"), 2)
	}
}

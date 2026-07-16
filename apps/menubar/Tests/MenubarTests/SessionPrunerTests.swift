import XCTest

@testable import Codogotchi

/// P15.07 / P21.04: SessionPruner is disk-only (slice + label + retrieved
/// title). Session-number release lives in PoolMemory / SessionNumberAllocatorState.
final class SessionPrunerTests: XCTestCase {
	private var dir: URL!
	private var labelsFile: URL!
	private var retrievedTitlesFile: URL!

	override func setUp() {
		super.setUp()
		dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("SessionPrunerTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		labelsFile = dir.appendingPathComponent("session-labels.json")
		retrievedTitlesFile = dir.appendingPathComponent("retrieved-session-labels.json")
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: dir)
		super.tearDown()
	}

	func testPruneSessionDeletesSliceAndRemovesLabelAndRetrievedTitle() {
		let sliceURL = dir.appendingPathComponent("claude_code:s1.json")
		try! Data("{\"activity_state\":\"idle\"}".utf8).write(to: sliceURL)
		SessionLabelStore.setLabel("My Session", for: "claude_code:s1", at: labelsFile.path)
		RetrievedSessionTitleStore.setTitle("Fetched title", for: "claude_code:s1", at: retrievedTitlesFile.path)

		SessionPruner.pruneSession(
			windowKey: "claude_code:s1",
			origin: "claude_code",
			sessionId: "s1",
			stateDirectory: dir.path,
			labelPath: labelsFile.path,
			retrievedTitlePath: retrievedTitlesFile.path
		)

		XCTAssertFalse(
			FileManager.default.fileExists(atPath: sliceURL.path), "the slice file must be deleted")
		XCTAssertNil(
			SessionLabelStore.label(for: "claude_code:s1", at: labelsFile.path),
			"the label key must be removed")
		XCTAssertNil(
			RetrievedSessionTitleStore.title(for: "claude_code:s1", at: retrievedTitlesFile.path),
			"the cached retrieved-title key must be removed")
	}

	func testPruneSessionIsSafeWhenSliceLabelAndRetrievedTitleNeverExisted() {
		SessionPruner.pruneSession(
			windowKey: "claude_code:ghost",
			origin: "claude_code",
			sessionId: "ghost",
			stateDirectory: dir.path,
			labelPath: labelsFile.path,
			retrievedTitlePath: retrievedTitlesFile.path
		)

		XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("claude_code:ghost.json").path))
	}

	func testPruneSessionDoesNotAffectASiblingSessionsSliceLabelOrRetrievedTitle() {
		let siblingSlice = dir.appendingPathComponent("claude_code:s2.json")
		try! Data("{\"activity_state\":\"implementing\"}".utf8).write(to: siblingSlice)
		SessionLabelStore.setLabel("Sibling", for: "claude_code:s2", at: labelsFile.path)
		RetrievedSessionTitleStore.setTitle("Sibling title", for: "claude_code:s2", at: retrievedTitlesFile.path)
		let targetSlice = dir.appendingPathComponent("claude_code:s1.json")
		try! Data("{\"activity_state\":\"idle\"}".utf8).write(to: targetSlice)

		SessionPruner.pruneSession(
			windowKey: "claude_code:s1",
			origin: "claude_code",
			sessionId: "s1",
			stateDirectory: dir.path,
			labelPath: labelsFile.path,
			retrievedTitlePath: retrievedTitlesFile.path
		)

		XCTAssertTrue(FileManager.default.fileExists(atPath: siblingSlice.path))
		XCTAssertEqual(SessionLabelStore.label(for: "claude_code:s2", at: labelsFile.path), "Sibling")
		XCTAssertEqual(
			RetrievedSessionTitleStore.title(for: "claude_code:s2", at: retrievedTitlesFile.path),
			"Sibling title")
	}

	// MARK: - app-state.json floating_pet_positions/floating_pet_hidden cleanup

	/// P13/P15 QC: pruneSession must also remove the pruned window's entries
	/// from app-state.json's floating_pet_positions/floating_pet_hidden maps,
	/// or they accumulate forever for sessions that no longer exist.
	func testPruneSessionRemovesAppStatePositionAndHiddenEntries() throws {
		let appStateHome = FileManager.default.temporaryDirectory
			.appendingPathComponent("SessionPrunerTests-appstate-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: appStateHome, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: appStateHome) }
		let prevHome = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", appStateHome.path, 1)
		defer {
			if let prevHome { setenv("CODOGOTCHI_HOME", prevHome, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}

		try AppStateStore.saveFrame(
			CGRect(x: 100, y: 200, width: 160, height: 160),
			for: .session(origin: "claude_code", id: "s1"))
		try AppStateStore.saveHiddenWindowKeys([.session(origin: "claude_code", id: "s1")])

		SessionPruner.pruneSession(
			windowKey: "claude_code:s1",
			origin: "claude_code",
			sessionId: "s1",
			stateDirectory: dir.path,
			labelPath: labelsFile.path,
			retrievedTitlePath: retrievedTitlesFile.path
		)

		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
		XCTAssertEqual(
			AppStateStore.loadFrame(for: .session(origin: "claude_code", id: "s1"), visibleFrame: visibleFrame),
			FloatingFramePolicy.defaultFrame(in: visibleFrame),
			"the pruned session's saved position must be gone, not just fall back on read")
		XCTAssertEqual(AppStateStore.loadHiddenWindowKeys(), [])
	}
}

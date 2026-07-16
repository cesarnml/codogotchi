import XCTest

@testable import Codogotchi

/// P20.03: Settings > Sessions "Started" subtitle.
///
/// Two contracts under test:
/// 1. `SessionsTabViewModel.refresh()` threads each slice's `session_started_at`
///    stamp (when the hook wrote one) into its `SessionRow`, independent of
///    which lifecycle tier the row lands in — the stamp read happens once per
///    candidate slice, before tiering branches.
/// 2. `SessionRowView.subtitleText(for:now:)` renders the relative Started
///    fragment (`Started 2h ago`) combined onto the tier's existing status
///    text as one line when the stamp is present and parseable, and omits it
///    entirely — never fabricated from `updated_at` — when the stamp is
///    missing or unparseable.
final class SessionsTabViewModelTests: XCTestCase {

	// MARK: - refresh() threading (Live/Archived — pool-free tiers)
	//
	// Active-tier classification requires a `FloatingPetWindowPool` wired to a
	// rendered/hidden window, which needs a full `FloatingPetWindowControlling`
	// stub (see `MenuItemsTests.StubWindow`). The stamp-read this ticket adds
	// runs once per candidate slice ahead of the tier switch — identically for
	// Active, Live, and Archived — so the Live/Archived coverage here plus the
	// exhaustive per-tier `subtitleText` contract tests below give equivalent
	// confidence without duplicating that heavyweight stub.

	private func writeSlice(named name: String, in dir: String, age: TimeInterval, json: String) throws {
		let path = (dir as NSString).appendingPathComponent(name)
		try json.write(toFile: path, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: path)
	}

	private func makeTempStateDir() throws -> String {
		let dir = NSTemporaryDirectory() + "sessions-vm-tests-" + UUID().uuidString
		try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
		return dir
	}

	@MainActor
	func testRefreshThreadsSessionStartedAtIntoLiveRow() throws {
		let dir = try makeTempStateDir()
		try writeSlice(
			named: "codex:live-one.json", in: dir, age: 60,
			json: #"{"schema_version": 10, "session_started_at": "2026-07-14T09:00:00.000Z"}"#)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir)
		viewModel.refresh()

		let row = try XCTUnwrap(viewModel.liveRows.first)
		XCTAssertEqual(row.sessionStartedAt, "2026-07-14T09:00:00.000Z")
	}

	@MainActor
	func testRefreshThreadsSessionStartedAtIntoArchivedRow() throws {
		let dir = try makeTempStateDir()
		try writeSlice(
			named: "codex:archived-one.json", in: dir, age: 3 * 60 * 60,
			json: #"{"schema_version": 10, "session_started_at": "2026-07-14T05:00:00.000Z"}"#)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir)
		viewModel.refresh()

		let row = try XCTUnwrap(viewModel.archivedRows.first)
		XCTAssertEqual(row.sessionStartedAt, "2026-07-14T05:00:00.000Z")
	}

	@MainActor
	func testRefreshOmitsSessionStartedAtWhenSliceLacksStamp() throws {
		let dir = try makeTempStateDir()
		try writeSlice(named: "codex:unstamped.json", in: dir, age: 60, json: #"{"schema_version": 6}"#)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir)
		viewModel.refresh()

		let row = try XCTUnwrap(viewModel.liveRows.first)
		XCTAssertNil(row.sessionStartedAt)
	}

	@MainActor
	func testRefreshOmitsSessionStartedAtWhenSliceIsPreV10() throws {
		// Pre-v10 (unstamped) slices never carry the field at all — the same
		// omit contract as a v10 slice the hook didn't stamp, never a
		// fabricated value derived from `updated_at`.
		let dir = try makeTempStateDir()
		try writeSlice(
			named: "claude_code:legacy.json", in: dir, age: 3 * 60 * 60,
			json: #"{"schema_version": 6, "updated_at": "2026-07-14T05:00:00.000Z"}"#)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir)
		viewModel.refresh()

		let row = try XCTUnwrap(viewModel.archivedRows.first)
		XCTAssertNil(row.sessionStartedAt)
	}

	// MARK: - SessionRowView.subtitleText formatting contract (all three tiers)

	private func makeRow(
		tier: SessionTier, isShown: Bool = true, ageSeconds: TimeInterval = 300,
		sessionStartedAt: String? = nil
	) -> SessionRow {
		SessionRow(
			id: "codex", origin: "codex", sessionId: nil, displayLabel: "Codex",
			tier: tier, isShown: isShown, ageSeconds: ageSeconds, canShow: true,
			sessionStartedAt: sessionStartedAt)
	}

	private func isoString(_ now: Date, before seconds: TimeInterval) -> String {
		ISO8601DateFormatter().string(from: now.addingTimeInterval(-seconds))
	}

	// MARK: Absent stamp — every tier renders exactly as it did before P20.03

	func testSubtitleOmitsStartedOnActiveWhenStampMissing() {
		XCTAssertEqual(
			SessionRowView.subtitleText(for: makeRow(tier: .active, isShown: true)), "Shown")
		XCTAssertEqual(
			SessionRowView.subtitleText(for: makeRow(tier: .active, isShown: false)), "Hidden")
	}

	func testSubtitleOmitsStartedOnLiveWhenStampMissing() {
		XCTAssertEqual(
			SessionRowView.subtitleText(for: makeRow(tier: .live, ageSeconds: 300)), "Idle 5m ago")
	}

	func testSubtitleOmitsStartedOnArchivedWhenStampMissing() {
		XCTAssertEqual(
			SessionRowView.subtitleText(for: makeRow(tier: .archived, ageSeconds: 7200)),
			"Quiet 2h ago")
	}

	// MARK: Present stamp — relative Started fragment combines onto one line

	func testSubtitleCombinesStartedOntoActiveShown() {
		let now = Date()
		let row = makeRow(
			tier: .active, isShown: true, sessionStartedAt: isoString(now, before: 2 * 60 * 60))
		XCTAssertEqual(SessionRowView.subtitleText(for: row, now: now), "Shown · Started 2h ago")
	}

	func testSubtitleCombinesStartedOntoActiveHidden() {
		let now = Date()
		let row = makeRow(
			tier: .active, isShown: false, sessionStartedAt: isoString(now, before: 45 * 60))
		XCTAssertEqual(SessionRowView.subtitleText(for: row, now: now), "Hidden · Started 45m ago")
	}

	func testSubtitleCombinesStartedWithIdleAgeOnLive() {
		let now = Date()
		let row = makeRow(
			tier: .live, ageSeconds: 300, sessionStartedAt: isoString(now, before: 3 * 60 * 60))
		XCTAssertEqual(
			SessionRowView.subtitleText(for: row, now: now), "Idle 5m ago · Started 3h ago")
	}

	func testSubtitleCombinesStartedWithQuietAgeOnArchived() {
		let now = Date()
		let row = makeRow(
			tier: .archived, ageSeconds: 7200, sessionStartedAt: isoString(now, before: 25 * 60 * 60))
		XCTAssertEqual(
			SessionRowView.subtitleText(for: row, now: now), "Quiet 2h ago · Started 1d ago")
	}

	// MARK: Unparseable stamp — treated the same as missing, never crashes

	func testSubtitleOmitsStartedWhenStampIsUnparseable() {
		let row = makeRow(tier: .live, ageSeconds: 300, sessionStartedAt: "not-a-date")
		XCTAssertEqual(SessionRowView.subtitleText(for: row), "Idle 5m ago")
	}
}

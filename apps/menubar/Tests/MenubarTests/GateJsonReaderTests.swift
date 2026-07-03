import XCTest

@testable import Codogotchi

/// Behavior contract for `GateJsonReader` and `resolveActivityState` merge resolver.
///
/// All gate.json fixtures are created as tmp files so the tests run cleanly
/// without requiring bundled fixtures.
final class GateJsonReaderTests: XCTestCase {

	// MARK: - GateJsonReader

	func testGateJsonDecodesFull() throws {
		// [red] GateJsonReader must decode all expected fields
		let json = """
			{
			  "gate": "ticket_started",
			  "since": "2026-05-29T12:00:00.000Z",
			  "expires_at": "2099-01-01T00:00:00.000Z",
			  "plan_key": "phase-07",
			  "ticket_id": "P7.01"
			}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNotNil(snapshot, "full gate.json must decode successfully")
		XCTAssertEqual(snapshot?.gate, "ticket_started")
		XCTAssertEqual(snapshot?.planKey, "phase-07")
		XCTAssertEqual(snapshot?.ticketId, "P7.01")
	}

	func testGateJsonMissingFileReturnsNil() {
		// [red] missing gate.json → nil (not an error)
		let snapshot = GateJsonReader.read(at: "/tmp/codogotchi-nonexistent-gate.json")
		XCTAssertNil(snapshot, "missing gate.json must return nil")
	}

	func testGateJsonMalformedReturnsNil() throws {
		// [red] malformed JSON → nil (best-effort, never throws)
		let tmp = writeTemp("{ not json")
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "malformed gate.json must return nil")
	}

	func testGateJsonMissingGateFieldReturnsNil() throws {
		let json = """
			{"since": "2026-05-29T12:00:00.000Z", "expires_at": "2099-01-01T00:00:00.000Z"}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "gate.json missing required 'gate' field must return nil")
	}

	func testGateJsonMissingExpiresAtFieldReturnsNil() throws {
		let json = """
			{"gate": "ticket_started", "since": "2026-05-29T12:00:00.000Z"}
			"""
		let tmp = writeTemp(json)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = GateJsonReader.read(at: tmp.path)
		XCTAssertNil(snapshot, "gate.json missing required 'expires_at' field must return nil")
	}

	func testUnparseableExpiresAtTreatedAsExpired() {
		// Corrupt expires_at must not activate the gate indefinitely
		let gate = makeGate(gate: "ticket_started", expiresAt: "not-a-date")
		let result = resolveActivityState(gate: gate, hookState: .implementing, now: Date())
		XCTAssertEqual(result, .implementing, "unparseable expires_at must fall through to hook state (treated as expired)")
	}

	// MARK: - resolveActivityState merge resolver

	func testUnexpiredGateWithRowRendersGateState() {
		// [red] unexpired gate with a sprite row → gate state wins over hook state
		let gate = makeGate(gate: "ticket_started", expiresAt: futureDate())
		let hookState = ActivityState.implementing
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .ticketStarted, "unexpired ticket_started gate with a row must render ticketStarted")
	}

	func testExpiredGateRendersHookState() {
		// [red] expired gate → fall through to hook state.json activity_state
		let gate = makeGate(gate: "ticket_started", expiresAt: pastDate())
		let hookState = ActivityState.implementing
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .implementing, "expired gate must fall through to hook state")
	}

	func testUnexpiredGateWithUnknownStateRendersHookState() {
		// [red] unexpired gate with an unknown/unmapped state → fall through (skew or artless)
		let gate = makeGate(gate: "some_unknown_gate_state", expiresAt: futureDate())
		let hookState = ActivityState.thinking
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .thinking, "gate with unknown state must fall through to hook state")
	}

	func testUnexpiredGateWithHookStateAsGateRendersHookState() {
		// A gate that fires a hook/lite state (not in soaRowMap) falls through —
		// the gate contract only elevates SoA gate states.
		let gate = makeGate(gate: "implementing", expiresAt: futureDate())
		let hookState = ActivityState.idle
		let result = resolveActivityState(gate: gate, hookState: hookState, now: Date())
		XCTAssertEqual(result, .idle, "gate with a hook state (not in soaRowMap) must fall through")
	}

	func testUnexpiredGateWithAdvanceRendersAdvanceState() {
		// P8.06: .advance is now in soaRowMap — unexpired gate must render as .advance.
		let gate = makeGate(gate: "advance", expiresAt: futureDate())
		let result = resolveActivityState(gate: gate, hookState: .idle, now: Date())
		XCTAssertEqual(result, .advance, "advance is in soaRowMap — unexpired gate renders as .advance")
	}

	func testUnexpiredGateWithSoaSheetAbsentFallsThroughToHookState() throws {
		// When codogotchiPet is present but has no SoA sheet, gate must NOT elevate —
		// falling to idle instead of hook animation violated the Phase 07 contract.
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("no-soa-sheet-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		let pet = try CodogotchiPet(petDirectory: tmp.path)
		XCTAssertNil(pet.soaSheet, "fixture must have no SoA sheet for this test to be meaningful")

		let gate = makeGate(gate: "ticket_started", expiresAt: futureDate())
		let hookState = ActivityState.implementing
		let result = resolveActivityState(gate: gate, hookState: hookState, codogotchiPet: pet, now: Date())
		XCTAssertEqual(
			result, .implementing,
			"gate must fall through to hook state when SoA sheet is absent")
	}

	func testAbsentGateRendersHookState() {
		// [red] absent gate.json → hook state only
		let hookState = ActivityState.errored
		let result = resolveActivityState(gate: nil, hookState: hookState, now: Date())
		XCTAssertEqual(result, .errored, "absent gate must render hook state unchanged")
	}

	// MARK: - resolveReviveState (v6 revive override)

	func testFutureReviveUntilOverridesToRevive() {
		let result = resolveReviveState(
			base: .implementing, reviveUntil: futureDate(), now: Date())
		XCTAssertEqual(result, .revive, "active revive window must render the dedicated revive row")
	}

	func testFutureReviveUntilWholeSecondsFormOverrides() {
		// Whole-seconds ISO 8601 (no fractional millis) must also parse.
		let result = resolveReviveState(
			base: .idle, reviveUntil: "2099-01-01T00:00:00Z", now: Date())
		XCTAssertEqual(result, .revive, "whole-seconds revive_until must parse and override")
	}

	func testExpiredReviveUntilRendersBaseState() {
		let result = resolveReviveState(
			base: .implementing, reviveUntil: pastDate(), now: Date())
		XCTAssertEqual(result, .implementing, "lapsed revive window must fall through to the base state")
	}

	func testNilReviveUntilRendersBaseState() {
		let result = resolveReviveState(base: .thinking, reviveUntil: nil, now: Date())
		XCTAssertEqual(result, .thinking, "absent revive_until must leave the base state unchanged")
	}

	func testUnparseableReviveUntilRendersBaseState() {
		let result = resolveReviveState(base: .editing, reviveUntil: "not-a-date", now: Date())
		XCTAssertEqual(result, .editing, "unparseable revive_until must not override")
	}

	func testReviveWithLiteBasicSheetAbsentDoesNotOverride() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("no-lite-basic-sheet-revive-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let petJson = """
			{"id":"test","display_name":"Test","description":"","spritesheet_path":"spritesheet.webp"}
			"""
		try petJson.data(using: .utf8)!.write(to: tmp.appendingPathComponent("pet.json"))

		let pet = try CodogotchiPet(petDirectory: tmp.path)
		XCTAssertNil(
			pet.liteBasicSheet, "fixture must have no Lite-Basic sheet for this test to be meaningful")

		let result = resolveReviveState(
			base: .implementing, reviveUntil: futureDate(), codogotchiPet: pet, now: Date())
		XCTAssertEqual(
			result, .implementing,
			"revive must not override when the Lite-Basic revive row is absent")
	}

	// MARK: - Persistent gate badge

	func testGateWithoutTicketIdDoesNotProducePartialBadge() {
		let context = makeDeliveryContext(ticketId: nil)
		XCTAssertNil(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: nil),
			"badge widget requires both the ticket_id and gate pills; partial gate payloads must not render half a badge"
		)
	}

	func testActiveDeliveryContextProducesBadgeContent() {
		let context = makeDeliveryContext()
		let badge = resolveGateBadgeContent(deliveryContext: context, sourceEvent: nil)
		XCTAssertEqual(
			badge,
			GateBadgeContent(ticketId: "P7.01", gate: "review_clean"),
			"active delivery context owns the persistent badge lane"
		)
	}

	func testClearedDeliveryContextProducesNoBadge() {
		let context = makeDeliveryContext(status: "cleared")
		XCTAssertNil(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: nil),
			"cleared delivery context must remove stale SoA badges"
		)
	}

	func testExpiredDeliveryContextLeaseProducesNoBadge() {
		let context = makeDeliveryContext(leaseExpiresAt: pastDate())
		XCTAssertNil(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: nil),
			"delivery context lease expiry clears stranded badge state"
		)
	}

	func testDifferentHookRepoSuppressesDeliveryContextBadge() {
		let context = makeDeliveryContext(repoRoot: "/repo/soa")
		let sourceEvent = SourceEvent(
			origin: "codex",
			kind: "tool_use",
			name: "Bash",
			repoRoot: "/repo/non-soa"
		)
		XCTAssertNil(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: sourceEvent),
			"newer hook activity from another repo must suppress stale SoA context"
		)
	}

	func testSameHookRepoKeepsDeliveryContextBadge() {
		let context = makeDeliveryContext(repoRoot: "/repo/soa")
		let sourceEvent = SourceEvent(
			origin: "codex",
			kind: "tool_use",
			name: "Bash",
			repoRoot: "/repo/soa"
		)
		XCTAssertEqual(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: sourceEvent),
			GateBadgeContent(ticketId: "P7.01", gate: "review_clean"),
			"same-repo hook activity may continue showing the active SoA context"
		)
	}

	func testWorktreeContextMatchesPrimaryCheckoutHookRepo() throws {
		// The real-world SoA case: delivery runs in a linked worktree while the
		// operator's editor hook reports the primary checkout. Both must resolve
		// to the same repo so the badge persists across the worktree boundary.
		let (mainRoot, worktreeRoot) = makeWorktreePair()
		defer {
			try? FileManager.default.removeItem(atPath: mainRoot)
			try? FileManager.default.removeItem(atPath: worktreeRoot)
		}
		let context = makeDeliveryContext(repoRoot: worktreeRoot)
		let sourceEvent = SourceEvent(
			origin: "claude_code",
			kind: "tool_use",
			name: "Bash",
			repoRoot: mainRoot
		)
		XCTAssertEqual(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: sourceEvent),
			GateBadgeContent(ticketId: "P7.01", gate: "review_clean"),
			"a worktree delivery context and a primary-checkout hook are the same repo"
		)
	}

	func testCanonicalRepoRootResolvesWorktreeToMainRoot() throws {
		let (mainRoot, worktreeRoot) = makeWorktreePair()
		defer {
			try? FileManager.default.removeItem(atPath: mainRoot)
			try? FileManager.default.removeItem(atPath: worktreeRoot)
		}
		XCTAssertEqual(
			canonicalRepoRoot(worktreeRoot), mainRoot,
			"a linked worktree must resolve to its main checkout root")
		XCTAssertEqual(
			canonicalRepoRoot(mainRoot), mainRoot,
			"a primary checkout must resolve to itself")
	}

	func testCanonicalRepoRootLeavesUnknownPathsUnchanged() {
		let bogus = "/tmp/codogotchi-not-a-repo-\(UUID().uuidString)"
		XCTAssertEqual(
			canonicalRepoRoot(bogus), bogus,
			"a path with no .git must be returned unchanged so the guard degrades safely")
	}

	func testDifferentReposStillSuppressedAfterCanonicalization() throws {
		// Two independent primary checkouts must still be treated as different
		// projects — canonicalization must not collapse unrelated repos.
		let (mainRootA, worktreeRootA) = makeWorktreePair()
		let (mainRootB, _) = makeWorktreePair()
		defer {
			try? FileManager.default.removeItem(atPath: mainRootA)
			try? FileManager.default.removeItem(atPath: worktreeRootA)
			try? FileManager.default.removeItem(atPath: mainRootB)
		}
		let context = makeDeliveryContext(repoRoot: worktreeRootA)
		let sourceEvent = SourceEvent(
			origin: "claude_code",
			kind: "tool_use",
			name: "Bash",
			repoRoot: mainRootB
		)
		XCTAssertNil(
			resolveGateBadgeContent(deliveryContext: context, sourceEvent: sourceEvent),
			"a worktree of repo A must not match an unrelated repo B")
	}

	// MARK: - PerPlatformGateReader (Phase 15 session-pets)

	/// `PerPlatformGateReader.read()` must keep same-origin sessions distinct
	/// so any render key — session-pets on or off — can badge from the exact
	/// session whose state it renders, never a sibling's.
	func testPerSessionGateReaderKeepsSameOriginSessionsDistinct() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-gate-reader-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		try """
			{"gate":"red_tdd","since":"2026-06-28T09:59:00.000Z","expires_at":"2099-01-01T00:00:00.000Z","plan_key":"phase-15","ticket_id":"P15.10"}
			""".write(
				to: dir.appendingPathComponent("claude_code:s1.gate.json"), atomically: true,
				encoding: .utf8)
		try """
			{"gate":"open_pr","since":"2026-06-28T10:00:01.000Z","expires_at":"2099-01-01T00:00:00.000Z","plan_key":"phase-15","ticket_id":"P15.11"}
			""".write(
				to: dir.appendingPathComponent("claude_code:s2.gate.json"), atomically: true,
				encoding: .utf8)

		let sessions = PerPlatformGateReader.read(at: dir.path)

		XCTAssertEqual(
			sessions["claude_code:s1"]?.gate?.ticketId, "P15.10",
			"session s1's own gate must survive independent of s2")
		XCTAssertEqual(
			sessions["claude_code:s2"]?.gate?.ticketId, "P15.11",
			"session s2's own gate must survive independent of s1")
	}

	// MARK: - Helpers

	/// Creates a primary-checkout directory (with a `.git` *directory*) and a
	/// sibling linked-worktree directory (with a `.git` *file* pointing back at
	/// the primary's `.git/worktrees/<name>`), mirroring real git layout.
	/// Returns `(mainRoot, worktreeRoot)` absolute paths.
	private func makeWorktreePair() -> (mainRoot: String, worktreeRoot: String) {
		let fm = FileManager.default
		let base = fm.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString)")
		let mainRoot = base.appendingPathComponent("codogotchi")
		let worktreeName = "codogotchi_wt"
		let worktreeRoot = base.appendingPathComponent(worktreeName)
		let gitDir = mainRoot.appendingPathComponent(".git")
		let worktreeMeta = gitDir.appendingPathComponent("worktrees/\(worktreeName)")
		try? fm.createDirectory(at: worktreeMeta, withIntermediateDirectories: true)
		try? fm.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
		let gitFile = worktreeRoot.appendingPathComponent(".git")
		try? "gitdir: \(worktreeMeta.path)\n".write(
			to: gitFile, atomically: true, encoding: .utf8)
		return (mainRoot.path, worktreeRoot.path)
	}

	private func writeTemp(_ content: String) -> URL {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("gate-\(UUID().uuidString).json")
		try? content.write(to: tmp, atomically: true, encoding: .utf8)
		return tmp
	}

	private func futureDate() -> String {
		"2099-01-01T00:00:00.000Z"
	}

	private func pastDate() -> String {
		"2020-01-01T00:00:00.000Z"
	}

	private func makeGate(gate: String, expiresAt: String) -> GateSnapshot {
		GateSnapshot(
			gate: gate,
			since: "2026-05-29T12:00:00.000Z",
			expiresAt: expiresAt,
			planKey: "phase-07",
			ticketId: "P7.01"
		)
	}

	private func makeDeliveryContext(
		status: String = "active",
		repoRoot: String? = "/repo/soa",
		ticketId: String? = "P7.01",
		lastGate: String? = "review_clean",
		leaseExpiresAt: String? = "2099-01-01T00:00:00.000Z"
	) -> DeliveryContextSnapshot {
		DeliveryContextSnapshot(
			owner: "soa",
			status: status,
			repoRoot: repoRoot,
			planKey: "phase-07",
			ticketId: ticketId,
			lastGate: lastGate,
			updatedAt: "2026-05-29T12:00:00.000Z",
			leaseExpiresAt: leaseExpiresAt
		)
	}
}

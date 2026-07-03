import XCTest

@testable import Codogotchi

/// P15.07 behavior contract for the pure per-origin cap/eviction partition.
/// `SessionSelectionPolicy.select` takes a `[windowKey → ActivityState]` map
/// and a cap; it is exercised directly here with no pool/window state so
/// eviction priority is locked independent of window-spawn machinery.
final class SessionSelectionPolicyTests: XCTestCase {

	// MARK: - (1) Cap holds the most-evictable session

	func testCapTwoWithIdleAndTwoActiveHoldsTheIdleSession() {
		let sessions: [String: ActivityState] = [
			"claude_code:idle-one": .idle,
			"claude_code:active-one": .implementing,
			"claude_code:active-two": .thinking,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 2)

		XCTAssertEqual(
			selection.pending, ["claude_code:idle-one"],
			"the idle session must be the one held back")
		XCTAssertEqual(
			selection.rendered, ["claude_code:active-one", "claude_code:active-two"],
			"both active sessions must render")
		XCTAssertFalse(
			selection.blocked, "holding an idle session is ordinary eviction, not a blocked signal")
	}

	// MARK: - (2) All-active cap pressure blocks without evicting

	func testCapTwoWithThreeActiveSessionsEmitsBlockedSignalWithoutEvicting() {
		let sessions: [String: ActivityState] = [
			"claude_code:a": .implementing,
			"claude_code:b": .thinking,
			"claude_code:c": .editing,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 2)

		XCTAssertEqual(selection.rendered.count, 2, "exactly two of the three active sessions must render")
		XCTAssertEqual(selection.pending.count, 1, "the third active session is held, not evicted from disk")
		XCTAssertTrue(
			Set(sessions.keys).isSuperset(of: selection.rendered.union(selection.pending)),
			"partition must never invent or drop a session key")
		XCTAssertTrue(
			selection.blocked,
			"a newcomer active session blocked by cap pressure with no evictable target must signal blocked")
	}

	// MARK: - (4) Eviction priority ordering

	func testEvictionRankOrdersIdleStandbyBelowErroredBelowWaitingBelowActive() {
		XCTAssertEqual(SessionSelectionPolicy.evictionRank(for: .idle), 0)
		XCTAssertEqual(SessionSelectionPolicy.evictionRank(for: .standby), 0)
		XCTAssertEqual(
			SessionSelectionPolicy.evictionRank(for: .idle),
			SessionSelectionPolicy.evictionRank(for: .standby),
			"idle and standby are equally evictable (both 'at rest')")
		XCTAssertLessThan(
			SessionSelectionPolicy.evictionRank(for: .idle),
			SessionSelectionPolicy.evictionRank(for: .errored),
			"idle/standby must be more evictable than errored")
		XCTAssertLessThan(
			SessionSelectionPolicy.evictionRank(for: .errored),
			SessionSelectionPolicy.evictionRank(for: .waitingForInput),
			"errored must be more evictable than waiting_for_input — a live approval gate must not be yielded before an idle/errored session")
		XCTAssertLessThan(
			SessionSelectionPolicy.evictionRank(for: .waitingForInput),
			SessionSelectionPolicy.evictionRank(for: .implementing),
			"waiting_for_input must be more evictable than any in-flight active state")
		XCTAssertEqual(
			SessionSelectionPolicy.evictionRank(for: .implementing),
			SessionSelectionPolicy.evictionRank(for: .thinking),
			"every in-flight state shares the top (never-evicted) rank")
	}

	func testFourDistinctRanksPartitionAgainstCapInPriorityOrder() {
		// One session per distinct rank; cap 3 must hold exactly the single
		// most-evictable (idle) session and render the other three.
		let sessions: [String: ActivityState] = [
			"o:idle": .idle,
			"o:errored": .errored,
			"o:waiting": .waitingForInput,
			"o:active": .implementing,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 3)

		XCTAssertEqual(selection.pending, ["o:idle"])
		XCTAssertEqual(selection.rendered, ["o:errored", "o:waiting", "o:active"])
	}

	// MARK: - (5) Unlimited cap

	func testUnlimitedCapNeverHoldsOrEvictsRegardlessOfSessionCount() {
		let sessions: [String: ActivityState] = [
			"o:a": .idle,
			"o:b": .idle,
			"o:c": .implementing,
			"o:d": .implementing,
			"o:e": .waitingForInput,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 0)

		XCTAssertEqual(selection.rendered, Set(sessions.keys), "Unlimited (cap 0) must render every session")
		XCTAssertTrue(selection.pending.isEmpty, "Unlimited must never hold a session pending")
		XCTAssertFalse(selection.blocked, "Unlimited must never emit a blocked signal")
	}

	// MARK: - Incumbent protection

	func testIncumbentActiveSessionIsNeverEvictedByANewcomerActiveSession() {
		let sessions: [String: ActivityState] = [
			"claude_code:incumbent-a": .implementing,
			"claude_code:incumbent-b": .thinking,
			"claude_code:newcomer": .editing,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 2,
			currentlyRendered: ["claude_code:incumbent-a", "claude_code:incumbent-b"])

		XCTAssertEqual(
			selection.rendered, ["claude_code:incumbent-a", "claude_code:incumbent-b"],
			"a newcomer active session must never bump an already-rendered active session")
		XCTAssertEqual(selection.pending, ["claude_code:newcomer"])
	}

	// MARK: - Prune-armed gate (P15.07-QC)

	func testArmedGateKeepsAFreedSlotEmptyWhenOnlyStandbyCandidateRemains() {
		// Pruning the active session drops the count to <= cap, so the
		// pre-QC guard clause would have auto-rendered the standby session.
		let sessions: [String: ActivityState] = [
			"claude_code:standby-one": .standby,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1, currentlyRendered: [],
			restrictNewPromotionsToInFlight: true)

		XCTAssertTrue(
			selection.rendered.isEmpty,
			"a non-in-flight session must not newly promote into a slot freed by a manual prune")
		XCTAssertEqual(selection.pending, ["claude_code:standby-one"])
	}

	func testArmedGatePromotesAnInFlightCandidateIntoAFreedSlot() {
		let sessions: [String: ActivityState] = [
			"claude_code:active-one": .implementing,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1, currentlyRendered: [],
			restrictNewPromotionsToInFlight: true)

		XCTAssertEqual(
			selection.rendered, ["claude_code:active-one"],
			"an in-flight candidate must still promote into a freed slot under the armed gate")
	}

	func testArmedGateNeverDemotesAnAlreadyRenderedIncumbent() {
		// An incumbent that later idles must stay rendered under the armed
		// gate — the gate only restricts NEW promotions, not incumbents.
		let sessions: [String: ActivityState] = [
			"claude_code:incumbent": .idle,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1, currentlyRendered: ["claude_code:incumbent"],
			restrictNewPromotionsToInFlight: true)

		XCTAssertEqual(
			selection.rendered, ["claude_code:incumbent"],
			"the armed gate must never evict an incumbent — only cap-pressure ranking does that")
	}

	func testArmedGateDefaultsToUnarmedPreservingPreQCBehavior() {
		let sessions: [String: ActivityState] = [
			"claude_code:standby-one": .standby,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1)

		XCTAssertEqual(
			selection.rendered, ["claude_code:standby-one"],
			"without an armed prune, a freed slot still auto-renders the sole remaining session")
	}

	// MARK: - Determinism

	func testEqualRankTiesBreakDeterministicallyByWindowKey() {
		let sessions: [String: ActivityState] = [
			"claude_code:zzz": .idle,
			"claude_code:aaa": .idle,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1)

		XCTAssertEqual(
			selection.rendered, ["claude_code:zzz"],
			"equal-rank ties must deterministically hold the lexicographically smallest key")
		XCTAssertEqual(selection.pending, ["claude_code:aaa"])
	}
}

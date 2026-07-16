import XCTest

@testable import Codogotchi

/// P15.07 behavior contract for the pure per-origin cap/eviction partition.
/// `SessionSelectionPolicy.select` takes a `[windowKey → ActivityState]` map
/// and a cap; it is exercised directly here with no pool/window state so
/// eviction priority is locked independent of window-spawn machinery.
final class SessionSelectionPolicyTests: XCTestCase {

	// MARK: - (1) Cap holds the most-evictable session

	func testCapTwoWithIdleAndTwoActiveHoldsTheIdleSession() {
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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

	// MARK: - "Evict Session Pets" kill-switch (incumbentsProtected)

	func testIncumbentsProtectedKeepsAnIdleIncumbentAliveAgainstAnInFlightNewcomer() {
		// The user's reported scenario: cap 2, one idle + one in-flight
		// incumbent, a 3rd in-flight thread starts. With incumbentsProtected,
		// the idle incumbent must NOT be evicted — the newcomer stays pending.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:idle-incumbent": .idle,
			"claude_code:active-incumbent": .implementing,
			"claude_code:newcomer": .thinking,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 2,
			currentlyRendered: ["claude_code:idle-incumbent", "claude_code:active-incumbent"],
			incumbentsProtected: true)

		XCTAssertEqual(
			selection.rendered, ["claude_code:idle-incumbent", "claude_code:active-incumbent"],
			"both incumbents must survive regardless of rank when incumbentsProtected is true")
		XCTAssertEqual(selection.pending, ["claude_code:newcomer"])
	}

	func testIncumbentsProtectedFillsAGenuinelyFreeSlotWithANewcomer() {
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:idle-incumbent": .idle,
			"claude_code:newcomer": .implementing,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 2,
			currentlyRendered: ["claude_code:idle-incumbent"],
			incumbentsProtected: true)

		XCTAssertEqual(
			selection.rendered, Set(sessions.keys),
			"a newcomer must still fill a slot that isn't already held by an incumbent")
		XCTAssertTrue(selection.pending.isEmpty)
	}

	func testIncumbentsProtectedDefaultsToFalsePreservingTodaysBehavior() {
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:idle-incumbent": .idle,
			"claude_code:active-incumbent": .implementing,
			"claude_code:newcomer": .thinking,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 2,
			currentlyRendered: ["claude_code:idle-incumbent", "claude_code:active-incumbent"])

		XCTAssertEqual(
			selection.rendered, ["claude_code:active-incumbent", "claude_code:newcomer"],
			"without incumbentsProtected, the idle incumbent is still evicted by the in-flight newcomer")
		XCTAssertEqual(selection.pending, ["claude_code:idle-incumbent"])
	}

	func testIncumbentsProtectedComposesWithArmedPruneGate() {
		// A freed slot (cap 1, no incumbents left) with incumbentsProtected on:
		// the armed gate still restricts a fresh non-in-flight promotion, since
		// incumbentsProtected only ever protects existing incumbents — it has
		// nothing to say about a slot with no incumbent at all.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:standby-one": .standby,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1, currentlyRendered: [],
			incumbentsProtected: true,
			restrictNewPromotionsToInFlight: true)

		XCTAssertTrue(
			selection.rendered.isEmpty,
			"incumbentsProtected must not bypass the prune-armed gate for a non-incumbent candidate")
		XCTAssertEqual(selection.pending, ["claude_code:standby-one"])
	}

	// MARK: - Prune-armed gate (P15.07-QC)

	func testArmedGateKeepsAFreedSlotEmptyWhenOnlyStandbyCandidateRemains() {
		// Pruning the active session drops the count to <= cap, so the
		// pre-QC guard clause would have auto-rendered the standby session.
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
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
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:standby-one": .standby,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1)

		XCTAssertEqual(
			selection.rendered, ["claude_code:standby-one"],
			"without an armed prune, a freed slot still auto-renders the sole remaining session")
	}

	// MARK: - Determinism

	func testEqualRankTiesBreakDeterministicallyByWindowKey() {
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:zzz": .idle,
			"claude_code:aaa": .idle,
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1)

		XCTAssertEqual(
			selection.rendered, ["claude_code:zzz"],
			"with no updatedAt data, equal-rank ties must deterministically hold the lexicographically smallest key")
		XCTAssertEqual(selection.pending, ["claude_code:aaa"])
	}

	// MARK: - Recency tie-break

	func testEqualRankTieBreaksByMostRecentUpdatedAtOverKeyOrder() {
		// "aaa" sorts first lexicographically, but "zzz" was updated more
		// recently — recency must win regardless of session-id ordering, e.g.
		// on a cold app relaunch where nothing is yet incumbent.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:aaa": .idle,
			"claude_code:zzz": .idle,
		]
		let updatedAt: [WindowKey: String] = [
			"claude_code:aaa": "2026-07-03T12:15:24.932Z",
			"claude_code:zzz": "2026-07-03T12:53:20.319Z",
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1, updatedAt: updatedAt)

		XCTAssertEqual(
			selection.rendered, ["claude_code:zzz"],
			"the more recently updated session must win the slot even though its key sorts later")
		XCTAssertEqual(selection.pending, ["claude_code:aaa"])
	}

	func testMissingOrUnparseableUpdatedAtSortsAsMostEvictable() {
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:known": .idle,
			"claude_code:unknown": .idle,
		]
		let updatedAt: [WindowKey: String] = [
			"claude_code:known": "2026-07-03T12:15:24.932Z"
			// "claude_code:unknown" intentionally absent.
		]

		let selection = SessionSelectionPolicy.select(sessions: sessions, cap: 1, updatedAt: updatedAt)

		XCTAssertEqual(
			selection.rendered, ["claude_code:known"],
			"a session with no updatedAt data must not out-rank one with a real timestamp")
		XCTAssertEqual(selection.pending, ["claude_code:unknown"])
	}

	func testRecencyTieBreakYieldsToIncumbency() {
		// The newcomer has a fresher timestamp, but the incumbent-protection
		// rule (checked first) must still win — recency only breaks ties among
		// equally-incumbent (or equally-newcomer) candidates.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:incumbent": .idle,
			"claude_code:newcomer": .idle,
		]
		let updatedAt: [WindowKey: String] = [
			"claude_code:incumbent": "2026-07-03T12:00:00.000Z",
			"claude_code:newcomer": "2026-07-03T12:59:00.000Z",
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1, currentlyRendered: ["claude_code:incumbent"],
			updatedAt: updatedAt)

		XCTAssertEqual(
			selection.rendered, ["claude_code:incumbent"],
			"incumbency must still be checked before recency")
	}

	// MARK: - Pinned (user-hidden) keys

	func testPinnedIdleIncumbentSurvivesAnInFlightNewcomerEvenWithEvictionEnabled() {
		// Eviction enabled (incumbentsProtected: false) would normally let the
		// in-flight newcomer bump the idle incumbent. Pinning — the user
		// explicitly hid this session to revisit it — must override rank.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:hidden-idle": .idle,
			"claude_code:newcomer": .implementing,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1,
			currentlyRendered: ["claude_code:hidden-idle"],
			incumbentsProtected: false,
			pinnedKeys: ["claude_code:hidden-idle"])

		XCTAssertEqual(
			selection.rendered, ["claude_code:hidden-idle"],
			"a pinned (user-hidden) incumbent must never lose its slot to passive cap eviction")
		XCTAssertEqual(selection.pending, ["claude_code:newcomer"])
		XCTAssertTrue(
			selection.blocked,
			"the held-back in-flight newcomer is a genuine conflict and must still signal blocked")
	}

	func testCapReductionStillTrimsPinnedKeys() {
		// Pinning protects against passive eviction, not against the user
		// deliberately lowering the cap below the pinned count.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:pinned-a": .idle,
			"claude_code:pinned-b": .idle,
		]
		let updatedAt: [WindowKey: String] = [
			"claude_code:pinned-a": "2026-07-03T12:00:00.000Z",
			"claude_code:pinned-b": "2026-07-03T12:30:00.000Z",
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1,
			currentlyRendered: ["claude_code:pinned-a", "claude_code:pinned-b"],
			updatedAt: updatedAt,
			pinnedKeys: ["claude_code:pinned-a", "claude_code:pinned-b"])

		XCTAssertEqual(
			selection.rendered, ["claude_code:pinned-b"],
			"cap 1 with two pinned keys must keep exactly one — the more recent")
		XCTAssertEqual(selection.pending, ["claude_code:pinned-a"])
	}

	func testPinnedIdleIncumbentYieldsToAFellowInFlightIncumbentOnCapReduction() {
		// Pinning protects against newcomers, not against fellow incumbents:
		// when the cap shrinks, the surviving slot must go to the visible
		// in-flight session — rendering the invisible (hidden) pinned one
		// instead would show the user nothing while their working pet vanished.
		let sessions: [WindowKey: ActivityState] = [
			"claude_code:pinned-idle": .idle,
			"claude_code:working": .implementing,
		]

		let selection = SessionSelectionPolicy.select(
			sessions: sessions, cap: 1,
			currentlyRendered: ["claude_code:pinned-idle", "claude_code:working"],
			pinnedKeys: ["claude_code:pinned-idle"])

		XCTAssertEqual(
			selection.rendered, ["claude_code:working"],
			"a fellow incumbent's higher rank must beat pinning when slots shrink")
		XCTAssertEqual(selection.pending, ["claude_code:pinned-idle"])
	}
}

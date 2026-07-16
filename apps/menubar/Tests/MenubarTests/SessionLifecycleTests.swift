import XCTest

@testable import Codogotchi

/// Pins `SessionLifecycle.classify` (P16.05) against the *current*
/// bucketing/tiering behavior read out of `SessionsTabViewModel.refresh()`
/// before this ticket's extraction: a slice's tier is decided by a fixed
/// precedence over three clock-derived signals — rendered-now, concealed
/// (hidden/pending-show/idle-dismissed) within the reader-staleness window,
/// and the reader-staleness/prune-horizon TTL comparisons themselves — with
/// no re-derivation once the pure classifier lands. Boundaries use strict
/// `<` throughout, matching every inline `age < ttl` comparison this ticket
/// replaces.
final class SessionLifecycleTests: XCTestCase {

	private let liveTTL: TimeInterval = 7200  // 2h "Archive Session After Idle"
	private let archiveTTL: TimeInterval = 86400  // 24h "Prune Archived Sessions"

	// MARK: - Rendered takes precedence over every other signal

	func testRenderedIsAlwaysActiveRegardlessOfAge() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: 0, isRendered: true, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .active)
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL, isRendered: true, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .active)
	}

	func testRenderedButPastPruneHorizonIsPruned() {
		// The `age < archiveTTL` filter runs before any rendered/concealed
		// check in the pre-existing `SessionsTabViewModel.refresh()` scan —
		// a stale slice is excluded even for a currently-rendered key.
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: archiveTTL, isRendered: true, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .pruned)
	}

	// MARK: - Concealed (hidden / pending-show / idle-dismissed)

	func testConcealedWithinLiveTTLIsActive() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL - 1, isRendered: false, isConcealed: true, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .active)
	}

	func testConcealedAtLiveTTLBoundaryIsArchived() {
		// Strict `<`: exactly-at-TTL fails the concealed-active check and
		// falls through to the plain age-vs-liveTTL comparison, which also
		// fails at the boundary, landing on `.archived` — this case is the
		// at-boundary side; `testConcealedWithinLiveTTLIsActive` covers the
		// still-under-TTL side one second earlier.
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL, isRendered: false, isConcealed: true, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .archived)
	}

	func testConcealedPastLiveTTLIsArchived() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL + 1, isRendered: false, isConcealed: true, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .archived)
	}

	// MARK: - Unrendered, unconcealed: plain reader-staleness comparison

	func testFreshUnconcealedIsLive() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: 0, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .live)
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL - 1, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .live)
	}

	func testExactlyAtLiveTTLBoundaryIsArchived() {
		// Strict `<` on the boundary: `age == liveTTL` fails `age < liveTTL`.
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .archived)
	}

	func testPastLiveTTLBeforePruneHorizonIsArchived() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: liveTTL + 1, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .archived)
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: archiveTTL - 1, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .archived)
	}

	// MARK: - Prune horizon boundary

	func testExactlyAtPruneHorizonIsPruned() {
		// Strict `<`: `age == archiveTTL` fails `age < archiveTTL`, mirroring
		// the pre-existing `guard age < archiveTTL else { continue }` filter.
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: archiveTTL, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .pruned)
	}

	func testPastPruneHorizonIsPruned() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: archiveTTL + 1, isRendered: false, isConcealed: false, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .pruned)
	}

	// MARK: - Precedence: prune horizon beats concealed-active

	func testConcealedPastPruneHorizonIsPruned() {
		XCTAssertEqual(
			SessionLifecycle.classify(
				age: archiveTTL, isRendered: false, isConcealed: true, liveTTL: liveTTL,
				archiveTTL: archiveTTL), .pruned)
	}
}

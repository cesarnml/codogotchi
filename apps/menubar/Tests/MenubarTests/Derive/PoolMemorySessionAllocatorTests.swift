import XCTest

@testable import Codogotchi

// MARK: - RED (P18.02) — session-number allocator release-from-captured-identity
//
// The P18.02 red-step author (`PoolDeriveSelectionTests.swift`) left the
// session-number allocator unresolved as an open question. The ticket owner
// has since decided it IS in scope for this ticket (Outcome bullet 3): "the
// free-list allocator is a value type in `PoolMemory`; assign-on-spawn/
// release-on-teardown semantics (including the unlimited-cap sentinel and
// release-from-captured-identity rule) match today's `SessionNumberAllocator`
// + `windowSessionIdentities` behavior."
//
// This is the specific leak-under-cap bug the ticket's Review Focus calls
// out: `FloatingPetWindowPool.releaseSessionNumber` reads the identity
// captured at ASSIGN time (`windowSessionIdentities`), never the latest
// snapshot — because by the time a session ends, its `state.d` slice is
// already deleted and its identity has already dropped out of
// `snapshot.renderKeyIdentities` on the very next tick, while the window
// itself lingers until TTL. Releasing from the (now-absent) latest snapshot
// would silently no-op and leak the number under a bounded cap.
//
// This test locks that exact contract directly against `PoolMemory`'s pure
// allocator surface, independent of the full `derive` selection machinery:
// assign a number, then release using ONLY the window key (never re-passing
// the identity) — release must still succeed and free the number for reuse.
@MainActor
final class PoolMemorySessionAllocatorTests: XCTestCase {

	private let key: WindowKey = "claude_code:s1"
	private let identity = RenderKeyIdentity(origin: "claude_code", sessionId: "s1")

	/// Assigns a session number and captures the assigning identity —
	/// mirrors `FloatingPetWindowPool.assignSessionNumber`.
	private func assigned(_ memory: PoolMemory) -> PoolMemory {
		var memory = memory
		let number = memory.sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
		XCTAssertEqual(number, 1)
		memory.windowSessionIdentities[key] = identity
		return memory
	}

	func test_releaseUsesAssignTimeIdentityNotLatestSnapshot() {
		var memory = PoolMemory()
		memory = assigned(memory)

		// Release exactly the way `FloatingPetWindowPool.releaseSessionNumber`
		// does: looked up by window key ALONE — no re-supplied identity, and
		// nothing resembling "the latest snapshot" is consulted here at all.
		guard let releasedIdentity = memory.windowSessionIdentities.removeValue(forKey: key) else {
			return XCTFail("expected the assign-time identity to still be captured at teardown")
		}
		memory.sessionNumberAllocator.release(origin: releasedIdentity.origin, sessionId: releasedIdentity.sessionId)

		// The freed number must be reusable — the lowest-free-number contract
		// — proving `release` actually ran, rather than silently no-op'ing
		// because it tried to resolve the identity from an empty/absent
		// latest-snapshot lookup instead of the captured one.
		let secondKey: WindowKey = "claude_code:s2"
		var afterRelease = memory
		let reassignedNumber = afterRelease.sessionNumberAllocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(
			reassignedNumber, 1,
			"the number freed by release must be reused by the next assign for this origin — proof "
				+ "release used the captured assign-time identity rather than silently no-op'ing")
		_ = secondKey
	}

	/// Under an Unlimited origin (`sessionCap == 0`), a released number must
	/// never be reused — the free-list bookkeeping is skipped entirely,
	/// matching `SessionNumberAllocator`'s documented "monotonic, never
	/// reused" Unlimited contract.
	func test_unlimitedOriginNeverReusesReleasedNumber() {
		var memory = PoolMemory()
		memory.sessionNumberAllocator.setUnlimited(true, origin: "claude_code")
		memory = assigned(memory)

		guard let releasedIdentity = memory.windowSessionIdentities.removeValue(forKey: key) else {
			return XCTFail("expected the assign-time identity to still be captured at teardown")
		}
		memory.sessionNumberAllocator.release(origin: releasedIdentity.origin, sessionId: releasedIdentity.sessionId)

		let nextNumber = memory.sessionNumberAllocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(
			nextNumber, 2,
			"an Unlimited origin must never reuse a released number — the next session gets the next "
				+ "monotonic number instead")
	}

	/// Subagent-review fix: `pruning(_:)` must release the assign-time
	/// identity IMMEDIATELY, in the same call — not defer to `derive`'s next
	/// teardown-diff pass. `pruning(_:)` already removes the key from
	/// `previousDesiredWindowKeys` as part of its own bookkeeping, so once
	/// that removal has happened, a subsequent `derive` tick can never see
	/// this key in `previousKeys` again; `torndownKeys =
	/// previousKeys.subtracting(visibleFinalKeys)` would compute empty for
	/// it forever, so the release-on-teardown path would never fire and the
	/// number would leak. This test proves the number is reusable right after
	/// `pruning(_:)` returns, with no `derive` tick involved at all.
	func test_pruningReleasesSessionNumberImmediatelyWithoutADeriveTick() {
		var memory = PoolMemory()
		memory = assigned(memory)
		memory.previousDesiredWindowKeys.insert(key)

		memory = memory.pruning(key)

		XCTAssertNil(
			memory.windowSessionIdentities[key],
			"pruning must remove the captured identity immediately, in the same call")

		let reassignedNumber = memory.sessionNumberAllocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(
			reassignedNumber, 1,
			"the number freed by pruning must be reusable immediately — proof pruning released it "
				+ "itself rather than waiting for a derive tick that can never observe this key again "
				+ "once previousDesiredWindowKeys already excludes it")
	}
}

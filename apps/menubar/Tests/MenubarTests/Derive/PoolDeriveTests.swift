import XCTest

@testable import Codogotchi

// MARK: - Helpers

private func makeSnapshot(
	state: ActivityState = .implementing,
	updated: String
) -> StateSnapshot {
	StateSnapshot(
		schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
		activityState: state,
		updatedAt: updated,
		sourceEvent: nil,
		attention: nil
	)
}

private func makePerPlatformSnapshot(_ map: [WindowKey: StateSnapshot]) -> PerPlatformSnapshot {
	PerPlatformSnapshot(perPlatform: map, gateBadges: [:], rpgSnapshot: .safeDefault)
}

private func makeCustomization(
	platformModes: [String: PlatformMode] = [:],
	ttlSeconds: Int = 300
) -> CustomizationSnapshot {
	CustomizationSnapshot(
		platformModes: platformModes,
		idleDismissTtlSeconds: ttlSeconds,
		menubarIconMonochrome: false,
		combinedMinimalistEnabled: false,
		minimalistBadgeScale: 1.0,
		sessionPetsEnabled: [:],
		sessionCap: [:],
		idleImpatientSeconds: 300,
		idleFrustratedSeconds: 600,
		evictSessionPetsEnabled: true
	)
}

private func tick(
	_ map: [WindowKey: StateSnapshot],
	customization: CustomizationSnapshot = makeCustomization(),
	currentTime: Date,
	memory: PoolMemory
) -> (DesiredWindows, PoolMemory) {
	let input = PoolTickInput(
		snapshot: makePerPlatformSnapshot(map),
		customization: customization,
		assignments: .safeDefault,
		currentTime: currentTime
	)
	return PoolDerive.derive(input: input, memory: memory)
}

private let t0 = Date(timeIntervalSinceReferenceDate: 0)

// MARK: - Test suite

@MainActor
final class PoolDeriveTests: XCTestCase {

	// MARK: First-sight seeding

	func testFirstSeenIsSetOnceAndNeverRefreshed() {
		var memory = PoolMemory()
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t0, memory: memory)
		XCTAssertEqual(memory.firstSeenAt["claude_code"], t0)

		let t1 = t0.addingTimeInterval(50)
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:50.000Z")],
			currentTime: t1, memory: memory)
		// firstSeenAt must not move on the second tick.
		XCTAssertEqual(memory.firstSeenAt["claude_code"], t0)
	}

	// MARK: Idle-frozen TTL clock

	func testLastSeenClockFreezesWhileIdleAndSeedsOnFirstSight() {
		var memory = PoolMemory()
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .idle, updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t0, memory: memory)
		// Seeded on first sight even though the slice is idle.
		XCTAssertEqual(memory.lastSeenAt["claude_code"], t0)

		let t1 = t0.addingTimeInterval(30)
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .idle, updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t1, memory: memory)
		// Still idle: the clock must NOT advance to t1.
		XCTAssertEqual(memory.lastSeenAt["claude_code"], t0)

		let t2 = t0.addingTimeInterval(60)
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .implementing, updated: "2026-06-28T10:01:00.000Z")],
			currentTime: t2, memory: memory)
		// Doing work again: the clock advances.
		XCTAssertEqual(memory.lastSeenAt["claude_code"], t2)
	}

	// MARK: Last-active election eligibility

	func testLastActiveElectionExcludesClockSkewedDepartedKeys() {
		var memory = PoolMemory()
		let customization = makeCustomization(ttlSeconds: 60)
		// "cursor" appears once with a far-future updatedAt (clock skew), then
		// disappears from every later snapshot.
		(_, memory) = tick(
			[
				"claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
				"cursor": makeSnapshot(updated: "2099-01-01T00:00:00.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)

		// Past cursor's TTL window and it is absent from the snapshot: it
		// must drop out of eligibility, so its clock-skewed updatedAt cannot
		// win last-active immunity over the currently-visible key.
		let t1 = t0.addingTimeInterval(120)
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:02:00.000Z")],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(memory.lastActiveRenderKey, "claude_code")
		XCTAssertNil(memory.lastUpdatedAt["cursor"])
	}

	// MARK: Sticky HUD-bearer

	func testHudBearerDoesNotHopMidPromptToNewerTimestamp() {
		var memory = PoolMemory()
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .implementing, updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t0, memory: memory)
		XCTAssertEqual(memory.hudBearingRenderKey, "claude_code")

		// "cursor" ticks with a newer updated_at while claude_code is still
		// in-flight (implementing): the HUD bearer must not hop.
		let t1 = t0.addingTimeInterval(5)
		(_, memory) = tick(
			[
				"claude_code": makeSnapshot(state: .implementing, updated: "2026-06-28T10:00:00.000Z"),
				"cursor": makeSnapshot(state: .implementing, updated: "2026-06-28T10:00:05.000Z"),
			],
			currentTime: t1, memory: memory)
		XCTAssertEqual(memory.hudBearingRenderKey, "claude_code")
	}

	func testHudBearerReElectsWhenHolderGoesIdle() {
		var memory = PoolMemory()
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .implementing, updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t0, memory: memory)
		XCTAssertEqual(memory.hudBearingRenderKey, "claude_code")

		let t1 = t0.addingTimeInterval(5)
		(_, memory) = tick(
			[
				"claude_code": makeSnapshot(state: .idle, updated: "2026-06-28T10:00:00.000Z"),
				"cursor": makeSnapshot(state: .implementing, updated: "2026-06-28T10:00:05.000Z"),
			],
			currentTime: t1, memory: memory)
		XCTAssertEqual(memory.hudBearingRenderKey, "cursor")
	}

	// MARK: Memory bounding

	func testEligibilityBoundingDropsKeysPastTTLWithNoWindow() {
		var memory = PoolMemory()
		let customization = makeCustomization(ttlSeconds: 30)
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertNotNil(memory.firstSeenAt["claude_code"])

		// claude_code vanishes from the snapshot and its TTL window elapses.
		let t1 = t0.addingTimeInterval(60)
		(_, memory) = tick([:], customization: customization, currentTime: t1, memory: memory)

		XCTAssertNil(memory.firstSeenAt["claude_code"])
		XCTAssertNil(memory.lastSeenAt["claude_code"])
		XCTAssertNil(memory.lastUpdatedAt["claude_code"])
	}

	func testOffModeKeyIsFilteredFromTracking() {
		var memory = PoolMemory()
		let customization = makeCustomization(platformModes: ["claude_code": .off])
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertNil(memory.firstSeenAt["claude_code"])
		XCTAssertNil(memory.lastSeenAt["claude_code"])
	}

	// MARK: TTL-expiry predicate (last-active immunity)

	func testIsTTLExpiredHonorsLastActiveImmunity() {
		var memory = PoolMemory()
		let customization = makeCustomization(ttlSeconds: 30)
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.lastActiveRenderKey, "claude_code")

		let t1 = t0.addingTimeInterval(120)
		XCTAssertFalse(
			PoolDerive.isTTLExpired(
				windowKey: "claude_code", memory: memory, ttlSeconds: 30, currentTime: t1),
			"the last-active key must never read as TTL-expired")
	}

	func testIsTTLExpiredFiresPastTTLForNonLastActiveKey() {
		var memory = PoolMemory()
		let customization = makeCustomization(ttlSeconds: 30)
		(_, memory) = tick(
			[
				"claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
				"cursor": makeSnapshot(updated: "2026-06-28T09:59:00.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.lastActiveRenderKey, "claude_code")

		let t1 = t0.addingTimeInterval(120)
		XCTAssertTrue(
			PoolDerive.isTTLExpired(
				windowKey: "cursor", memory: memory, ttlSeconds: 30, currentTime: t1))
	}

	// MARK: Multi-tick fold

	func testMultiTickFoldCarriesMemoryForward() {
		var memory = PoolMemory()
		let customization = makeCustomization(ttlSeconds: 60)

		// Tick 1: claude_code appears.
		(_, memory) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.firstSeenAt["claude_code"], t0)
		XCTAssertEqual(memory.lastActiveRenderKey, "claude_code")

		// Tick 2: cursor joins with a newer updated_at; claude_code keeps ticking.
		let t1 = t0.addingTimeInterval(10)
		(_, memory) = tick(
			[
				"claude_code": makeSnapshot(updated: "2026-06-28T10:00:10.000Z"),
				"cursor": makeSnapshot(updated: "2026-06-28T10:00:15.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)
		XCTAssertEqual(memory.firstSeenAt["claude_code"], t0)
		XCTAssertEqual(memory.firstSeenAt["cursor"], t1)
		XCTAssertEqual(memory.lastActiveRenderKey, "cursor")

		// Tick 3: claude_code drops out of the snapshot but is still within TTL.
		let t2 = t0.addingTimeInterval(20)
		(_, memory) = tick(
			["cursor": makeSnapshot(updated: "2026-06-28T10:00:25.000Z")],
			customization: customization, currentTime: t2, memory: memory)
		XCTAssertNotNil(memory.lastSeenAt["claude_code"], "still within the 60s TTL window")
		XCTAssertEqual(memory.lastActiveRenderKey, "cursor")

		// Tick 4: TTL elapses for claude_code; it must be pruned from memory.
		let t3 = t0.addingTimeInterval(100)
		(_, memory) = tick(
			["cursor": makeSnapshot(updated: "2026-06-28T10:01:40.000Z")],
			customization: customization, currentTime: t3, memory: memory)
		XCTAssertNil(memory.lastSeenAt["claude_code"])
		XCTAssertNil(memory.firstSeenAt["claude_code"])
	}

	// MARK: DesiredWindows membership (selection landed in P18.02)

	/// P18.01 left `derive` always returning an empty `DesiredWindows` — the
	/// gate this test originally locked. P18.02 wires selection (Step 6c) and
	/// the collapse steps (6a/6a2/6b), so `derive` now actually constructs a
	/// `DesiredWindow` for a visible, non-off-mode, non-hidden, non-TTL-
	/// expired render key. Push-payload fields on that `DesiredWindow`
	/// (besides `isMinimalist`/`inheritedFrameFrom`) remain P18.03 scope —
	/// see `PoolDeriveSelectionTests.swift` for the full P18.02 gap-class
	/// coverage this ticket adds.
	func testDeriveConstructsADesiredWindowForAVisibleRenderKey() {
		let memory = PoolMemory()
		let (desired, _) = tick(
			["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
			currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code"])
		XCTAssertEqual(desired.windows["claude_code"]?.isMinimalist, false)
	}
}

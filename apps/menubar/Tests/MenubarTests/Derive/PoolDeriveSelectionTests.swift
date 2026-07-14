import XCTest

@testable import Codogotchi

// MARK: - RED (P18.02) — derive selection: cap/eviction, grandfather, frame
// directives, user-action transitions.
//
// These tests exercise API surface that does not exist yet on `PoolMemory` /
// `PoolDerive` / `DesiredWindow` — referencing it is the expected red signal
// for this ticket (see ticket-02-derive-selection.md "Red" section: a
// compile-failing red is acceptable when the API under test doesn't exist
// yet). No production code is added by this commit. The exact shape assumed
// below is documented inline and in this session's report so GREEN can
// confirm or adjust it:
//
// - `PoolMemory` gains: `slotOccupants: Set<WindowKey>`,
//   `prunedOrigins: Set<String>`, `userHiddenWindowKeys: Set<WindowKey>`,
//   `windowSpawnedModes: [WindowKey: PlatformMode]`,
//   `evictedFrameDirectives: [String: [WindowKey]]` (per-origin FIFO of the
//   TORN-DOWN window key whose on-screen frame a later spawn for that origin
//   should inherit — never a fabricated `CGRect`; `apply` reads the actual
//   frame at execution time).
// - `PoolMemory` gains pure transition functions matching the legacy
//   out-of-band methods: `hiding(_:)`, `showing(_:)`, `pruning(_:origin:)`,
//   `hidingAllOthers(keeping:among:)`, `resettingPromptTimer(for:)`.
// - `DesiredWindow` gains `inheritedFrameFrom: WindowKey?` — replacing the
//   P18.01 placeholder `inheritedFrame: CGRect?`, which fabricates a value
//   this ticket's contract explicitly forbids. Flagged as an open question
//   below; GREEN may instead keep `inheritedFrame` and add a parallel field.

// MARK: - Helpers (mirrors PoolDeriveTests.swift)

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

private func makePerPlatformSnapshot(
	_ map: [WindowKey: StateSnapshot],
	identities: [WindowKey: RenderKeyIdentity] = [:]
) -> PerPlatformSnapshot {
	PerPlatformSnapshot(perPlatform: map, gateBadges: [:], rpgSnapshot: .safeDefault)
}

private func makeCustomization(
	platformModes: [String: PlatformMode] = [:],
	ttlSeconds: Int = 300,
	sessionPetsEnabled: [String: Bool] = [:],
	sessionCap: [String: Int] = [:],
	evictSessionPetsEnabled: Bool = true
) -> CustomizationSnapshot {
	CustomizationSnapshot(
		platformModes: platformModes,
		idleDismissTtlSeconds: ttlSeconds,
		menubarIconMonochrome: false,
		combinedMinimalistEnabled: false,
		minimalistBadgeScale: 1.0,
		sessionPetsEnabled: sessionPetsEnabled,
		sessionCap: sessionCap,
		idleImpatientSeconds: 300,
		idleFrustratedSeconds: 600,
		evictSessionPetsEnabled: evictSessionPetsEnabled
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

// MARK: - Gap class 1: mode-transition teardown (Step 6b)

@MainActor
final class PoolDeriveModeTransitionTeardownTests: XCTestCase {

	/// own→minimalist must tear the stale window's key out of desired
	/// membership immediately so the spawn gate re-enters and the correct
	/// renderer wins next tick — the exact bug
	/// `testOwnToMinimalistTransitionReplacesWindow` locks at the
	/// `FloatingPetWindowPool` level.
	func test_ownToMinimalistModeSwitchTearsDownStaleWindow() {
		var memory = PoolMemory()
		var customization = makeCustomization(platformModes: ["codex": .own])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["codex": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.windowSpawnedModes["codex"], .own)
		XCTAssertNotNil(desired.windows["codex"])

		customization = makeCustomization(platformModes: ["codex": .minimalist])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			["codex": makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(
			memory.windowSpawnedModes["codex"], .minimalist,
			"the spawned-mode bookkeeping must flip to minimalist after teardown+respawn")
		XCTAssertEqual(desired.windows["codex"]?.isMinimalist, true)
	}

	/// minimalist→own is the mirror-image regression
	/// (`testMinimalistToOwnTransitionReplacesWindow`).
	func test_minimalistToOwnModeSwitchTearsDownStaleWindow() {
		var memory = PoolMemory()
		var customization = makeCustomization(platformModes: ["codex": .minimalist])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["codex": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.windowSpawnedModes["codex"], .minimalist)

		customization = makeCustomization(platformModes: ["codex": .own])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			["codex": makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(memory.windowSpawnedModes["codex"], .own)
		XCTAssertEqual(desired.windows["codex"]?.isMinimalist, false)
	}

	/// Combined-mode collapse of directly-keyed windows (Step 6a): an origin
	/// switching own/minimalist→combined must lose its own directly-keyed
	/// window immediately — it must not coexist with the shared `.combined`
	/// window.
	func test_combinedModeCollapsesDirectlyKeyedWindow() {
		var memory = PoolMemory()
		var customization = makeCustomization(platformModes: ["codex": .own])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["codex": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertNotNil(desired.windows["codex"])

		customization = makeCustomization(platformModes: ["codex": .combined])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[.combined: makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertNil(
			desired.windows["codex"],
			"the stale directly-keyed window must collapse the instant its origin folds into combined")
		XCTAssertNotNil(desired.windows[.combined])
	}
}

// MARK: - Gap class 2: hide vs. cap incumbency (P15.07-QC)

@MainActor
final class PoolDeriveHideVsCapIncumbencyTests: XCTestCase {

	/// P15.07-QC: a user-hidden incumbent's window is torn down while it
	/// still holds its cap slot — `slotOccupants` (not window/desired
	/// membership) is the source of truth for incumbency, so hiding never
	/// strips the slot and an unrelated standby session cannot backfill it.
	func test_hiddenIncumbentKeepsSlotUnderCapPressure() {
		var memory = PoolMemory()
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:idle-one", "claude_code:active-one"])

		// User hides the idle incumbent: a pure transition, immediately
		// removing it from desired membership without touching slotOccupants.
		memory = memory.hiding("claude_code:idle-one")
		XCTAssertTrue(
			memory.slotOccupants.contains("claude_code:idle-one"),
			"hiding must never release the cap slot")

		// Next tick: a pending idle sibling arrives. It must NOT backfill the
		// hidden incumbent's still-reserved slot.
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(
			Set(desired.windows.keys), ["claude_code:active-one"],
			"the hidden incumbent's window stays absent and the pending sibling must not backfill its slot")
		XCTAssertTrue(memory.slotOccupants.contains("claude_code:idle-one"))
		XCTAssertFalse(memory.slotOccupants.contains("claude_code:idle-two"))
	}

	/// P15.07-QC: a key that genuinely loses the cap fight (a real rank
	/// eviction, not a hide) must have its hidden flag purged — otherwise the
	/// menu keeps offering a dead "Show" entry.
	func test_genuinelyEvictedHiddenKeyLosesHiddenFlag() {
		var memory = PoolMemory()
		var customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)

		memory = memory.hiding("claude_code:idle-a")
		XCTAssertTrue(memory.userHiddenWindowKeys.contains("claude_code:idle-a"))

		// The cap is lowered to 1 — a deliberate curation act that legitimately
		// evicts the hidden idle session (its slot loses the rank fight to the
		// in-flight incumbent, not merely conceals it).
		customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:active-b"])
		XCTAssertFalse(
			memory.userHiddenWindowKeys.contains("claude_code:idle-a"),
			"a hidden key that genuinely loses the cap fight must be purged from userHiddenWindowKeys")
		XCTAssertFalse(memory.slotOccupants.contains("claude_code:idle-a"))
	}
}

// MARK: - Gap class 3: grandfather admission (Step 6a2, both directions)

@MainActor
final class PoolDeriveGrandfatherAdmissionTests: XCTestCase {

	/// Enabling direction: toggling session-pets ON collapses the plain
	/// window and the grandfathered session window must inherit its exact
	/// frame — the sole enabling-direction frame capture site.
	func test_grandfatherAdmission_enablingDirection() {
		var memory = PoolMemory()
		var customization = makeCustomization()
		var desired: DesiredWindows
		(desired, memory) = tick(
			["claude_code:winner": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code"])

		customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			["claude_code:winner": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:winner"])
		XCTAssertEqual(
			desired.windows["claude_code:winner"]?.inheritedFrameFrom, "claude_code",
			"the grandfathered session must carry a frame directive referencing the collapsed plain "
				+ "window's key, not a fabricated CGRect")
	}

	/// Disabling direction: several session-keyed windows collapse to one new
	/// plain window with NO frame inheritance — there is no single
	/// unambiguous predecessor to inherit from.
	func test_grandfatherAdmission_disablingDirection() {
		var memory = PoolMemory()
		var customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:s1", "claude_code:s2"])

		customization = makeCustomization()
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(Set(desired.windows.keys), ["claude_code"])
		XCTAssertNil(
			desired.windows["claude_code"]?.inheritedFrameFrom,
			"disabling session-pets must not inherit either sibling session's frame")
	}
}

// MARK: - Gap class 4: eviction frame-inheritance (multi-eviction FIFO)

@MainActor
final class PoolDeriveEvictionFrameInheritanceTests: XCTestCase {

	/// A single eviction: the incoming active session's directive must
	/// reference the evicted session's window key.
	func test_evictionFrameInheritance_singleEviction() {
		var memory = PoolMemory()
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:idle-one"])

		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:active-one"])
		XCTAssertEqual(
			desired.windows["claude_code:active-one"]?.inheritedFrameFrom, "claude_code:idle-one")
	}

	/// Multi-eviction FIFO across ticks: two siblings evicted in the SAME
	/// tick (a cap reduction of more than 1) must both survive in the queue
	/// and be claimed in order — not overwritten by a single-slot bug, and
	/// not dependent on `DesiredWindows.windows`' dictionary iteration order
	/// (spawn-order determinism must be explicit/sorted per the ticket's
	/// Review Focus).
	func test_evictionFrameInheritance_multiEvictionFIFO() {
		var memory = PoolMemory()
		var customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 3])
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-b": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(
			Set(desired.windows.keys),
			["claude_code:idle-a", "claude_code:idle-b", "claude_code:idle-c"])

		// Tick 2: cap drops to 1 in one settings change — evicts idle-a and
		// idle-b simultaneously (idle-c, most recently updated, wins the
		// tie-break). Both eviction directives must queue, FIFO by eviction
		// order (idle-a before idle-b, since `ordered` walks least-recent
		// first within a rank).
		customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-b": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), ["claude_code:idle-c"])
		XCTAssertEqual(
			memory.evictedFrameDirectives["claude_code"], ["claude_code:idle-a", "claude_code:idle-b"],
			"both evicted keys must queue FIFO in eviction order, explicit/sorted rather than "
				+ "incidental to Dictionary iteration order")

		// Tick 3: cap is raised back up and two new active sessions arrive at
		// once — each must drain a DISTINCT directive from the FIFO, in
		// queue order, and the queue must be empty afterward.
		customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 3])
		let t2 = t0.addingTimeInterval(2)
		(desired, memory) = tick(
			[
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
				"claude_code:new-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:05:00.000Z"),
				"claude_code:new-two": makeSnapshot(state: .implementing, updated: "2026-07-01T10:05:01.000Z"),
			],
			customization: customization, currentTime: t2, memory: memory)

		XCTAssertEqual(
			Set(desired.windows.keys),
			["claude_code:idle-c", "claude_code:new-one", "claude_code:new-two"])
		let newOneDirective = desired.windows["claude_code:new-one"]?.inheritedFrameFrom
		let newTwoDirective = desired.windows["claude_code:new-two"]?.inheritedFrameFrom
		XCTAssertEqual(
			Set([newOneDirective, newTwoDirective]),
			Set(["claude_code:idle-a" as WindowKey?, "claude_code:idle-b" as WindowKey?]),
			"the two newly-spawned sessions must drain the two queued directives between them, "
				+ "not the same one twice")
		XCTAssertTrue(
			(memory.evictedFrameDirectives["claude_code"] ?? []).isEmpty,
			"the FIFO must be fully drained once both spawns have claimed their directive")
	}
}

// MARK: - Combined-mode collapse of directly-keyed windows (Step 6a) — focused

@MainActor
final class PoolDeriveCombinedCollapseTests: XCTestCase {

	func test_combinedFoldedSessionsProduceOneSharedDesiredWindow() {
		var memory = PoolMemory()
		let customization = makeCustomization(platformModes: ["claude_code": .combined])
		let (desired, _) = tick(
			[.combined: makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(Set(desired.windows.keys), [.combined])
		_ = memory
	}
}

// MARK: - Per-origin session-cap selection (Step 6c) — focused

@MainActor
final class PoolDeriveSessionCapSelectionTests: XCTestCase {

	/// Slot-occupancy resync: `slotOccupants` must be replaced exactly with
	/// `selection.rendered` for the origin every tick, not incrementally
	/// unioned — a session that drops out must leave the set.
	func test_slotOccupancyResyncsToExactlySelectionRenderedEveryTick() {
		var memory = PoolMemory()
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["claude_code:a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.slotOccupants, ["claude_code:a"])

		// "a" drops out of the snapshot entirely (TTL/pruned elsewhere); "b"
		// is the sole session this tick.
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			["claude_code:b": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z")],
			customization: customization, currentTime: t1, memory: memory)
		XCTAssertEqual(
			memory.slotOccupants, ["claude_code:b"],
			"slotOccupants must resync to exactly this tick's selection.rendered, not accumulate")
		_ = desired
	}

	/// Pinned hidden keys: a hidden incumbent beats an in-flight newcomer for
	/// its own slot even with "Evict Session Pets" enabled — pinning
	/// protects against newcomers only.
	func test_pinnedHiddenKeyBeatsInFlightNewcomerForItsSlot() {
		var memory = PoolMemory()
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2],
			evictSessionPetsEnabled: true)
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code:idle-hidden": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		memory = memory.hiding("claude_code:idle-hidden")

		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[
				"claude_code:idle-hidden": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:newcomer": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization, currentTime: t1, memory: memory)

		XCTAssertTrue(memory.userHiddenWindowKeys.contains("claude_code:idle-hidden"))
		XCTAssertEqual(desired.pendingSessionKeys, ["claude_code:newcomer"])
	}

	/// Subagent-review fix: an origin that had a rendered session on one tick
	/// but has ZERO session-cap candidates the next (every render key for
	/// that origin vanished from the snapshot entirely, not merely evicted by
	/// the cap) never runs the per-origin cap-selection loop iteration for
	/// that origin, so it must still get its entire `slotOccupants` slice
	/// cleared rather than leaking the stale occupant forever.
	func test_zeroCandidateOriginClearsSlotOccupantsSlice() {
		var memory = PoolMemory()
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		var desired: DesiredWindows
		(desired, memory) = tick(
			["claude_code:a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		XCTAssertEqual(memory.slotOccupants, ["claude_code:a"])

		// Next tick: the origin's sole session vanishes from the snapshot
		// entirely — zero session-cap candidates for "claude_code" this tick.
		let t1 = t0.addingTimeInterval(1)
		(desired, memory) = tick(
			[:], customization: customization, currentTime: t1, memory: memory)

		XCTAssertTrue(
			memory.slotOccupants.isEmpty,
			"an origin with zero candidates this tick must have its entire slotOccupants slice "
				+ "cleared, not left as a phantom occupant forever")
		_ = desired
	}

	/// Subagent-review fix (bounded→unlimited): if an origin's cap flips to
	/// Unlimited on the SAME tick every one of its candidates disappears
	/// (zero candidates this tick, so the per-origin loop never runs for it),
	/// the allocator's unlimited/bounded mode must still be refreshed against
	/// the CURRENT tick's customization before the teardown release — not
	/// left at whatever mode a prior tick set. Otherwise release would use
	/// the stale bounded mode and incorrectly free-list the number.
	func test_capFlipBoundedToUnlimitedRefreshesAllocatorModeBeforeZeroCandidateTeardown() {
		var memory = PoolMemory()
		let identity = RenderKeyIdentity(origin: "claude_code", sessionId: "s1")
		let number = memory.sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
		XCTAssertEqual(number, 1)
		memory.windowSessionIdentities["claude_code:s1"] = identity
		memory.previousDesiredWindowKeys.insert("claude_code:s1")

		// The cap flips to Unlimited (0) AND the session disappears from the
		// snapshot entirely, in the same tick — a teardown-only tick with no
		// candidates for "claude_code" at all.
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 0])
		let t1 = t0.addingTimeInterval(1)
		(_, memory) = tick([:], customization: customization, currentTime: t1, memory: memory)

		XCTAssertNil(memory.windowSessionIdentities["claude_code:s1"])
		let nextNumber = memory.sessionNumberAllocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(
			nextNumber, 2,
			"under the now-Unlimited mode the released number must never be reused — a stale "
				+ "bounded mode left over from before the cap flip would incorrectly free-list it, "
				+ "letting the next assign wrongly reuse number 1")
	}

	/// Subagent-review fix (unlimited→bounded): the mirror-image direction —
	/// an origin's cap flips to bounded on the same tick every candidate
	/// disappears; the allocator must refresh to bounded mode before
	/// releasing so the freed number returns to the free list for reuse,
	/// rather than being discarded under a stale Unlimited mode.
	func test_capFlipUnlimitedToBoundedRefreshesAllocatorModeBeforeZeroCandidateTeardown() {
		var memory = PoolMemory()
		memory.sessionNumberAllocator.setUnlimited(true, origin: "claude_code")
		let identity = RenderKeyIdentity(origin: "claude_code", sessionId: "s1")
		let number = memory.sessionNumberAllocator.assign(origin: identity.origin, sessionId: identity.sessionId)
		XCTAssertEqual(number, 1)
		memory.windowSessionIdentities["claude_code:s1"] = identity
		memory.previousDesiredWindowKeys.insert("claude_code:s1")

		// The cap flips to bounded (2) AND the session disappears from the
		// snapshot entirely, in the same tick.
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let t1 = t0.addingTimeInterval(1)
		(_, memory) = tick([:], customization: customization, currentTime: t1, memory: memory)

		XCTAssertNil(memory.windowSessionIdentities["claude_code:s1"])
		let nextNumber = memory.sessionNumberAllocator.assign(origin: "claude_code", sessionId: "s2")
		XCTAssertEqual(
			nextNumber, 1,
			"under the now-bounded mode the released number must return to the free list and be "
				+ "reused by the very next assign — a stale Unlimited mode left over from before the "
				+ "cap flip would have discarded it instead")
	}

	/// Pruned-origin promotion restriction: once an origin is armed by a
	/// manual prune, only an in-flight session may newly promote into a
	/// freed slot — a merely-held idle sibling must not backfill it.
	func test_prunedOriginRestrictsNewPromotionsToInFlight() {
		var memory = PoolMemory()
		memory.prunedOrigins.insert("claude_code")
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		// One slot is free (only one session currently exists at cap 2), and
		// a held idle sibling arrives — it must NOT be promoted because the
		// origin is prune-armed and it is not in-flight.
		let (desired, _) = tick(
			[
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-held": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)

		XCTAssertEqual(
			Set(desired.windows.keys), ["claude_code:active-one"],
			"a prune-armed origin must not backfill a freed slot with a merely-held idle session")
	}
}

// MARK: - Out-of-band user-action pure transition functions

@MainActor
final class PoolMemoryUserActionTransitionTests: XCTestCase {

	/// `hiding(_:)` mirrors `setVisible(false, for:)`: inserts into
	/// `userHiddenWindowKeys`, never touches `slotOccupants`.
	func test_hidingInsertsHiddenFlagWithoutTouchingSlotOccupants() {
		var memory = PoolMemory()
		memory.slotOccupants.insert("claude_code:s1")
		memory = memory.hiding("claude_code:s1")
		XCTAssertTrue(memory.userHiddenWindowKeys.contains("claude_code:s1"))
		XCTAssertTrue(
			memory.slotOccupants.contains("claude_code:s1"),
			"hide must be a pure visibility toggle, not a cap release")
	}

	/// `showing(_:)` mirrors `setVisible(true, for:)`: clears the hidden
	/// flag AND re-seeds the TTL clock (drops `lastSeenAt` so the next tick
	/// re-seeds full TTL grace) — the exact fix for the "Show is a silent
	/// no-op" bug the ticket's Review Focus calls out.
	func test_showingClearsHiddenFlagAndReseedsTTLClock() {
		var memory = PoolMemory()
		memory.userHiddenWindowKeys.insert("claude_code:s1")
		memory.lastSeenAt["claude_code:s1"] = t0
		memory = memory.showing("claude_code:s1")
		XCTAssertFalse(memory.userHiddenWindowKeys.contains("claude_code:s1"))
		XCTAssertNil(
			memory.lastSeenAt["claude_code:s1"],
			"showing must drop the TTL clock entry so the next tick re-seeds full grace — "
				+ "without this, Show can silently no-op when a sibling session wins the "
				+ "last-active election on a newer updated_at")
	}

	/// `pruning(_:)` mirrors `pruneSession`'s in-memory bookkeeping: arms the
	/// origin (permanently, for the process lifetime) and clears every
	/// per-key bookkeeping map a fresh session at that key should not
	/// inherit stale state from.
	func test_pruningArmsOriginAndClearsBookkeeping() {
		var memory = PoolMemory()
		memory.slotOccupants.insert("claude_code:s1")
		memory.windowSpawnedModes["claude_code:s1"] = .own
		memory = memory.pruning("claude_code:s1")
		XCTAssertTrue(memory.prunedOrigins.contains("claude_code"))
		XCTAssertNil(memory.windowSpawnedModes["claude_code:s1"])
	}

	func test_pruningCombinedWindowArmsResolvedOrigin() {
		let memory = PoolMemory().pruning(.combined, resolvedOrigin: "cursor")
		XCTAssertTrue(memory.prunedOrigins.contains("cursor"))
		XCTAssertFalse(memory.prunedOrigins.contains("combined"))
	}

	/// `hidingAllOthers(keeping:)` mirrors `hideAllOtherWindows`: every
	/// currently-desired key except the kept one is hidden in one batch.
	func test_hidingAllOthersHidesEveryDesiredKeyExceptKept() {
		var memory = PoolMemory()
		let customization = makeCustomization()
		var desired: DesiredWindows
		(desired, memory) = tick(
			[
				"claude_code": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"cursor": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization, currentTime: t0, memory: memory)
		memory = memory.hidingAllOthers(keeping: "claude_code", among: Set(desired.windows.keys))
		XCTAssertTrue(memory.userHiddenWindowKeys.contains("cursor"))
		XCTAssertFalse(memory.userHiddenWindowKeys.contains("claude_code"))
	}

	/// `resettingPromptTimer(for:)` mirrors `resetPromptTimer(forWindowKey:)`:
	/// a live user action (Force Idle, attention-bubble dismiss) that stamps
	/// the pool-owned prompt timer with the real current time so a
	/// subsequent stale-slice poll cannot restart it.
	func test_resettingPromptTimerStampsRealCurrentTime() {
		var memory = PoolMemory()
		let customization = makeCustomization()
		(_, memory) = tick(
			["claude_code": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, currentTime: t0, memory: memory)
		memory = memory.resettingPromptTimer(for: "claude_code")
		XCTAssertNil(
			memory.promptTimers["claude_code"]?.currentStatus(),
			"a reset prompt timer must present no in-flight status immediately after the reset")
	}
}

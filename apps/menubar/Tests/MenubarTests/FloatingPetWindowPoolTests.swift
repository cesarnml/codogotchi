import XCTest

@testable import Codogotchi

// MARK: - Test double

@MainActor
private final class StubWindowController: FloatingPetWindowControlling {
    var isFloatingPetVisible: Bool = false
    var appliedStates: [(ActivityState, VisualMode)] = []
    var replacePetsCallCount = 0
    var appliedPlatforms: [String?] = []

    func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
    func apply(state: ActivityState, visualMode: VisualMode) { appliedStates.append((state, visualMode)) }
    func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
    func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
    func applyGateBadge(content: GateBadgeContent?) {}
    func applyPlatform(origin: String?) { appliedPlatforms.append(origin) }
    func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) { replacePetsCallCount += 1 }
}

// MARK: - Helpers

private func makeSnapshot(state: ActivityState = .implementing, updated: String) -> StateSnapshot {
    StateSnapshot(
        schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
        activityState: state,
        updatedAt: updated,
        sourceEvent: nil,
        attention: nil
    )
}

private func makePerPlatformSnapshot(_ map: [String: StateSnapshot]) -> PerPlatformSnapshot {
    PerPlatformSnapshot(perPlatform: map, rpgSnapshot: .safeDefault)
}

private func makeCustomization(
    platformModes: [String: PlatformMode] = [:],
    ttlSeconds: Int = 300,
    monochrome: Bool = false
) -> CustomizationSnapshot {
    CustomizationSnapshot(
        platformModes: platformModes,
        idleDismissTtlSeconds: ttlSeconds,
        menubarIconMonochrome: monochrome
    )
}

// MARK: - Test suite

@MainActor
final class FloatingPetWindowPoolTests: XCTestCase {

    // MARK: - Spawn / activeOrigins

    func testTwoOriginSnapshotSpawnsTwoWindows() {
        var created: [String] = []
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { origin, _ in
                created.append(origin)
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code", "cursor"]))
    }

    // MARK: - TTL dismiss

    func testOriginWithExpiredTTLIsDismissedButLastActiveWindowSurvives() {
        var controllers: [String: StubWindowController] = [:]
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(ttlSeconds: 60) },
            windowFactory: { origin, _ in
                let c = StubWindowController()
                controllers[origin] = c
                return c
            },
            now: { currentTime }
        )

        // First tick: both origins present; cursor has later updated_at → last active
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T09:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T09:01:00.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code", "cursor"]))

        // Advance clock past TTL so claude_code is stale; feed empty snapshot
        currentTime = currentTime.addingTimeInterval(61)
        pool.update(snapshot: makePerPlatformSnapshot([:]))

        // claude_code (non-last-active) is dismissed; cursor (last-active) survives
        XCTAssertFalse(pool.activeOrigins.contains("claude_code"), "stale non-last-active window must be dismissed")
        XCTAssertTrue(pool.activeOrigins.contains("cursor"), "last-active window must survive TTL")
    }

    func testIdleOriginPastTTLIsDismissedWhileStillPresent() {
        // The spec scenario: leaving a tool idle dismisses its (non-last-active)
        // window within the TTL even though its slice is still present in state.d/.
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(ttlSeconds: 60) },
            windowFactory: { _, _ in StubWindowController() },
            now: { currentTime }
        )

        // Tick 1: both origins present and idle; cursor newer → last-active.
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(state: .idle, updated: "2026-06-28T09:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-28T09:01:00.000Z"),
        ]))
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code", "cursor"]))

        // Advance past the TTL with BOTH slices still present and still idle.
        currentTime = currentTime.addingTimeInterval(61)
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(state: .idle, updated: "2026-06-28T09:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-28T09:01:00.000Z"),
        ]))

        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "idle non-last-active window must dismiss after TTL even while its slice is still present"
        )
        XCTAssertTrue(
            pool.activeOrigins.contains("cursor"),
            "last-active window survives TTL per spec"
        )
    }

    func testActivityResetsIdleDismissClock() {
        // A pet that keeps working must never idle-dismiss: each active tick refreshes
        // the TTL clock, so it survives indefinitely regardless of elapsed wall time.
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(ttlSeconds: 60) },
            windowFactory: { _, _ in StubWindowController() },
            now: { currentTime }
        )
        // cursor is last-active; claude_code keeps working across a long span.
        for i in 0...10 {
            currentTime = Date(timeIntervalSinceReferenceDate: Double(i) * 30)
            pool.update(snapshot: makePerPlatformSnapshot([
                "claude_code": makeSnapshot(state: .implementing, updated: "2026-06-28T09:00:00.000Z"),
                "cursor": makeSnapshot(state: .idle, updated: "2026-06-28T09:01:00.000Z"),
            ]))
        }
        XCTAssertTrue(
            pool.activeOrigins.contains("claude_code"),
            "an actively-working origin must not idle-dismiss even after many TTLs of wall time"
        )
    }

    func testLastActiveWindowNeverDismissedRegardlessOfTTL() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(ttlSeconds: 5) },
            windowFactory: { _, _ in StubWindowController() },
            now: { currentTime }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertEqual(pool.activeOrigins, ["claude_code"])

        // Advance well past TTL
        currentTime = currentTime.addingTimeInterval(3600)
        pool.update(snapshot: makePerPlatformSnapshot([:]))

        XCTAssertEqual(pool.activeOrigins, ["claude_code"], "last-active window must never be dismissed by TTL")
    }

    // MARK: - Combined mode

    func testCombinedModeOriginsFoldIntoSingleSharedWindow() {
        var createdKeys: [String] = []
        let pool = FloatingPetWindowPool(
            customizationReader: {
                makeCustomization(platformModes: ["claude_code": .combined, "cursor": .combined])
            },
            windowFactory: { origin, _ in
                createdKeys.append(origin)
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ])
        pool.update(snapshot: snap)

        XCTAssertEqual(pool.activeOrigins.count, 1, "two combined-mode origins must fold to one window")
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code") || pool.activeOrigins.contains("cursor"),
            "combined-mode origins must not own their own window"
        )
    }

    func testCombinedWindowSurvivesTTLWhenLastActive() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            customizationReader: {
                makeCustomization(platformModes: ["claude_code": .combined, "cursor": .combined], ttlSeconds: 60)
            },
            windowFactory: { _, _ in StubWindowController() },
            now: { currentTime }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertTrue(pool.activeOrigins.contains("combined"), "combined window must be spawned")

        // Advance past TTL and feed empty snapshot
        currentTime = currentTime.addingTimeInterval(3600)
        pool.update(snapshot: makePerPlatformSnapshot([:]))

        XCTAssertTrue(
            pool.activeOrigins.contains("combined"),
            "combined last-active window must not be dismissed by TTL"
        )
    }

    // MARK: - Live mode changes

    func testOwnToCombinedCollapsesPreviousWindowImmediately() {
        var createdKeys: [String] = []
        var customization = makeCustomization()
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { origin, _ in
                createdKeys.append(origin)
                return StubWindowController()
            }
        )
        // Tick 1: claude_code is own-mode → gets its own window
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ]))
        XCTAssertTrue(pool.activeOrigins.contains("claude_code"), "own-mode origin must have own window")

        // Tick 2: claude_code switches to combined → old own window must be gone immediately
        customization = makeCustomization(platformModes: ["claude_code": .combined])
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ]))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "own window must be dismissed immediately when origin switches to combined"
        )
        XCTAssertTrue(
            pool.activeOrigins.contains("combined"),
            "combined window must be spawned for the combined-mode origin"
        )
    }

    func testOwnToOffRemovesWindowBypassingLastActiveImmunity() {
        var customization = makeCustomization()
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() }
        )
        // Tick 1: claude_code is own-mode and the only origin → it is last-active
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ]))
        XCTAssertTrue(pool.activeOrigins.contains("claude_code"), "own-mode origin must have a window")

        // Tick 2: claude_code switches to off → must be removed even though it is last-active
        customization = makeCustomization(platformModes: ["claude_code": .off])
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ]))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "off-mode origin must be removed from render pipeline even when last-active"
        )
        XCTAssertTrue(pool.activeOrigins.isEmpty, "no windows must remain after last-active origin switches to off")
    }

    // MARK: - Off mode

    // MARK: - Live pet swap

    private func maliFixtureDirectory() -> String {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mali")
            .path
    }

    func testReplacePetPerOriginLiveSwapsOnlyThatWindow() throws {
        var stubs: [String: StubWindowController] = [:]
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { origin, _ in
                let c = StubWindowController()
                stubs[origin] = c
                return c
            }
        )
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ]))
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code", "cursor"]))

        let pet = try CodexPet(petDirectory: maliFixtureDirectory())
        pool.replacePet(origin: "claude_code", codexPet: pet, codogotchiPet: nil)

        XCTAssertEqual(stubs["claude_code"]?.replacePetsCallCount, 1,
            "replacePet must live-update the target window")
        XCTAssertEqual(stubs["cursor"]?.replacePetsCallCount, 0,
            "replacePet must not touch other windows")
    }

    func testOffModeOriginNeverAppearsInActiveOrigins() {
        var factoryCalled = false
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(platformModes: ["cursor": .off]) },
            windowFactory: { _, _ in
                factoryCalled = true
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)

        XCTAssertTrue(pool.activeOrigins.isEmpty, "off-mode origin must not appear in activeOrigins")
        XCTAssertFalse(factoryCalled, "window factory must not be called for off-mode origins")
    }

    // MARK: - User-hide persistence

    func testHideDoesNotRespawnOnNextTick() {
        var spawnCount = 0
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { _, _ in
                spawnCount += 1
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertEqual(spawnCount, 1)
        XCTAssertTrue(pool.activeOrigins.contains("cursor"))

        pool.setVisible(false, for: "cursor")
        XCTAssertFalse(pool.activeOrigins.contains("cursor"), "pet must be hidden immediately")
        XCTAssertTrue(pool.hiddenWindowKeys.contains("cursor"), "hidden key must be tracked")

        // Subsequent ticks with the same snapshot must NOT re-spawn the window.
        pool.update(snapshot: snap)
        pool.update(snapshot: snap)
        XCTAssertFalse(pool.activeOrigins.contains("cursor"), "hidden pet must not re-spawn on update ticks")
        XCTAssertEqual(spawnCount, 1, "factory must be called exactly once — no re-spawn while hidden")
    }

    func testShowClearsHiddenFlagAndRespawnsOnNextTick() {
        var spawnCount = 0
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { _, _ in
                spawnCount += 1
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)
        pool.setVisible(false, for: "cursor")
        XCTAssertTrue(pool.hiddenWindowKeys.contains("cursor"))

        pool.setVisible(true, for: "cursor")
        XCTAssertFalse(pool.hiddenWindowKeys.contains("cursor"), "hidden flag must be cleared on show")

        // The next tick should re-spawn since the snapshot is still present.
        pool.update(snapshot: snap)
        XCTAssertTrue(pool.activeOrigins.contains("cursor"), "pet must reappear after setVisible(true) + tick")
        XCTAssertEqual(spawnCount, 2, "factory must be called again after show + tick")
    }

    func testCombinedWindowHideDoesNotRespawnOnNextTick() {
        var spawnCount = 0
        let pool = FloatingPetWindowPool(
            customizationReader: {
                makeCustomization(platformModes: ["claude_code": .combined, "cursor": .combined])
            },
            windowFactory: { _, _ in
                spawnCount += 1
                return StubWindowController()
            }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
        ])
        pool.update(snapshot: snap)
        XCTAssertTrue(pool.activeOrigins.contains("combined"))
        XCTAssertEqual(spawnCount, 1)

        pool.setVisible(false, for: "combined")
        XCTAssertFalse(pool.activeOrigins.contains("combined"))
        XCTAssertTrue(pool.hiddenWindowKeys.contains("combined"))

        pool.update(snapshot: snap)
        pool.update(snapshot: snap)
        XCTAssertFalse(
            pool.activeOrigins.contains("combined"),
            "combined window must not re-spawn while user-hidden"
        )
        XCTAssertEqual(spawnCount, 1)
    }

    // MARK: - P14.05 Per-platform pet routing + combined idle Default badge

    func testTwoOwnOriginsWithDifferentAssignmentsResolveCorrectPetIds() {
        var resolvedPetIds: [String: String] = [:]
        let assignments = AssignmentsSnapshot(
            default: DEFAULT_PET_NAME,
            platformOverrides: ["claude_code": "mali", "cursor": DEFAULT_PET_NAME]
        )
        let pool = FloatingPetWindowPool(
            assignmentsReader: { assignments },
            customizationReader: { makeCustomization() },
            windowFactory: { origin, petId in
                resolvedPetIds[origin] = petId
                return StubWindowController()
            }
        )
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-30T10:00:01.000Z"),
        ]))
        XCTAssertEqual(
            resolvedPetIds["claude_code"], "mali",
            "own-mode origin assigned 'mali' must spawn with petId 'mali'"
        )
        XCTAssertEqual(
            resolvedPetIds["cursor"], DEFAULT_PET_NAME,
            "own-mode origin with no override must fall through to the default petId"
        )
    }

    func testCombinedWindowReceivesDefaultPetId() {
        var resolvedPetIds: [String: String] = [:]
        let assignments = AssignmentsSnapshot(
            default: "mali",
            platformOverrides: ["claude_code": "some-other-pet"]
        )
        let pool = FloatingPetWindowPool(
            assignmentsReader: { assignments },
            customizationReader: {
                makeCustomization(platformModes: ["claude_code": .combined])
            },
            windowFactory: { origin, petId in
                resolvedPetIds[origin] = petId
                return StubWindowController()
            }
        )
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
        ]))
        XCTAssertEqual(
            resolvedPetIds["combined"], "mali",
            "combined window must always resolve the default petId regardless of per-origin overrides"
        )
    }

    func testReplacePetForOneOriginDoesNotAffectOtherWindows() throws {
        var stubs: [String: StubWindowController] = [:]
        let assignments = AssignmentsSnapshot(default: DEFAULT_PET_NAME, platformOverrides: [:])
        let pool = FloatingPetWindowPool(
            assignmentsReader: { assignments },
            customizationReader: { makeCustomization() },
            windowFactory: { origin, _ in
                let c = StubWindowController()
                stubs[origin] = c
                return c
            }
        )
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(updated: "2026-06-30T10:00:01.000Z"),
        ]))
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code", "cursor"]))

        let pet = try CodexPet(petDirectory: maliFixtureDirectory())
        pool.replacePet(origin: "claude_code", codexPet: pet, codogotchiPet: nil)

        XCTAssertEqual(
            stubs["claude_code"]?.replacePetsCallCount, 1,
            "changing one origin's assignment must update only that origin's window"
        )
        XCTAssertEqual(
            stubs["cursor"]?.replacePetsCallCount, 0,
            "changing one origin's assignment must not disturb other windows"
        )
    }

    func testCombinedWindowAppliesDefaultBadgeWhenIdle() {
        var stubs: [String: StubWindowController] = [:]
        let assignments = AssignmentsSnapshot(default: DEFAULT_PET_NAME, platformOverrides: [:])
        let pool = FloatingPetWindowPool(
            assignmentsReader: { assignments },
            customizationReader: {
                makeCustomization(
                    platformModes: ["claude_code": .combined, "cursor": .combined]
                )
            },
            windowFactory: { origin, _ in
                let c = StubWindowController()
                stubs[origin] = c
                return c
            }
        )
        pool.update(snapshot: makePerPlatformSnapshot([
            "claude_code": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:01.000Z"),
        ]))

        XCTAssertTrue(pool.activeOrigins.contains("combined"), "combined window must be present")
        XCTAssertEqual(
            stubs["combined"]?.appliedPlatforms.last,
            "combined",
            "combined window must call applyPlatform('combined') when its winner state is idle to show the ⭐ Default badge"
        )
    }
}

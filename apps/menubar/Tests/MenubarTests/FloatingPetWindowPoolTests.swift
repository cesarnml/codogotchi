import XCTest

@testable import Codogotchi

// MARK: - Test double

@MainActor
private final class StubWindowController: FloatingPetWindowControlling {
    var isFloatingPetVisible: Bool = false
    var appliedStates: [(ActivityState, VisualMode)] = []
    var replacePetsCallCount = 0
    var appliedPlatforms: [String?] = []
    var appliedAttention: [(AttentionPayload?, SourceEvent?)] = []
    var appliedRPGStates: [(Int, Double, Int, Int, Bool)] = []
    var appliedGateBadges: [GateBadgeContent?] = []

    func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
    func apply(state: ActivityState, visualMode: VisualMode) { appliedStates.append((state, visualMode)) }
    func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
        appliedRPGStates.append((halfHearts, levelFraction, level, activeMinutes, hudEnabled))
    }
    func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
        appliedAttention.append((payload, sourceEvent))
    }
    func applyGateBadge(content: GateBadgeContent?) { appliedGateBadges.append(content) }
    func applyPlatform(origin: String?) { appliedPlatforms.append(origin) }
    func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) { replacePetsCallCount += 1 }
}

@MainActor
private final class StubMinimalistPanel: MinimalistPanelManaging {
    var visible = false
    var platformOrigin: String?
    var activityLabel = ""
	var attentionSummary = ""
	var promptSummary = ""
	var rpgApplyCount = 0
	var frameChangeHandler: ((CGRect) -> Void)?
	var gateBadge: GateBadgeContent?

	func show(frame: CGRect) { visible = true }
	func hide() { visible = false }
	func applyPlatform(origin: String?) { platformOrigin = origin }
    func applyActivity(_ state: ActivityState) { activityLabel = state.displayLabel }
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		attentionSummary = payload?.summary ?? ""
	}
	func applyPromptSummary(_ summary: String) { promptSummary = summary }
	func applyBadgeScale(_ scale: Double) {}
	func applyGateBadge(content: GateBadgeContent?) { gateBadge = content }
	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) { frameChangeHandler = handler }
}

// MARK: - Helpers

private func makeSnapshot(
    state: ActivityState = .implementing,
    updated: String,
    sourceEvent: SourceEvent? = nil,
    attention: AttentionPayload? = nil
) -> StateSnapshot {
    StateSnapshot(
        schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
        activityState: state,
        updatedAt: updated,
        sourceEvent: sourceEvent,
        attention: attention
    )
}

private func makePerPlatformSnapshot(
    _ map: [String: StateSnapshot],
    gateBadges: [String: GateBadgeContent] = [:]
) -> PerPlatformSnapshot {
    PerPlatformSnapshot(perPlatform: map, gateBadges: gateBadges, rpgSnapshot: .safeDefault)
}

private func makeCustomization(
    platformModes: [String: PlatformMode] = [:],
    ttlSeconds: Int = 300,
    monochrome: Bool = false,
    combinedMinimalistEnabled: Bool = false,
    minimalistBadgeScale: Double = 1.0,
    sessionPetsEnabled: [String: Bool] = [:]
) -> CustomizationSnapshot {
    CustomizationSnapshot(
        platformModes: platformModes,
        idleDismissTtlSeconds: ttlSeconds,
        menubarIconMonochrome: monochrome,
        combinedMinimalistEnabled: combinedMinimalistEnabled,
        minimalistBadgeScale: minimalistBadgeScale,
        sessionPetsEnabled: sessionPetsEnabled
    )
}

/// Builds the pool input exactly the way `LivePollingDriver` does: a raw
/// per-session map (keyed `origin:session_id`) collapsed through
/// `resolveRenderKeys` for the given customization, with the parallel
/// identity map carried alongside. Fan-out tests must use this so they
/// exercise the real resolver→pool seam rather than hand-built render keys.
private func makeResolvedSnapshot(
    perSession: [String: StateSnapshot],
    customization: CustomizationSnapshot,
    gateBadges: [String: GateBadgeContent] = [:]
) -> PerPlatformSnapshot {
    let resolution = resolveRenderKeys(perSession: perSession, customization: customization)
    return PerPlatformSnapshot(
        perPlatform: resolution.states,
        gateBadges: gateBadges,
        rpgSnapshot: .safeDefault,
        renderKeyIdentities: resolution.identities
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

    // MARK: - Phase 15: per-origin gate badge routing

    /// Own-mode windows must each receive their own origin's gate badge, not
    /// each other's — the pool used to call `applyGateBadge` on no window at
    /// all (dead sink), so this is the regression guard for that gap.
    func testOwnModeWindowsReceiveTheirOwnGateBadge() {
        var stubs: [String: StubWindowController] = [:]
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { origin, _ in
                let c = StubWindowController()
                stubs[origin] = c
                return c
            }
        )
        let claudeBadge = GateBadgeContent(ticketId: "P15.01", gate: "red_tdd")
        let cursorBadge = GateBadgeContent(ticketId: "P15.04", gate: "open_pr")
        pool.update(
            snapshot: makePerPlatformSnapshot(
                [
                    "claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
                    "cursor": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
                ],
                gateBadges: ["claude_code": claudeBadge, "cursor": cursorBadge]
            ))

        XCTAssertEqual(stubs["claude_code"]?.appliedGateBadges.last ?? nil, claudeBadge)
        XCTAssertEqual(stubs["cursor"]?.appliedGateBadges.last ?? nil, cursorBadge)
    }

    /// An origin's gate badge must clear on the tick it disappears — a stale
    /// badge left behind after a delivery context clears would misattribute
    /// the previous ticket to whatever runs next on that platform.
    func testGateBadgeClearsWhenOriginNoLongerHasOne() {
        var stub: StubWindowController!
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { _, _ in
                stub = StubWindowController()
                return stub
            }
        )
        let badge = GateBadgeContent(ticketId: "P15.01", gate: "red_tdd")
        pool.update(
            snapshot: makePerPlatformSnapshot(
                ["claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
                gateBadges: ["claude_code": badge]
            ))
        XCTAssertEqual(stub.appliedGateBadges.last ?? nil, badge)

        pool.update(
            snapshot: makePerPlatformSnapshot(
                ["claude_code": makeSnapshot(updated: "2026-06-28T10:00:01.000Z")],
                gateBadges: [:]
            ))
        XCTAssertEqual(stub.appliedGateBadges.last ?? nil, nil, "badge must clear once the origin's ticket is no longer active")
    }

    /// The combined window's gate badge follows whichever origin is currently
    /// winning the shared pet — mirroring the existing platform-chip precedent
    /// (`applyPlatform`) rather than always showing a fixed origin's ticket.
    func testCombinedWindowGateBadgeFollowsTheWinningOrigin() {
        var stub: StubWindowController!
        let pool = FloatingPetWindowPool(
            customizationReader: {
                makeCustomization(platformModes: ["claude_code": .combined, "cursor": .combined])
            },
            windowFactory: { _, _ in
                stub = StubWindowController()
                return stub
            }
        )
        let cursorBadge = GateBadgeContent(ticketId: "P15.04", gate: "open_pr")
        pool.update(
            snapshot: makePerPlatformSnapshot(
                [
                    "claude_code": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
                    "cursor": makeSnapshot(updated: "2026-06-30T10:00:01.000Z"),
                ],
                gateBadges: [
                    "claude_code": GateBadgeContent(ticketId: "P15.01", gate: "red_tdd"),
                    "cursor": cursorBadge,
                ]
            ))

        XCTAssertEqual(
            stub.appliedGateBadges.last ?? nil, cursorBadge,
            "combined window must badge with the later-updated (winning) origin's ticket")
    }

    /// Minimalist windows must receive gate badges through the same pool path
    /// as Own-mode windows — the pool loop that calls `applyGateBadge` is
    /// shared between the two, so this guards against a future split reintroducing
    /// the gap where only Own-mode windows got badged.
    func testMinimalistWindowReceivesGateBadge() {
        var stub: StubWindowController!
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(platformModes: ["cursor": .minimalist]) },
            windowFactory: { _, _ in StubWindowController() },
            minimalistWindowFactory: { _ in
                stub = StubWindowController()
                return stub
            }
        )
        let badge = GateBadgeContent(ticketId: "P15.04", gate: "open_pr")
        pool.update(
            snapshot: makePerPlatformSnapshot(
                ["cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
                gateBadges: ["cursor": badge]
            ))

        XCTAssertEqual(stub.appliedGateBadges.last ?? nil, badge)
    }

    // MARK: - P14.06 Minimalist mode routing

	func testMinimalistOriginUsesMinimalistFactoryAndLifecycleParity() {
        var petFactoryCalls: [String] = []
        var minimalistFactoryCalls: [String] = []
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        var stubs: [String: StubWindowController] = [:]
        let pool = FloatingPetWindowPool(
            customizationReader: {
                makeCustomization(
                    platformModes: ["codex": .minimalist, "cursor": .own],
                    ttlSeconds: 60
                )
            },
            windowFactory: { origin, _ in
                petFactoryCalls.append(origin)
                let c = StubWindowController()
                stubs[origin] = c
                return c
            },
            minimalistWindowFactory: { origin in
                minimalistFactoryCalls.append(origin)
                let c = StubWindowController()
                stubs[origin] = c
                return c
            },
            now: { currentTime }
        )

        pool.update(snapshot: makePerPlatformSnapshot([
            "codex": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:01.000Z"),
        ]))

        XCTAssertEqual(minimalistFactoryCalls, ["codex"])
        XCTAssertEqual(petFactoryCalls, ["cursor"])
        XCTAssertEqual(Set(pool.activeOrigins), Set(["codex", "cursor"]))
        XCTAssertEqual(stubs["codex"]?.appliedStates.last?.0, .idle)
        XCTAssertEqual(stubs["codex"]?.appliedRPGStates.count, 1, "minimalist windows still receive lifecycle-wide RPG broadcasts")

        pool.setVisible(false, for: "codex")
        XCTAssertFalse(pool.activeOrigins.contains("codex"))
        pool.update(snapshot: makePerPlatformSnapshot([
            "codex": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:01.000Z"),
        ]))
        XCTAssertFalse(pool.activeOrigins.contains("codex"), "hidden minimalist window must not respawn")

        pool.setVisible(true, for: "codex")
        pool.update(snapshot: makePerPlatformSnapshot([
            "codex": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:01.000Z"),
        ]))
        XCTAssertTrue(pool.activeOrigins.contains("codex"), "minimalist show flow must match own windows")

        currentTime = currentTime.addingTimeInterval(61)
        pool.update(snapshot: makePerPlatformSnapshot([
            "codex": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:00.000Z"),
            "cursor": makeSnapshot(state: .idle, updated: "2026-06-30T10:00:01.000Z"),
        ]))
        XCTAssertFalse(pool.activeOrigins.contains("codex"), "non-last-active minimalist idle windows must TTL-dismiss")
		XCTAssertTrue(pool.activeOrigins.contains("cursor"))
	}

	func testOwnToMinimalistTransitionReplacesWindow() {
		// Regression: own→minimalist left the pet window in place because
		// windows[origin] was non-nil and the spawn gate was never entered.
		var petFactoryCalls: [String] = []
		var minimalistFactoryCalls: [String] = []
		var currentMode: PlatformMode = .own
		var stubs: [String: StubWindowController] = [:]

		let pool = FloatingPetWindowPool(
			customizationReader: { makeCustomization(platformModes: ["codex": currentMode]) },
			windowFactory: { origin, _ in
				petFactoryCalls.append(origin)
				let c = StubWindowController()
				stubs[origin] = c
				return c
			},
			minimalistWindowFactory: { origin in
				minimalistFactoryCalls.append(origin)
				let c = StubWindowController()
				stubs[origin] = c
				return c
			}
		)

		// Tick 1: spawns a pet window for "codex" in own mode.
		pool.update(snapshot: makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
		]))
		XCTAssertEqual(petFactoryCalls, ["codex"])
		XCTAssertTrue(minimalistFactoryCalls.isEmpty)

		// Switch to minimalist mode, then tick 2.
		currentMode = .minimalist
		pool.update(snapshot: makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-06-30T10:00:01.000Z"),
		]))
		XCTAssertEqual(minimalistFactoryCalls, ["codex"], "minimalist factory must be called after own→minimalist switch")
		XCTAssertEqual(petFactoryCalls, ["codex"], "pet factory must not be called again after mode switch")
		XCTAssertTrue(pool.activeOrigins.contains("codex"))
	}

	func testMinimalistToOwnTransitionReplacesWindow() {
		// Regression: minimalist→own left the minimalist window in place.
		var petFactoryCalls: [String] = []
		var minimalistFactoryCalls: [String] = []
		var currentMode: PlatformMode = .minimalist
		var stubs: [String: StubWindowController] = [:]

		let pool = FloatingPetWindowPool(
			customizationReader: { makeCustomization(platformModes: ["codex": currentMode]) },
			windowFactory: { origin, _ in
				petFactoryCalls.append(origin)
				let c = StubWindowController()
				stubs[origin] = c
				return c
			},
			minimalistWindowFactory: { origin in
				minimalistFactoryCalls.append(origin)
				let c = StubWindowController()
				stubs[origin] = c
				return c
			}
		)

		// Tick 1: spawns a minimalist window.
		pool.update(snapshot: makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
		]))
		XCTAssertEqual(minimalistFactoryCalls, ["codex"])
		XCTAssertTrue(petFactoryCalls.isEmpty)

		// Switch back to own mode, then tick 2.
		currentMode = .own
		pool.update(snapshot: makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-06-30T10:00:01.000Z"),
		]))
		XCTAssertEqual(petFactoryCalls, ["codex"], "pet factory must be called after minimalist→own switch")
		XCTAssertEqual(minimalistFactoryCalls, ["codex"], "minimalist factory must not be called again after mode switch")
		XCTAssertTrue(pool.activeOrigins.contains("codex"))
	}

	func testMinimalistOriginWithoutMinimalistFactoryDoesNotFallBackToPetWindow() {
		var petFactoryCalls: [String] = []
		let pool = FloatingPetWindowPool(
			customizationReader: {
				makeCustomization(platformModes: ["codex": .minimalist])
			},
			windowFactory: { origin, _ in
				petFactoryCalls.append(origin)
				return StubWindowController()
			}
		)

		pool.update(snapshot: makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-06-30T10:00:00.000Z"),
		]))

		XCTAssertTrue(petFactoryCalls.isEmpty, "minimalist mode must not fall back to the pet/HUD window factory")
		XCTAssertFalse(pool.activeOrigins.contains("codex"), "minimalist mode without a factory must fail closed")
	}

	// MARK: - P15.04 Per-session window fan-out

	/// (1) Session-pets on: each active `origin:session_id` gets its own window,
	/// every session window resolves the ORIGIN's assigned pet (the session id
	/// must not leak into pet resolution), and the platform chip is applied to
	/// the session window itself, not looked up under the bare origin key.
	func testSessionPetsOnFansOutOneWindowPerActiveSession() {
		var createdPetIds: [String: String] = [:]
		var stubs: [String: StubWindowController] = [:]
		let assignments = AssignmentsSnapshot(
			default: DEFAULT_PET_NAME,
			platformOverrides: ["claude_code": "mali"]
		)
		let customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		let pool = FloatingPetWindowPool(
			assignmentsReader: { assignments },
			customizationReader: { customization },
			windowFactory: { key, petId in
				createdPetIds[key] = petId
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)
		let sourceEvent = SourceEvent(origin: "claude_code", kind: "hook", name: "Claude Code")
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z", sourceEvent: sourceEvent),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z", sourceEvent: sourceEvent),
			],
			customization: customization
		))

		XCTAssertEqual(
			Set(pool.activeOrigins), Set(["claude_code:s1", "claude_code:s2"]),
			"session-pets on must spawn one window per active session, keyed origin:session_id"
		)
		XCTAssertEqual(
			createdPetIds["claude_code:s1"], "mali",
			"session windows must resolve the pet by ORIGIN — the session id must not defeat the override"
		)
		XCTAssertEqual(createdPetIds["claude_code:s2"], "mali")
		XCTAssertEqual(
			stubs["claude_code:s1"]?.appliedPlatforms.last ?? nil, "claude_code",
			"the platform chip must land on the session window itself"
		)
		XCTAssertEqual(stubs["claude_code:s2"]?.appliedPlatforms.last ?? nil, "claude_code")
	}

	/// (2) Session-pets off: two sessions for one origin collapse to a single
	/// plain-origin window — byte-identical to pre-Phase-15 behavior.
	func testSessionPetsOffCollapsesSessionsToOneOriginWindow() {
		var created: [String] = []
		let customization = makeCustomization()
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				created.append(key)
				return StubWindowController()
			}
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(pool.activeOrigins, ["claude_code"], "session-pets off must fold sessions to the plain origin key")
		XCTAssertEqual(created, ["claude_code"], "exactly one window must spawn for the collapsed origin")
	}

	/// (3) Per-session TTL: an idle session past the TTL is dismissed while a
	/// still-working sibling session on the same origin survives — the TTL
	/// clock and dismissal operate on the resolved key, not the origin.
	func testIdleSessionAgesOutWhileActiveSiblingSessionSurvives() {
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let customization = makeCustomization(ttlSeconds: 60, sessionPetsEnabled: ["claude_code": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() },
			now: { currentTime }
		)
		let perSession = [
			"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
			"claude_code:busy-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
		]
		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization))
		XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code:idle-one", "claude_code:busy-one"]))

		currentTime = currentTime.addingTimeInterval(61)
		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization))

		XCTAssertEqual(
			pool.activeOrigins, ["claude_code:busy-one"],
			"only the idle session past TTL is dismissed; the active sibling session must survive"
		)
	}

	/// (4) Combined mode with two sessions still folds to one "combined" window,
	/// even with session-pets enabled for the origin, and keeps the combined
	/// window's idle ⭐ Default badge behavior (`applyPlatform("combined")`).
	func testCombinedModeWithTwoSessionsFoldsToSingleCombinedWindow() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(
			platformModes: ["claude_code": .combined],
			sessionPetsEnabled: ["claude_code": true]
		)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(pool.activeOrigins, ["combined"], "combined mode must fold all sessions to the single shared window")
		XCTAssertEqual(
			stubs["combined"]?.appliedPlatforms.last ?? nil, "combined",
			"the folded combined window must keep the idle ⭐ Default badge behavior"
		)
	}

	/// (5) own→minimalist toggle tears down and respawns the correct controller
	/// type for EACH of that platform's session windows without resetting other
	/// platforms' windows.
	func testOwnToMinimalistRespawnsEachSessionWindowWithoutResettingOthers() {
		var petFactoryCalls: [String] = []
		var minimalistFactoryCalls: [String] = []
		var currentModes: [String: PlatformMode] = ["codex": .own]
		var stubs: [String: StubWindowController] = [:]
		let customization: () -> CustomizationSnapshot = {
			makeCustomization(
				platformModes: currentModes,
				sessionPetsEnabled: ["codex": true]
			)
		}
		let pool = FloatingPetWindowPool(
			customizationReader: customization,
			windowFactory: { key, _ in
				petFactoryCalls.append(key)
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			minimalistWindowFactory: { key in
				minimalistFactoryCalls.append(key)
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)
		let perSession = [
			"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			"codex:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			"cursor:main": makeSnapshot(updated: "2026-07-01T10:00:02.000Z"),
		]
		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization()))
		XCTAssertEqual(Set(petFactoryCalls), Set(["codex:s1", "codex:s2", "cursor"]))
		XCTAssertTrue(minimalistFactoryCalls.isEmpty)
		let cursorStubBeforeToggle = stubs["cursor"]

		currentModes["codex"] = .minimalist
		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization()))

		XCTAssertEqual(
			Set(minimalistFactoryCalls), Set(["codex:s1", "codex:s2"]),
			"each codex session window must respawn through the minimalist factory after the toggle"
		)
		XCTAssertEqual(
			Set(petFactoryCalls), Set(["codex:s1", "codex:s2", "cursor"]),
			"the pet factory must not run again for the toggled platform or for cursor"
		)
		XCTAssertTrue(
			stubs["cursor"] === cursorStubBeforeToggle,
			"toggling codex must not tear down or respawn cursor's window"
		)
		XCTAssertEqual(Set(pool.activeOrigins), Set(["codex:s1", "codex:s2", "cursor"]))
	}

	/// Review-focus guard: a pet reassignment for an origin live-swaps ALL of
	/// that origin's session windows and leaves other platforms untouched.
	func testReplacePetLiveSwapsAllSessionWindowsOfTheOrigin() throws {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"codex:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
				"cursor:main": makeSnapshot(updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), Set(["codex:s1", "codex:s2", "cursor"]))

		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		pool.replacePet(origin: "codex", codexPet: pet, codogotchiPet: nil)

		XCTAssertEqual(
			stubs["codex:s1"]?.replacePetsCallCount, 1,
			"replacePet must live-swap every session window of the target origin"
		)
		XCTAssertEqual(stubs["codex:s2"]?.replacePetsCallCount, 1)
		XCTAssertEqual(
			stubs["cursor"]?.replacePetsCallCount, 0,
			"replacePet must not touch other platforms' windows"
		)
	}
}

final class PromptAttentionReaderTests: XCTestCase {
    func testNewestEntryForOriginPrefixWinsAndOtherOriginsAreIgnored() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptAttentionReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("prompt-attention.json")
        let json = """
            {
              "by_session": {
                "codex:older": {
                  "updated_at": "2026-06-30T09:00:00.000Z",
                  "summary": "older codex prompt"
                },
                "cursor:newer-but-wrong-origin": {
                  "updated_at": "2026-06-30T11:00:00.000Z",
                  "summary": "cursor prompt"
                },
                "codex:newer": {
                  "updated_at": "2026-06-30T10:00:00.000Z",
                  "summary": "newer codex prompt"
                }
              }
            }
            """
        try json.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(PromptAttentionReader.latestSummary(origin: "codex", at: url.path), "newer codex prompt")
    }

	func testAbsentOrMalformedFileReturnsEmptySummary() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-prompt-attention-\(UUID().uuidString).json")
        XCTAssertEqual(PromptAttentionReader.latestSummary(origin: "codex", at: missing.path), "")

        let malformed = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-prompt-attention-\(UUID().uuidString).json")
        try "{".write(to: malformed, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: malformed) }
		XCTAssertEqual(PromptAttentionReader.latestSummary(origin: "codex", at: malformed.path), "")
	}

	func testUnparseableTimestampForMatchingOriginReturnsEmptySummary() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("PromptAttentionReaderTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let url = dir.appendingPathComponent("prompt-attention.json")
		let json = """
			{
			  "by_session": {
			    "codex:bad-date": {
			      "updated_at": "not-a-date",
			      "summary": "must not surface"
			    }
			  }
			}
			"""
		try json.write(to: url, atomically: true, encoding: .utf8)

		XCTAssertEqual(PromptAttentionReader.latestSummary(origin: "codex", at: url.path), "")
	}
}

@MainActor
final class MinimalistWindowControllerTests: XCTestCase {
	func testAppliesPlatformAnimationAttentionAndLatestPromptSummary() {
        let panel = StubMinimalistPanel()
        let controller = MinimalistWindowController(
            origin: "codex",
            panel: panel,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 800, height: 600) },
            saveState: { _ in },
            initialState: FloatingAppState(
                isFloatingPetVisible: false,
                frame: CGRect(x: 20, y: 20, width: 240, height: 64),
                onboardingCompletedAt: nil,
                lastHookActivityAt: nil,
                hooksStatus: nil,
                installedHookVersion: nil
            ),
            promptSummaryProvider: { origin in
                origin == "codex" ? "Refactor the renderer" : ""
            }
        )

        controller.setFloatingPetVisible(true)
        controller.apply(state: .testing, visualMode: .normal)
        controller.applyAttention(
            payload: AttentionPayload(
                createdAt: "2026-06-30T10:00:00.000Z",
                expiresAt: "2099-01-01T00:00:00.000Z",
                summary: "needs focus",
                reasonKind: "waiting"
            ),
            sourceEvent: SourceEvent(origin: "codex", kind: "hook", name: "Codex")
        )
        controller.applyPlatform(origin: "codex")
        controller.applyRPGState(halfHearts: 0, levelFraction: 0.5, level: 2, activeMinutes: 12, hudEnabled: true)

        XCTAssertEqual(panel.visible, true)
        XCTAssertEqual(panel.platformOrigin, "codex")
        XCTAssertEqual(panel.activityLabel, "Testing")
        XCTAssertEqual(panel.attentionSummary, "needs focus")
		XCTAssertEqual(panel.promptSummary, "Refactor the renderer")
		XCTAssertEqual(panel.rpgApplyCount, 0, "minimalist window must not render RPG HUD state")
	}

	func testPersistsCommittedFrameChanges() {
		let panel = StubMinimalistPanel()
		var savedStates: [FloatingAppState] = []
		let controller = MinimalistWindowController(
			origin: "codex",
			panel: panel,
			visibleFrameProvider: { CGRect(x: 0, y: 0, width: 800, height: 600) },
			saveState: { savedStates.append($0) },
			initialState: FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 20, y: 20, width: 240, height: 64),
				onboardingCompletedAt: nil,
				lastHookActivityAt: nil,
				hooksStatus: nil,
				installedHookVersion: nil
			),
			promptSummaryProvider: { _ in "" }
		)

		panel.frameChangeHandler?(CGRect(x: 300, y: 320, width: 360, height: 58))

		XCTAssertTrue(controller.isFloatingPetVisible)
		XCTAssertEqual(savedStates.last?.frame.origin.x, 300)
		XCTAssertEqual(savedStates.last?.frame.origin.y, 320)
	}
}

import XCTest

@testable import Codogotchi

// MARK: - Test double

@MainActor
private final class StubWindowController: FloatingPetWindowControlling {
    var isFloatingPetVisible: Bool = false
    var appliedStates: [(ActivityState, VisualMode)] = []

    func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
    func apply(state: ActivityState, visualMode: VisualMode) { appliedStates.append((state, visualMode)) }
    func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
    func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
    func applyGateBadge(content: GateBadgeContent?) {}
    func applyPlatform(origin: String?) {}
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

// MARK: - Test suite

@MainActor
final class FloatingPetWindowPoolTests: XCTestCase {

    // MARK: - Spawn / activeOrigins

    func testTwoOriginSnapshotSpawnsTwoWindows() {
        var created: [String] = []
        let pool = FloatingPetWindowPool(
            ttlSeconds: 300,
            platformModes: [:],
            windowFactory: { origin in
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
            ttlSeconds: 60,
            platformModes: [:],
            windowFactory: { origin in
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

    func testLastActiveWindowNeverDismissedRegardlessOfTTL() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 0)
        let pool = FloatingPetWindowPool(
            ttlSeconds: 5,
            platformModes: [:],
            windowFactory: { _ in StubWindowController() },
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
            ttlSeconds: 300,
            platformModes: ["claude_code": "combined", "cursor": "combined"],
            windowFactory: { origin in
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
            ttlSeconds: 60,
            platformModes: ["claude_code": "combined", "cursor": "combined"],
            windowFactory: { _ in StubWindowController() },
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

    // MARK: - Off mode

    func testOffModeOriginNeverAppearsInActiveOrigins() {
        var factoryCalled = false
        let pool = FloatingPetWindowPool(
            ttlSeconds: 300,
            platformModes: ["cursor": "off"],
            windowFactory: { _ in
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
}

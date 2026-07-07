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
    var appliedSessionNumbers: [Int?] = []
    var appliedSessionLabels: [String?] = []
    var appliedSessionTooltips: [String?] = []
    var appliedConflictBubbles: [ConflictBubblePayload?] = []
    /// Settable so a test can simulate "this window is currently at frame X"
    /// before the pool reads it via `currentFrame` at eviction time.
    var currentFrame: CGRect = .zero
    var adoptedFrames: [CGRect] = []
    var appliedIdleEscalationConfigs: [IdleEscalationConfig] = []

    func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
    func adoptFrame(_ frame: CGRect) {
        adoptedFrames.append(frame)
        currentFrame = frame
    }
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
    func applySessionNumber(_ number: Int?) { appliedSessionNumbers.append(number) }
    func applySessionLabel(_ label: String?) { appliedSessionLabels.append(label) }
    func applySessionTooltip(_ summary: String?) { appliedSessionTooltips.append(summary) }
    func applyConflictBubble(_ payload: ConflictBubblePayload?) { appliedConflictBubbles.append(payload) }
    func updateIdleEscalationConfig(_ config: IdleEscalationConfig) { appliedIdleEscalationConfigs.append(config) }
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
	var sessionNumber: Int?
	var sessionLabel: String?
	var sessionTooltip: String?

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
	func applySessionNumber(_ number: Int?) { sessionNumber = number }
	func applySessionLabel(_ label: String?) { sessionLabel = label }
	func applySessionTooltip(_ summary: String?) { sessionTooltip = summary }
	func applyConflictBubble(_ payload: ConflictBubblePayload?) {}
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
    sessionPetsEnabled: [String: Bool] = [:],
    sessionCap: [String: Int] = [:],
    idleImpatientSeconds: Int = 300,
    idleFrustratedSeconds: Int = 600,
    evictSessionPetsEnabled: Bool = true
) -> CustomizationSnapshot {
    CustomizationSnapshot(
        platformModes: platformModes,
        idleDismissTtlSeconds: ttlSeconds,
        menubarIconMonochrome: monochrome,
        combinedMinimalistEnabled: combinedMinimalistEnabled,
        minimalistBadgeScale: minimalistBadgeScale,
        sessionPetsEnabled: sessionPetsEnabled,
        sessionCap: sessionCap,
        idleImpatientSeconds: idleImpatientSeconds,
        idleFrustratedSeconds: idleFrustratedSeconds,
        evictSessionPetsEnabled: evictSessionPetsEnabled
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

    /// Phase-15 QC regression: app starts already in Combined mode for the
    /// origin, then the user switches to Own — with the SAME `updated_at` on
    /// both ticks (no new agent activity between the settings toggle, the
    /// common case when a developer just flips the mode picker). Before this
    /// fix, Step 8's else-branch gated the "combined" dismissal on
    /// last-active immunity even when no origin was combined-mode anymore:
    /// the freshly-added "claude_code" render key and the stale "combined"
    /// entry tie in `lastUpdatedAt`, and Swift's `max(by:)` tie-break is
    /// Dictionary-iteration-order dependent, so "combined" could
    /// nondeterministically win last-active and never be dismissed —
    /// verified flaky (2/3 runs) against the pre-fix code.
    func testCombinedToOwnDismissesCombinedEvenOnTimestampTie() {
        var customization = makeCustomization(platformModes: ["claude_code": .combined])
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() }
        )
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(pool.activeOrigins, ["combined"])

        customization = makeCustomization(platformModes: ["claude_code": .own])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(
            pool.activeOrigins, ["claude_code"],
            "combined window must be dismissed when its only origin switches to own, even on a timestamp tie"
        )
    }

    /// Same regression as above, for Combined → Minimalist.
    func testCombinedToMinimalistDismissesCombinedEvenOnTimestampTie() {
        var customization = makeCustomization(platformModes: ["claude_code": .combined])
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() },
            minimalistWindowFactory: { _ in StubWindowController() }
        )
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(pool.activeOrigins, ["combined"])

        customization = makeCustomization(platformModes: ["claude_code": .minimalist])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(
            pool.activeOrigins, ["claude_code"],
            "combined window must be dismissed when its only origin switches to minimalist, even on a timestamp tie"
        )
    }

    /// Phase-15 QC regression: same transition as
    /// `testOwnToCombinedCollapsesPreviousWindowImmediately` above, but fed
    /// the PRE-FOLDED shape the production driver actually emits since
    /// P15.03 — `resolveRenderKeys` folds a combined-mode origin to the
    /// literal "combined" key BEFORE the pool sees the snapshot, so the
    /// origin's own key never reappears and teardown must be driven by the
    /// pool's own window bookkeeping, not snapshot keys.
    func testOwnToCombinedCollapsesPreviousWindowWithPreFoldedSnapshot() {
        var customization = makeCustomization()
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() }
        )
        // Tick 1: own mode, session-pets off → resolver folds to plain "claude_code"
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(pool.activeOrigins, ["claude_code"])

        // Tick 2: switch to combined → resolver pre-folds to the literal "combined"
        // key; the plain "claude_code" key never appears in the snapshot again.
        customization = makeCustomization(platformModes: ["claude_code": .combined])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:01.000Z")],
            customization: customization
        ))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "stale own window must be dismissed immediately even though its key is absent from the pre-folded snapshot"
        )
        XCTAssertEqual(pool.activeOrigins, ["combined"])
    }

    /// Phase-15 QC regression: minimalist→combined with the pre-folded shape.
    /// Steps 5a/6b only inspect snapshot keys, so the stale minimalist window
    /// must be caught by the same window-keyed collapse as own→combined.
    func testMinimalistToCombinedCollapsesPreviousWindowWithPreFoldedSnapshot() {
        var customization = makeCustomization(platformModes: ["claude_code": .minimalist])
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() },
            minimalistWindowFactory: { _ in StubWindowController() }
        )
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(pool.activeOrigins, ["claude_code"])

        customization = makeCustomization(platformModes: ["claude_code": .combined])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:01.000Z")],
            customization: customization
        ))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "stale minimalist window must be dismissed immediately when its origin switches to combined"
        )
        XCTAssertEqual(pool.activeOrigins, ["combined"])
    }

    /// Phase-15 QC regression: enabling Session Pets for an Own-mode origin
    /// (with no sessions before) must dismiss the plain-origin window. The
    /// plain "claude_code" key vanishes from the snapshot entirely once
    /// sessionPetsEnabled flips on (resolveRenderKeys now emits
    /// "claude_code:sess-N" keys instead), so no existing teardown branch's
    /// precondition — which all key off snapshot presence under the SAME
    /// string, or off mode changes — is ever met without this fix.
    func testEnablingSessionPetsDismissesPlainOriginWindow() {
        var customization = makeCustomization()
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() }
        )
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")],
            customization: customization
        ))
        XCTAssertEqual(pool.activeOrigins, ["claude_code"])

        customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: [
                "claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
                "claude_code:sess-2": makeSnapshot(updated: "2026-06-28T10:00:01.000Z"),
            ],
            customization: customization
        ))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code"),
            "stale plain-origin window must be dismissed when session-pets turns on for its origin"
        )
        XCTAssertEqual(
            Set(pool.activeOrigins), Set(["claude_code:sess-1", "claude_code:sess-2"]),
            "session-keyed windows must spawn for the newly-visible sessions"
        )
    }

    /// Phase-15 QC regression: disabling Session Pets for an Own-mode origin
    /// must dismiss every now-stale session-keyed window (the reverse of the
    /// test above). The session-keyed keys vanish from the snapshot entirely
    /// once sessionPetsEnabled flips off (resolveRenderKeys now folds to the
    /// plain "claude_code" key), so the same class of gap applies in reverse.
    func testDisablingSessionPetsDismissesSessionKeyedWindows() {
        var customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
        let pool = FloatingPetWindowPool(
            customizationReader: { customization },
            windowFactory: { _, _ in StubWindowController() }
        )
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: [
                "claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
                "claude_code:sess-2": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
            ],
            customization: customization
        ))
        XCTAssertEqual(Set(pool.activeOrigins), Set(["claude_code:sess-1", "claude_code:sess-2"]))

        customization = makeCustomization(sessionPetsEnabled: ["claude_code": false])
        pool.update(snapshot: makeResolvedSnapshot(
            perSession: ["claude_code:sess-1": makeSnapshot(updated: "2026-06-28T10:00:01.000Z")],
            customization: customization
        ))
        XCTAssertFalse(
            pool.activeOrigins.contains("claude_code:sess-1"),
            "stale session-keyed windows must be dismissed when session-pets turns off for their origin"
        )
        XCTAssertFalse(pool.activeOrigins.contains("claude_code:sess-2"))
        XCTAssertEqual(
            pool.activeOrigins, ["claude_code"],
            "plain-origin window must spawn once session-pets is off"
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

    func testSetVisibleWritesThroughToInjectedSaver() {
        var savedCalls: [Set<String>] = []
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { _, _ in StubWindowController() },
            hiddenKeysSaver: { savedCalls.append($0) }
        )
        let snap = makePerPlatformSnapshot([
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)

        pool.setVisible(false, for: "cursor")
        XCTAssertEqual(savedCalls.last, ["cursor"], "hiding must write-through the full hidden set")

        pool.setVisible(true, for: "cursor")
        XCTAssertEqual(savedCalls.last, [], "showing must write-through the cleared hidden set")
    }

    func testInitRestoresHiddenKeysFromInjectedLoader() {
        var spawnCount = 0
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization() },
            windowFactory: { _, _ in
                spawnCount += 1
                return StubWindowController()
            },
            hiddenKeysLoader: { ["cursor"] }
        )

        XCTAssertTrue(pool.hiddenWindowKeys.contains("cursor"), "persisted hidden key must be restored at init")

        let snap = makePerPlatformSnapshot([
            "cursor": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)

        XCTAssertFalse(
            pool.activeOrigins.contains("cursor"),
            "a pet restored as hidden must not spawn on the first tick after relaunch"
        )
        XCTAssertEqual(spawnCount, 0)
    }

    func testInitRestoredHiddenKeyForExpiredSessionIsHarmlessAndUnseenSiblingDefaultsVisible() {
        var spawnedKeys: [String] = []
        let pool = FloatingPetWindowPool(
            customizationReader: { makeCustomization(ttlSeconds: 60, sessionPetsEnabled: ["claude_code": true]) },
            windowFactory: { key, _ in
                spawnedKeys.append(key)
                return StubWindowController()
            },
            // "claude_code:stale" was hidden in a previous run and has since
            // TTL-expired out of state.d/ entirely — it must never reappear or
            // otherwise affect the render queue. "claude_code:s2" is a brand
            // new session never seen before restart and must default visible.
            hiddenKeysLoader: { ["claude_code:stale"] }
        )
        let snap = makePerPlatformSnapshot([
            "claude_code:s2": makeSnapshot(updated: "2026-06-28T10:00:00.000Z"),
        ])
        pool.update(snapshot: snap)

        XCTAssertTrue(pool.activeOrigins.contains("claude_code:s2"), "unseen session must default visible")
        XCTAssertEqual(spawnedKeys, ["claude_code:s2"], "expired persisted-hidden key must not be spawned or interfered with")
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

	func testEnablingSessionPetsGrandfathersThePreviousPlainWindowsFrame() {
		var stubs: [String: StubWindowController] = [:]
		var customization = makeCustomization()
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1: session-pets off — a single plain-origin window renders.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:winner": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code"])
		let previousFrame = CGRect(x: 42, y: 84, width: 160, height: 160)
		stubs["claude_code"]?.currentFrame = previousFrame

		// Tick 2: session-pets toggles on for claude_code — the plain window
		// collapses (Step 6a2) and the grandfathered session window spawns in
		// its place (Step 7); it must inherit the collapsed window's exact
		// slot instead of the default spawn position.
		customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:winner": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")
			],
			customization: customization
		))

		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:winner"])
		XCTAssertEqual(
			stubs["claude_code:winner"]?.adoptedFrames, [previousFrame],
			"the grandfathered session window must inherit the collapsed plain window's exact frame")
	}

	func testDisablingSessionPetsDoesNotInheritAnySessionWindowsFrame() {
		var stubs: [String: StubWindowController] = [:]
		var customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1: session-pets on — two session windows render.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:s1", "claude_code:s2"])
		stubs["claude_code:s1"]?.currentFrame = CGRect(x: 10, y: 10, width: 160, height: 160)
		stubs["claude_code:s2"]?.currentFrame = CGRect(x: 20, y: 20, width: 160, height: 160)

		// Tick 2: session-pets toggles off — both collapse into one new plain
		// window, which is deliberately left at the default spawn position:
		// there is no single unambiguous sibling frame to inherit from.
		customization = makeCustomization()
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code"])
		XCTAssertTrue(
			stubs["claude_code"]?.adoptedFrames.isEmpty ?? true,
			"disabling session-pets must not inherit either sibling session's frame — only the "
				+ "enabling direction inherits from a single unambiguous predecessor window")
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

	// MARK: - P15.07 session-cap selection, promotion, prune

	/// (7) Same as `testIdleSessionAgesOutWhileActiveSiblingSessionSurvives`
	/// above, plus the P15.07 nuance: TTL-dismissing one session must release
	/// only that session's free-list number, leaving its still-live sibling's
	/// number untouched.
	func testSessionKeyedTTLDismissesOneSessionWithoutRenumberingItsSibling() {
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
		let survivorNumberBefore = pool.sessionNumber(forWindowKey: "claude_code:busy-one")

		currentTime = currentTime.addingTimeInterval(61)
		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization))

		XCTAssertEqual(
			pool.activeOrigins, ["claude_code:busy-one"],
			"only the idle session past TTL is dismissed; the active sibling session must survive")
		XCTAssertEqual(
			pool.sessionNumber(forWindowKey: "claude_code:busy-one"), survivorNumberBefore,
			"dismissing the idle sibling must not renumber the still-live session")
	}

	/// (1) Cap pressure holds the idle session and renders both active ones.
	func testSessionCapHoldsIdleSessionWhileTwoActiveSessionsRender() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)
		let perSession = [
			"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
			"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			"claude_code:active-two": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:02.000Z"),
		]

		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization))

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-one", "claude_code:active-two"],
			"cap 2 must render only the two active sessions, holding the idle one")
	}

	// MARK: - "Evict Session Pets" kill-switch

	func testEvictSessionPetsDisabledProtectsAnIdleIncumbentFromANewcomer() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2],
			evictSessionPetsEnabled: false)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)

		// Tick 1: one idle + one active session both render (cap 2, exactly full).
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-one", "claude_code:active-one"])

		// Tick 2: a 3rd (in-flight) session arrives — with eviction disabled the
		// idle incumbent must survive; the newcomer stays pending instead.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:newcomer": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:idle-one", "claude_code:active-one"],
			"Evict Session Pets disabled must protect the idle incumbent — the newcomer stays pending")
	}

	// MARK: - Live Idle Escalation Timing propagation

	// Note: `windowFactory` (in production, `MenubarApp`) resolves the current
	// customization directly at construction time, so a freshly-spawned real
	// window always starts current. The pool's diff-push mechanism exercised
	// here only needs to reach windows that were ALREADY open before a
	// Settings change — `StubWindowController` (unlike the real controller)
	// takes no config at construction, so these tests only assert the push
	// that happens on ticks after the window already exists.
	func testIdleEscalationConfigChangeIsPushedToAlreadyOpenWindows() {
		var stubs: [String: StubWindowController] = [:]
		var customization = makeCustomization(idleImpatientSeconds: 300, idleFrustratedSeconds: 600)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1: spawns the window under the initial config.
		pool.update(snapshot: makePerPlatformSnapshot([
			"claude_code": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z")
		]))
		let stub = stubs["claude_code"]!

		// Tick 2: Settings change — bump both thresholds while the window stays open.
		customization = makeCustomization(idleImpatientSeconds: 1800, idleFrustratedSeconds: 3600)
		pool.update(snapshot: makePerPlatformSnapshot([
			"claude_code": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z")
		]))

		XCTAssertEqual(
			stub.appliedIdleEscalationConfigs.last,
			IdleEscalationConfig(impatientAfter: 1800, frustratedAfter: 3600),
			"a changed customization must be pushed to the already-open window")
	}

	func testUnchangedIdleEscalationConfigIsNotRePushedEveryTick() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(idleImpatientSeconds: 300, idleFrustratedSeconds: 600)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1 spawns the window; tick 2 keeps the same (unchanged) config.
		pool.update(snapshot: makePerPlatformSnapshot([
			"claude_code": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z")
		]))
		pool.update(snapshot: makePerPlatformSnapshot([
			"claude_code": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z")
		]))

		XCTAssertEqual(
			stubs["claude_code"]?.appliedIdleEscalationConfigs.count, 0,
			"an unchanged config must never be pushed to a window that already started current")
	}

	// MARK: - P15.07 evicted-session frame inheritance

	func testEvictedSessionFrameIsInheritedByTheIncomingActiveSession() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1: a single idle session renders (cap 1, only one session exists).
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-one"])
		let evictedFrame = CGRect(x: 111, y: 222, width: 140, height: 140)
		stubs["claude_code:idle-one"]?.currentFrame = evictedFrame

		// Tick 2: a new in-flight session arrives; cap 1 evicts the idle one and
		// promotes the active newcomer into its slot.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-one"],
			"cap 1 must evict the idle session and render only the new active one")
		XCTAssertEqual(
			stubs["claude_code:active-one"]?.adoptedFrames, [evictedFrame],
			"the incoming active session must inherit the evicted session's exact frame and size")
	}

	func testInheritedFrameDoesNotLeakToAnUnrelatedOrigin() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
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
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z")
			],
			customization: customization
		))
		stubs["claude_code:idle-one"]?.currentFrame = CGRect(x: 50, y: 50, width: 140, height: 140)

		// A brand-new session for a DIFFERENT, session-pets-off origin (folds to the
		// plain "cursor" key) appears in the same tick that evicts claude_code's idle
		// session — cursor must not inherit claude_code's freed frame.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"cursor:new": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))

		XCTAssertTrue(
			stubs["cursor"]?.adoptedFrames.isEmpty ?? true,
			"an unrelated origin's newcomer must not inherit another origin's evicted frame")
	}

	func testEvictedSessionFramesQueueAcrossMultipleEvictionsInTheSameTick() {
		var stubs: [String: StubWindowController] = [:]
		var customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 3])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)

		// Tick 1: three idle sessions render under cap 3.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-b": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(
			Set(pool.activeOrigins),
			["claude_code:idle-a", "claude_code:idle-b", "claude_code:idle-c"])
		let frameA = CGRect(x: 10, y: 10, width: 140, height: 140)
		let frameB = CGRect(x: 20, y: 20, width: 140, height: 140)
		stubs["claude_code:idle-a"]?.currentFrame = frameA
		stubs["claude_code:idle-b"]?.currentFrame = frameB

		// Tick 2: cap drops to 1 in one settings change — evicts idle-a and
		// idle-b simultaneously (idle-c, the most recently updated, wins the
		// tie-break and stays rendered). Both evicted frames must survive,
		// not just the last one captured by the pending-set loop.
		customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 1])
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-b": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-c"])

		// Tick 3: cap is raised back up and two new active sessions arrive at
		// once — each must inherit a DISTINCT evicted frame, not the same one
		// twice and not the default spot.
		customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 3])
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-c": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
				"claude_code:new-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:05:00.000Z"),
				"claude_code:new-two": makeSnapshot(state: .implementing, updated: "2026-07-01T10:05:01.000Z"),
			],
			customization: customization
		))

		let newOneFrame = stubs["claude_code:new-one"]?.adoptedFrames.first
		let newTwoFrame = stubs["claude_code:new-two"]?.adoptedFrames.first
		let gotBothFramesInEitherOrder =
			(newOneFrame == frameA && newTwoFrame == frameB)
			|| (newOneFrame == frameB && newTwoFrame == frameA)
		XCTAssertTrue(
			gotBothFramesInEitherOrder,
			"both newly-spawned sessions must inherit the two previously-evicted frames between "
				+ "them (got \(String(describing: newOneFrame)) and "
				+ "\(String(describing: newTwoFrame))) — not lose one to the single-slot overwrite bug")
	}

	/// (3, revised by P15.07-QC) A held idle session must NOT be promoted when
	/// a manual Prune frees its slot: pruning arms the origin so only an
	/// in-flight newcomer may claim the freed slot going forward this app
	/// session — a standby/idle session merely held by cap pressure is not
	/// what the user asked to see appear in the pruned pet's place.
	func testHeldIdleSessionIsNotPromotedWhenAManualPruneFreesItsSlot() {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("pool-prune-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		func writeSlice(_ name: String, state: String, updatedAt: String) {
			try! """
				{ "activity_state": "\(state)", "updated_at": "\(updatedAt)", "source_event": { "origin": "claude_code" } }
				""".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}
		writeSlice("claude_code:idle-one.json", state: "idle", updatedAt: "2026-07-01T10:00:00.000Z")
		writeSlice("claude_code:active-one.json", state: "implementing", updatedAt: "2026-07-01T10:00:01.000Z")
		writeSlice("claude_code:active-two.json", state: "thinking", updatedAt: "2026-07-01T10:00:02.000Z")

		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		func readSnapshot() -> PerPlatformSnapshot {
			guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(at: dir.path)
			else { fatalError("read must succeed") }
			return makeResolvedSnapshot(perSession: perSession, customization: customization)
		}

		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)
		pool.update(snapshot: readSnapshot())
		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-one", "claude_code:active-two"],
			"idle-one must start held pending under cap 2")

		pool.pruneSession(windowKey: "claude_code:active-one", stateDirectory: dir.path)
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("claude_code:active-one.json").path))

		pool.update(snapshot: readSnapshot())

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-two"],
			"the held idle session must stay pending — a manual prune only admits an in-flight newcomer into its freed slot")

		// Once idle-one goes in-flight, it is eligible to claim the still-free slot.
		writeSlice("claude_code:idle-one.json", state: "implementing", updatedAt: "2026-07-01T10:00:03.000Z")
		pool.update(snapshot: readSnapshot())

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:idle-one", "claude_code:active-two"],
			"an in-flight session must still be able to claim a slot freed by a manual prune")
	}

	/// (P15.07-QC) Hiding an idle incumbent must not free its cap slot for a
	/// pending idle sibling to backfill — hide is a pure visibility toggle, not
	/// a cap release, so the sibling stays held exactly as before the hide.
	func testHidingAnIdleIncumbentDoesNotBackfillAPendingIdleSibling() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)

		// Tick 1: idle-one and active-one fill both slots under cap 2.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-one", "claude_code:active-one"])

		// Tick 2: idle-two arrives and is held pending by cap pressure —
		// idle-one keeps its slot as the incumbent.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-one", "claude_code:active-one"])

		// User hides idle-one — its window is torn down immediately.
		pool.setVisible(false, for: "claude_code:idle-one")
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:active-one"])

		// Tick 3: the same three sessions are still present. idle-two must NOT
		// be promoted into idle-one's slot — only active-one should be visible.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-one"],
			"hiding an idle incumbent must not let a pending idle sibling backfill its slot")
	}

	/// (P15.07-QC) Hiding an in-flight incumbent must not free its cap slot for
	/// a pending idle sibling to backfill. In-flight sessions are never
	/// rank-evicted, so the slot stays reserved for the hidden session even
	/// though its window is torn down.
	func testHidingAnInFlightIncumbentDoesNotBackfillAPendingIdleSibling() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)

		// Tick 1: active-one and idle-one fill both slots under cap 2.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:active-one", "claude_code:idle-one"])

		// Tick 2: idle-two arrives and is held pending by cap pressure.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:active-one", "claude_code:idle-one"])

		// User hides the running (in-flight) pet — its window is torn down.
		pool.setVisible(false, for: "claude_code:active-one")
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-one"])

		// Tick 3: idle-two must still not be promoted — active-one's slot stays
		// reserved even though it's concealed, and idle-one is unaffected.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:idle-one"],
			"hiding an in-flight incumbent must not let a pending idle sibling backfill its slot")

		// Showing it again must respawn on the very next tick with no fresh cap
		// contention — the slot was reserved the whole time it was hidden.
		pool.setVisible(true, for: "claude_code:active-one")
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:active-one": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:idle-one": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:idle-two": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:active-one", "claude_code:idle-one"],
			"un-hiding a still-occupant session must respawn immediately without competing for a slot")
	}

	/// (P15.07-QC) A hidden session that genuinely loses the cap fight (a real
	/// in-flight newcomer takes its slot, not a bogus backfill) must drop out
	/// of `hiddenWindowKeys` the moment it's evicted — otherwise the menu keeps
	/// offering a "Show" entry that does nothing when clicked, and the session
	/// vanishes from both `activeOrigins` and `hiddenWindowKeys` with no way to
	/// retry ("lost in the ether").
	func testHiddenSessionThatLosesTheCapFightIsRemovedFromHiddenList() {
		var savedCalls: [Set<String>] = []
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() },
			hiddenKeysSaver: { savedCalls.append($0) }
		)

		// Tick 1: idle-a and active-b fill both slots under cap 2.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:idle-a", "claude_code:active-b"])

		// User hides idle-a.
		pool.setVisible(false, for: "claude_code:idle-a")
		XCTAssertTrue(pool.hiddenWindowKeys.contains("claude_code:idle-a"))

		// A genuine in-flight newcomer arrives — both slots correctly go to
		// the two in-flight sessions, legitimately evicting idle-a.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:idle-a": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:active-b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:active-c": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:02.000Z"),
			],
			customization: customization
		))

		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:active-b", "claude_code:active-c"])
		XCTAssertFalse(
			pool.hiddenWindowKeys.contains("claude_code:idle-a"),
			"a hidden session that loses the cap fight must be dropped from hiddenWindowKeys, not left as a dead 'Show' entry")
		XCTAssertFalse(
			Set(pool.activeOrigins).union(pool.hiddenWindowKeys).contains("claude_code:idle-a"),
			"the evicted session must not linger in either menu-visible set")
		XCTAssertEqual(
			savedCalls.last, [],
			"the write-through save must reflect the purge"
		)
	}

	/// (4 review focus) A blocked all-active origin must never evict a
	/// currently-rendered active session — the rendered set stays exactly the
	/// same across the tick that introduces the third active session.
	func testAllActiveCapPressureNeverEvictsAnAlreadyRenderedSession() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)
		let first = [
			"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
			"claude_code:b": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:01.000Z"),
		]
		pool.update(snapshot: makeResolvedSnapshot(perSession: first, customization: customization))
		XCTAssertEqual(Set(pool.activeOrigins), ["claude_code:a", "claude_code:b"])

		let second = first.merging([
			"claude_code:c": makeSnapshot(state: .editing, updated: "2026-07-01T10:00:02.000Z")
		]) { _, new in new }
		pool.update(snapshot: makeResolvedSnapshot(perSession: second, customization: customization))

		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code:a", "claude_code:b"],
			"a blocked newcomer active session must never evict an already-rendered active session")
	}

	/// A blocked all-active origin must expose the block via `blockedOrigins`,
	/// not just via the rendered-set partition — P15.08's conflict-bubble
	/// signal reads this property directly.
	func testAllActiveCapPressureIsExposedThroughBlockedOrigins() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)
		let first = [
			"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
			"claude_code:b": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:01.000Z"),
		]
		pool.update(snapshot: makeResolvedSnapshot(perSession: first, customization: customization))
		XCTAssertTrue(pool.blockedOrigins.isEmpty, "no blocked origin while all sessions fit under cap")

		let second = first.merging([
			"claude_code:c": makeSnapshot(state: .editing, updated: "2026-07-01T10:00:02.000Z")
		]) { _, new in new }
		pool.update(snapshot: makeResolvedSnapshot(perSession: second, customization: customization))

		XCTAssertEqual(
			pool.blockedOrigins, ["claude_code"],
			"an all-active origin over cap must report itself in blockedOrigins")
	}

	/// P15.08 advisory-observation fix: if the conflict bubble's host window
	/// dies for a reason other than resolution (here: a manual Prune) while
	/// the origin is still blocked, the bubble must re-home onto the next
	/// longest-lived live session immediately — not wait up to an hour for
	/// the rate limiter to naturally allow a re-fire.
	func testConflictBubbleRehomesToFreshTargetWhenItsHostWindowIsPrunedWhileStillBlocked() {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("pool-bubble-rehome-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		func writeSlice(_ name: String, updatedAt: String) {
			try! """
				{ "activity_state": "implementing", "updated_at": "\(updatedAt)", "source_event": { "origin": "claude_code" } }
				""".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}

		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		var stubs: [String: StubWindowController] = [:]
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			now: { currentTime }
		)
		func readSnapshot() -> PerPlatformSnapshot {
			guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(at: dir.path)
			else { fatalError("read must succeed") }
			return makeResolvedSnapshot(perSession: perSession, customization: customization)
		}

		// Tick 1: "b" alone renders.
		writeSlice("claude_code:b.json", updatedAt: "2026-07-01T10:00:00.000Z")
		pool.update(snapshot: readSnapshot())

		// Tick 2: "c" joins; both fit under cap 2, so both render.
		currentTime = currentTime.addingTimeInterval(1)
		writeSlice("claude_code:c.json", updatedAt: "2026-07-01T10:00:01.000Z")
		pool.update(snapshot: readSnapshot())

		// Tick 3: "a" joins as a third session — now over cap. "b" and "c" are
		// incumbents and stay rendered; "a" is pending. "b" is the
		// longest-lived (first-seen) of the two rendered sessions, so it
		// becomes the conflict-bubble host.
		currentTime = currentTime.addingTimeInterval(1)
		writeSlice("claude_code:a.json", updatedAt: "2026-07-01T10:00:02.000Z")
		pool.update(snapshot: readSnapshot())
		XCTAssertEqual(pool.blockedOrigins, ["claude_code"])
		XCTAssertEqual(
			stubs["claude_code:b"]?.appliedConflictBubbles.last ?? nil,
			ConflictBubblePayload(origin: "claude_code"),
			"the longest-lived rendered session must host the initial conflict bubble")

		// Tick 4: "d" joins too — a second pending session, so the origin
		// stays over cap even after "b" (one of the two rendered incumbents)
		// is pruned below.
		currentTime = currentTime.addingTimeInterval(1)
		writeSlice("claude_code:d.json", updatedAt: "2026-07-01T10:00:03.000Z")
		pool.update(snapshot: readSnapshot())

		// Manually prune "b" — the bubble's host window — while "a" and "d"
		// (pending) and "c" (rendered) keep the origin over cap. Well within
		// the rate limiter's one-hour window, so a naive re-fire check would
		// suppress any new bubble.
		currentTime = currentTime.addingTimeInterval(1)
		pool.pruneSession(windowKey: "claude_code:b", stateDirectory: dir.path)
		pool.update(snapshot: readSnapshot())

		XCTAssertEqual(pool.blockedOrigins, ["claude_code"], "the origin must still be blocked after the prune")
		XCTAssertEqual(
			stubs["claude_code:c"]?.appliedConflictBubbles.last ?? nil,
			ConflictBubblePayload(origin: "claude_code"),
			"the bubble must re-home onto the next longest-lived live session immediately, "
				+ "bypassing the one-hour rate limit — this is the same ongoing conflict, not a new one")
	}

	/// P15.08 advisory-observation fix: firstSeenAt (and lastSeenAt /
	/// lastUpdatedAt alongside it) must not retain a render key's ancient
	/// timestamp forever. Once a key drops out of the snapshot for longer
	/// than its TTL grace window, its bookkeeping must be forgotten — so if
	/// the same render key is later observed again, it is treated as a fresh
	/// first sighting rather than recalling a tenure from a previous,
	/// unrelated episode. Observable via conflict-bubble target selection,
	/// which picks the earliest firstSeenAt among currently-rendered sessions.
	func testFirstSeenAtForgetsARenderKeyThatAgedOutPastItsTTLWindow() {
		let customization = makeCustomization(
			ttlSeconds: 300, sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": 2])
		var stubs: [String: StubWindowController] = [:]
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			now: { currentTime }
		)

		// Tick 1: "a" alone, rendered.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z")],
			customization: customization))

		// Tick 2: "b" joins; both fit under cap 2, both render. firstSeenAt
		// captures a:T+0, b:T+1 — "a" is the more tenured of the two.
		currentTime = currentTime.addingTimeInterval(1)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization))

		// Tick 3: "a" vanishes entirely (its hook session ended) for far
		// longer than the 300s TTL. Its window is dismissed, and — with the
		// fix — its firstSeenAt/lastSeenAt/lastUpdatedAt entries are pruned.
		currentTime = currentTime.addingTimeInterval(400)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["claude_code:b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:06:41.000Z")],
			customization: customization))

		// Tick 4: "a" reappears (session id reused) alongside continuing "b" —
		// just the two of them, still under cap, so both render with no
		// eviction contest. This lets "a" settle back into an incumbent
		// window before the next tick introduces cap pressure, isolating what
		// we actually want to test: whether "a"'s firstSeenAt was correctly
		// reset to this tick (the fix) or still carries its tick-1 value (the
		// bug) — `SessionSelectionPolicy.select`'s eviction sort never looks
		// at firstSeenAt itself, only rank/incumbency/recency/lex, so this can only be
		// observed via which incumbent conflict-bubble target selection picks
		// once both are incumbents.
		currentTime = currentTime.addingTimeInterval(1)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:06:42.000Z"),
				"claude_code:b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:06:41.000Z"),
			],
			customization: customization))

		// Tick 5: "c" joins as a third in-flight session, pushing the origin
		// over cap. "a" and "b" are now both incumbents, so the sole
		// non-incumbent "c" is evicted regardless of rank or lex order —
		// deterministic. "c" is in-flight, so this eviction counts as a real
		// conflict (`blocked == true`).
		currentTime = currentTime.addingTimeInterval(1)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:06:43.000Z"),
				"claude_code:b": makeSnapshot(state: .implementing, updated: "2026-07-01T10:06:43.000Z"),
				"claude_code:c": makeSnapshot(state: .thinking, updated: "2026-07-01T10:06:43.000Z"),
			],
			customization: customization))

		XCTAssertEqual(pool.blockedOrigins, ["claude_code"])
		XCTAssertEqual(
			stubs["claude_code:b"]?.appliedConflictBubbles.last ?? nil,
			ConflictBubblePayload(origin: "claude_code"),
			"\"b\" must win the conflict-bubble target: \"a\" was reset to a fresh firstSeenAt on "
				+ "reappearance rather than retaining its ancient tick-1 tenure over continuously-present \"b\"")
	}

	/// A negative persisted `session_cap` must resolve to the shared default
	/// cap (3), matching `CustomizationSnapshot.sessionCap`'s documented
	/// "absent or negative" contract — not fall through to
	/// `SessionSelectionPolicy.select`'s `cap > 0` guard, which would silently
	/// treat any non-positive cap as Unlimited.
	func testNegativeSessionCapResolvesToDefaultCapNotUnlimited() {
		let customization = makeCustomization(
			sessionPetsEnabled: ["claude_code": true], sessionCap: ["claude_code": -1])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindowController() }
		)
		let perSession = [
			"claude_code:a": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:00.000Z"),
			"claude_code:b": makeSnapshot(state: .thinking, updated: "2026-07-01T10:00:01.000Z"),
			"claude_code:c": makeSnapshot(state: .editing, updated: "2026-07-01T10:00:02.000Z"),
			"claude_code:d": makeSnapshot(state: .reading, updated: "2026-07-01T10:00:03.000Z"),
		]

		pool.update(snapshot: makeResolvedSnapshot(perSession: perSession, customization: customization))

		XCTAssertEqual(
			pool.activeOrigins.count, 3,
			"a negative session_cap must resolve to the default cap of 3, not Unlimited")
		XCTAssertEqual(
			pool.blockedOrigins, ["claude_code"],
			"a negative session_cap must still block the fourth session under the resolved default cap")
	}

	/// (4 review focus) Manual Prune atomicity: destroys the panel, deletes the
	/// slice, releases the number, and removes the label key together.
	func testPruneSessionDestroysPanelSliceNumberAndLabelTogether() {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("pool-prune-atomic-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let labelsFile = dir.appendingPathComponent("session-labels.json")
		SessionLabelStore.setLabel("Mine", for: "claude_code:s1", at: labelsFile.path)
		try! Data("{}".utf8).write(to: dir.appendingPathComponent("claude_code:s1.json"))

		var stub: StubWindowController?
		let customization = makeCustomization(sessionPetsEnabled: ["claude_code": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in
				let c = StubWindowController()
				stub = c
				return c
			},
			sessionLabelReader: { SessionLabelStore.label(for: $0, at: labelsFile.path) }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["claude_code:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization))
		XCTAssertEqual(pool.sessionNumber(forWindowKey: "claude_code:s1"), 1)

		pool.pruneSession(windowKey: "claude_code:s1", stateDirectory: dir.path, labelPath: labelsFile.path)

		XCTAssertEqual(stub?.isFloatingPetVisible, false, "the panel must be torn down")
		XCTAssertFalse(pool.isActive(for: "claude_code:s1"))
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("claude_code:s1.json").path),
			"the slice must be deleted")
		XCTAssertNil(
			SessionLabelStore.label(for: "claude_code:s1", at: labelsFile.path),
			"the label key must be removed")

		// A brand-new session on the same origin must reclaim the released number.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["claude_code:s2": makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization))
		XCTAssertEqual(
			pool.sessionNumber(forWindowKey: "claude_code:s2"), 1,
			"the pruned session's number must be released back to the free list")
	}

	/// (4 review focus) Prune is a no-op for a plain-origin (session-pets off)
	/// or "combined" window — those are never session-keyed.
	func testPruneSessionIsNoOpForNonSessionKeyedWindow() {
		var stub: StubWindowController?
		let customization = makeCustomization()
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in
				let c = StubWindowController()
				stub = c
				return c
			}
		)
		pool.update(snapshot: makePerPlatformSnapshot([
			"claude_code": makeSnapshot(updated: "2026-06-28T10:00:00.000Z")
		]))

		pool.pruneSession(windowKey: "claude_code", stateDirectory: "/tmp/does-not-matter")

		XCTAssertTrue(pool.isActive(for: "claude_code"), "a plain-origin window must survive an attempted prune")
		XCTAssertNotEqual(stub?.isFloatingPetVisible, false)
	}

	/// (4 combined coverage) Combined-mode sessions must never be cap-partitioned
	/// — they always fold to the single shared window regardless of
	/// `sessionCap`, and keep the combined window's idle ⭐ Default badge
	/// behavior (`applyPlatform("combined")`).
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
		XCTAssertEqual(
			stubs["combined"]?.appliedSessionLabels.last ?? nil, "Combined",
			"the session-label badge names the window itself (\"Combined\"), distinct from"
				+ " the platform chip's ⭐ \"Default\" pet-assignment text"
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

	// MARK: - Session-pets attention fan-out (dismiss/Focus clears every sibling bubble)

	func testClearAttentionBubblesHidesEverySessionWindowSharingTheOrigin() {
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
		let cursorCallCountBefore = stubs["cursor"]?.appliedAttention.count ?? 0

		pool.clearAttentionBubbles(sharingOriginWith: "codex:s1")

		XCTAssertEqual(
			stubs["codex:s1"]?.appliedAttention.last?.0, nil,
			"the clicked session's own bubble must clear"
		)
		XCTAssertEqual(
			stubs["codex:s2"]?.appliedAttention.last?.0, nil,
			"a sibling session sharing the same origin must also clear — Focus can only "
				+ "raise the codex app as a whole, not one specific thread"
		)
		XCTAssertEqual(
			stubs["cursor"]?.appliedAttention.count, cursorCallCountBefore,
			"a different platform's window must not be touched"
		)
	}

	// MARK: - P15.05 Session number gating

	func testSessionKeyedWindowsGetSessionNumbersStartingAtOne() {
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
			],
			customization: customization
		))
		XCTAssertEqual(
			stubs["codex:s1"]?.appliedSessionNumbers.last ?? nil, 1,
			"first session-keyed window must be numbered 1"
		)
		XCTAssertEqual(
			stubs["codex:s2"]?.appliedSessionNumbers.last ?? nil, 2,
			"second session-keyed window must be numbered 2"
		)
	}

	func testPlainOriginWindowWithSessionPetsOffNeverGetsASessionNumber() {
		// Regression: `sessionNumber(forWindowKey:)` must gate on isSessionKeyed
		// the same way the private assign/release helpers do. A plain-origin
		// render key still carries a `RenderKeyIdentity` (session_id degrades to
		// "default"), so an ungated lookup would wrongly hand out a number.
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": false])
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
			],
			customization: customization
		))
		XCTAssertEqual(Set(pool.activeOrigins), Set(["codex"]))
		XCTAssertNil(pool.sessionNumber(forWindowKey: "codex"))
		XCTAssertEqual(
			stubs["codex"]?.appliedSessionNumbers,
			[nil],
			"a plain-origin window (session-pets off) must never receive a session number"
		)
	}

	func testTTLDismissedSessionReleasesItsNumberEvenAfterItsIdentityLeavesTheSnapshot() {
		// Regression: a session ending deletes its state.d slice, so its
		// RenderKeyIdentity drops out of the snapshot immediately — but the
		// window itself lingers until TTL expiry. releaseSessionNumber must
		// resolve the identity from assign-time bookkeeping, not from the
		// (by-then-stale) latest snapshot, or the freed number leaks forever.
		var stubs: [String: StubWindowController] = [:]
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let customization = makeCustomization(ttlSeconds: 60, sessionPetsEnabled: ["claude_code": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			now: { currentTime }
		)

		// Tick 1: two sessions spawn, get numbers 1 and 2. s2 is the busier /
		// more-recently-updated session so it (not s1) holds last-active immunity.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s1": makeSnapshot(state: .idle, updated: "2026-07-01T10:00:00.000Z"),
				"claude_code:s2": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["claude_code:s1"]?.appliedSessionNumbers.last ?? nil, 1)
		XCTAssertEqual(stubs["claude_code:s2"]?.appliedSessionNumbers.last ?? nil, 2)

		// Tick 2: s1's session ends — its state.d slice is gone, so it drops out
		// of the snapshot entirely. Its window is still within its TTL grace
		// window, so it must still be present (not yet dismissed).
		currentTime = currentTime.addingTimeInterval(1)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s2": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertTrue(pool.activeOrigins.contains("claude_code:s1"), "s1 must survive within its TTL grace window")

		// Tick 3: advance past the TTL. s1's window is now dismissed via Step 5b
		// with NO entry for "claude_code:s1" in this tick's renderKeyIdentities.
		currentTime = currentTime.addingTimeInterval(61)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s2": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
			],
			customization: customization
		))
		XCTAssertFalse(pool.activeOrigins.contains("claude_code:s1"), "s1 must be dismissed once its TTL expires")

		// Tick 4: a brand-new session arrives. If s1's number (1) was correctly
		// released, the new session reuses it (lowest free) instead of climbing
		// to 3.
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"claude_code:s2": makeSnapshot(state: .implementing, updated: "2026-07-01T10:00:01.000Z"),
				"claude_code:s3": makeSnapshot(state: .idle, updated: "2026-07-01T10:02:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(
			stubs["claude_code:s3"]?.appliedSessionNumbers.last ?? nil, 1,
			"a released number must be reused by the next new session, not leaked forever"
		)
	}

	func testCombinedWindowNeverGetsASessionNumber() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(platformModes: ["codex": .combined])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			}
		)
		let snap = makePerPlatformSnapshot([
			"codex": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
		])
		pool.update(snapshot: snap)
		XCTAssertEqual(pool.activeOrigins, ["combined"])
		XCTAssertNil(pool.sessionNumber(forWindowKey: "combined"))
		XCTAssertEqual(
			stubs["combined"]?.appliedSessionNumbers, [],
			"applySessionNumber must never be dispatched to the combined controller")
	}

	// MARK: - P15.06 Session label resolution

	func testSessionKeyedWindowWithSidecarLabelDisplaysItInsteadOfSessionN() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { key in key == "codex:s1" ? "Refactor pass" : nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Refactor pass")
	}

	// An unrenamed session-keyed window gets its "Session N" default resolved
	// at the pool, not synthesized inside the badge view — a non-nil label is
	// what gates the right-click "Rename…" affordance, so leaving it nil here
	// would hide Rename on every never-renamed session window.
	func testSessionKeyedWindowWithoutSidecarLabelAppliesSessionNumberDefault() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { _ in nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Session 1")
	}

	// A plain-origin window (session-pets off) now gets a session-label badge
	// too (P?? unification): the user's rename, if the sidecar has one for
	// this exact plain-origin key ("codex", not "codex:s1").
	func testPlainOriginWindowAppliesItsOwnSidecarLabelWhenReaderHasOne() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": false])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { key in key == "codex" ? "My Codex" : nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex"]?.appliedSessionLabels.last ?? nil, "My Codex")
	}

	// Without a sidecar rename, a plain-origin window falls back to the
	// platform's own display name — it has no "Session N" of its own to fall
	// back to the way a session-keyed window does.
	func testPlainOriginWindowWithoutSidecarLabelFallsBackToPlatformDisplayName() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": false])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { _ in nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex"]?.appliedSessionLabels.last ?? nil, "Codex")
	}

	// MARK: - Session title resolution (platform auto-generated thread titles)

	// A session-keyed window with no sidecar rename prefers the platform's
	// own resolved thread title over the numeric "Session N" fallback — a
	// friendlier default when the coding-agent platform already titled it.
	func testSessionKeyedWindowWithResolvedTitlePrefersItOverSessionNumber() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { _ in nil },
			sessionTitleReader: { origin, sessionId in
				origin == "codex" && sessionId == "s1" ? "Locate session auto label" : nil
			}
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Locate session auto label")
	}

	// A sidecar rename always wins over a resolved title, exactly as it wins
	// over the "Session N" default — the user's explicit rename is never
	// second-guessed by a friendlier-looking platform title.
	func testSessionKeyedWindowUserRenameStillWinsOverResolvedTitle() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { key in key == "codex:s1" ? "Renamed by user" : nil },
			sessionTitleReader: { _, _ in "Locate session auto label" }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Renamed by user")
	}

	// A title unresolved on the first tick (the platform hasn't titled the
	// thread yet) is retried on a later tick rather than permanently frozen
	// at "Session N".
	func testSessionKeyedWindowRetriesUnresolvedTitleOnLaterTick() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		var titleAvailable = false
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { _ in nil },
			sessionTitleReader: { _, _ in titleAvailable ? "Locate session auto label" : nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Session 1")

		titleAvailable = true
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["codex:s1": makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Locate session auto label")
	}

	// Once resolved, a title is cached rather than re-fetched every tick —
	// `sessionTitleReader` touches another app's on-disk storage, so a
	// resolved title must not be looked up again on every subsequent tick.
	func testSessionKeyedWindowResolvedTitleIsNotReFetchedOnLaterTicks() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		var readerCallCount = 0
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionLabelReader: { _ in nil },
			sessionTitleReader: { _, _ in
				readerCallCount += 1
				return "Locate session auto label"
			}
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization
		))
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: ["codex:s1": makeSnapshot(updated: "2026-07-01T10:00:01.000Z")],
			customization: customization
		))
		XCTAssertEqual(readerCallCount, 1)
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionLabels.last ?? nil, "Locate session auto label")
	}

	/// Mirrors `testSessionKeyedWindowWithSidecarLabelDisplaysItInsteadOfSessionN`
	/// for `applySessionTooltip` — the pool-level path was previously untested
	/// even though the label path had symmetric coverage.
	func testSessionKeyedWindowWithPromptSummaryAppliesItAsTooltip() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": true])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionPromptSummaryReader: { key in key == "codex:s1" ? "Fix the login bug" : nil }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex:s1"]?.appliedSessionTooltips.last ?? nil, "Fix the login bug")
	}

	/// Mirrors `testPlainOriginWindowNeverAppliesASessionLabelEvenIfReaderHasOne`
	/// for `applySessionTooltip`.
	func testPlainOriginWindowNeverAppliesASessionTooltipEvenIfReaderHasOne() {
		var stubs: [String: StubWindowController] = [:]
		let customization = makeCustomization(sessionPetsEnabled: ["codex": false])
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { key, _ in
				let c = StubWindowController()
				stubs[key] = c
				return c
			},
			sessionPromptSummaryReader: { _ in "should never surface" }
		)
		pool.update(snapshot: makeResolvedSnapshot(
			perSession: [
				"codex:s1": makeSnapshot(updated: "2026-07-01T10:00:00.000Z"),
			],
			customization: customization
		))
		XCTAssertEqual(stubs["codex"]?.appliedSessionTooltips, [nil])
	}

	// MARK: - sessionIdentity(forWindowKey:)

	func testSessionIdentitySplitsOriginAndSessionIdForASessionKeyedKey() {
		let identity = FloatingPetWindowPool.sessionIdentity(forWindowKey: "claude_code:s1")
		XCTAssertEqual(identity?.origin, "claude_code")
		XCTAssertEqual(identity?.sessionId, "s1")
	}

	func testSessionIdentityIsNilForAPlainOrigin() {
		XCTAssertNil(FloatingPetWindowPool.sessionIdentity(forWindowKey: "claude_code"))
	}

	func testSessionIdentityIsNilForTheCombinedKey() {
		XCTAssertNil(FloatingPetWindowPool.sessionIdentity(forWindowKey: "combined"))
	}

	// MARK: - modeSwitchOrigin(forWindowKey:)

	func testModeSwitchOriginResolvesASessionKeyedKeyToItsPlatformOrigin() {
		// Platform-level switch: a right-click on one session panel must
		// rewrite the whole platform's mode, never a per-session mode.
		XCTAssertEqual(
			FloatingPetWindowPool.modeSwitchOrigin(forWindowKey: "claude_code:s1"),
			"claude_code")
	}

	func testModeSwitchOriginIsTheKeyItselfForAPlainOrigin() {
		XCTAssertEqual(
			FloatingPetWindowPool.modeSwitchOrigin(forWindowKey: "cursor"), "cursor")
	}

	func testModeSwitchOriginIsNilForTheCombinedKey() {
		// The combined window has no single origin — the switch flips
		// combined_minimalist_enabled instead of any platform_modes entry.
		XCTAssertNil(FloatingPetWindowPool.modeSwitchOrigin(forWindowKey: "combined"))
	}

	// MARK: - pruneHiddenKeysWithoutBackingSlice (zombie "Show … Pet" menu entries)

	private func makeSliceDir(files: [String]) -> String {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("pool-hidden-prune-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		for name in files {
			try! Data("{}".utf8).write(to: dir.appendingPathComponent(name))
		}
		return dir.path
	}

	func testPruneHiddenKeysDropsASessionKeyWhoseSliceWasDeletedAndPersists() {
		let dir = makeSliceDir(files: ["claude_code:alive.json"])
		defer { try? FileManager.default.removeItem(atPath: dir) }
		var savedSets: [Set<String>] = []
		let pool = FloatingPetWindowPool(
			customizationReader: { .safeDefault },
			windowFactory: { _, _ in StubWindowController() },
			hiddenKeysSaver: { savedSets.append($0) }
		)
		pool.setVisible(false, for: "claude_code:alive")
		pool.setVisible(false, for: "claude_code:pruned")

		pool.pruneHiddenKeysWithoutBackingSlice(stateDirectory: dir)

		XCTAssertEqual(
			Set(pool.hiddenWindowKeys), ["claude_code:alive"],
			"the key with a live slice survives; the SlicePruner-deleted one is culled")
		XCTAssertEqual(
			savedSets.last, ["claude_code:alive"],
			"the trimmed set must persist so the zombie key does not resurrect on relaunch")
	}

	func testPruneHiddenKeysKeepsAPlainOriginKeyWhileAnySliceOfThatOriginExists() {
		let dir = makeSliceDir(files: ["cursor:s1.json"])
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let pool = FloatingPetWindowPool(
			customizationReader: { .safeDefault },
			windowFactory: { _, _ in StubWindowController() }
		)
		pool.setVisible(false, for: "cursor")
		pool.setVisible(false, for: "codex")

		pool.pruneHiddenKeysWithoutBackingSlice(stateDirectory: dir)

		XCTAssertEqual(
			Set(pool.hiddenWindowKeys), ["cursor"],
			"a plain-origin key survives on any slice of its origin; codex has none left")
	}

	func testPruneHiddenKeysCombinedKeySurvivesWhileACombinedOriginHasASlice() {
		let dir = makeSliceDir(files: ["cursor:s1.json"])
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let combined = CustomizationSnapshot(
			platformModes: ["cursor": .combined, "codex": .combined],
			idleDismissTtlSeconds: 300,
			menubarIconMonochrome: false,
			combinedMinimalistEnabled: false,
			minimalistBadgeScale: 1.0
		)
		let pool = FloatingPetWindowPool(
			customizationReader: { combined },
			windowFactory: { _, _ in StubWindowController() }
		)
		pool.setVisible(false, for: "combined")

		pool.pruneHiddenKeysWithoutBackingSlice(stateDirectory: dir)
		XCTAssertEqual(
			Set(pool.hiddenWindowKeys), ["combined"],
			"the combined key survives while any combined-mode origin still has a slice")

		try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent("cursor:s1.json"))
		pool.pruneHiddenKeysWithoutBackingSlice(stateDirectory: dir)
		XCTAssertTrue(
			pool.hiddenWindowKeys.isEmpty,
			"once every combined-mode origin's slices are gone, the combined key is culled")
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

	// MARK: - P15.06 exact session-key lookup (not origin-collapsed)

	func testSummaryForSessionKeyReadsOnlyThatExactKey() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("PromptAttentionReaderTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let url = dir.appendingPathComponent("prompt-attention.json")
		let json = """
			{
			  "by_session": {
			    "codex:s1": {
			      "updated_at": "2026-06-30T09:00:00.000Z",
			      "summary": "s1 prompt"
			    },
			    "codex:s2": {
			      "updated_at": "2026-06-30T11:00:00.000Z",
			      "summary": "s2 prompt, newer than s1"
			    }
			  }
			}
			"""
		try json.write(to: url, atomically: true, encoding: .utf8)

		XCTAssertEqual(PromptAttentionReader.summary(forSessionKey: "codex:s1", at: url.path), "s1 prompt")
		XCTAssertEqual(PromptAttentionReader.summary(forSessionKey: "codex:s2", at: url.path), "s2 prompt, newer than s1")
	}

	func testSummaryForSessionKeyAbsentOrMalformedFileReturnsEmpty() throws {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("missing-prompt-attention-\(UUID().uuidString).json")
		XCTAssertEqual(PromptAttentionReader.summary(forSessionKey: "codex:s1", at: missing.path), "")

		let malformed = FileManager.default.temporaryDirectory
			.appendingPathComponent("bad-prompt-attention-\(UUID().uuidString).json")
		try "{".write(to: malformed, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: malformed) }
		XCTAssertEqual(PromptAttentionReader.summary(forSessionKey: "codex:s1", at: malformed.path), "")
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

	/// Regression test for the bug where Minimalist mode never surfaced a
	/// session's rename (P15.06): `MinimalistWindowController` inherited the
	/// `FloatingPetWindowControlling` default no-op for `applySessionLabel`/
	/// `applySessionTooltip` instead of forwarding to its panel, so a label the
	/// user set in Own mode never appeared after switching a platform to
	/// Minimalist even though `SessionLabelStore` is shared, origin-keyed
	/// storage read by both modes.
	func testForwardsSessionLabelAndTooltipToPanel() {
		let panel = StubMinimalistPanel()
		let controller = MinimalistWindowController(
			origin: "codex:s1",
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
			promptSummaryProvider: { _ in "" }
		)

		controller.applySessionLabel("Refactor pass")
		controller.applySessionTooltip("Fix the login bug")

		XCTAssertEqual(panel.sessionLabel, "Refactor pass")
		XCTAssertEqual(panel.sessionTooltip, "Fix the login bug")
	}
}

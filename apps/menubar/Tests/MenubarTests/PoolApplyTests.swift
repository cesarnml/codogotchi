import AppKit
import XCTest

@testable import Codogotchi

/// Red-phase tests for P18.04's `apply` — executing a `WindowDiff` against
/// mock `FloatingPetWindowControlling` controllers. Per the ticket's Outcome:
///
/// "`apply` executes a diff against the Phase 17 converged factories: spawn
/// (with directive-driven frame adoption read from the live donor window at
/// execution time), teardown, and per-window pushes straight from
/// `DesiredWindow` fields ... Zero policy decisions."
///
/// `PoolApply` does not exist yet. Unlike `diff`, `apply` lives OUTSIDE
/// `Pool/Derive/` (it drives `FloatingPetWindowControlling`, an
/// `@MainActor`/AppKit-adjacent protocol) — this file is a sibling of
/// `FloatingPetWindowPoolTests.swift`, matching that convention.
///
/// Scope note (see this ticket's Rationale / the delivering agent's report):
/// `DesiredWindow.promptTimerStatus` is a `PromptTimerPresentation` (P18.03's
/// already-rendered label/isRunning pair) while
/// `FloatingPetWindowControlling.applyPromptTimerStatus` currently accepts a
/// `PromptTimerStatus` (raw startedAt/endedAt). That type mismatch is a real
/// gap `apply`'s green phase must resolve (new protocol member vs. adapting
/// the existing one) — deliberately left untested here rather than guessed.
@MainActor
final class PoolApplyTests: XCTestCase {

	// MARK: - Test double

	private final class MockController: FloatingPetWindowControlling {
		var isFloatingPetVisible = false
		var appliedStates: [(ActivityState, VisualMode)] = []
		var appliedAttention: [(AttentionPayload?, SourceEvent?)] = []
		var appliedGateBadges: [GateBadgeContent?] = []
		var appliedPlatforms: [String?] = []
		var appliedRPGStates: [(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)] =
			[]
		var appliedSessionNumbers: [Int?] = []
		var appliedSessionLabels: [String?] = []
		var appliedSessionTooltips: [String?] = []
		var appliedConflictBubbles: [ConflictBubblePayload?] = []
		var appliedIdleEscalationConfigs: [IdleEscalationConfig] = []
		var adoptedFrames: [CGRect] = []
		/// Settable so a test can simulate "this window is currently at frame
		/// X" before `apply` reads it as a spawn's frame-inheritance donor.
		var currentFrame: CGRect = .zero
		var replacePetsCallCount = 0

		func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
		func apply(state: ActivityState, visualMode: VisualMode) { appliedStates.append((state, visualMode)) }
		func applyPromptTimerStatus(_ status: PromptTimerStatus?) {}
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
		func adoptFrame(_ frame: CGRect) {
			adoptedFrames.append(frame)
			currentFrame = frame
		}
		func updateIdleEscalationConfig(_ config: IdleEscalationConfig) { appliedIdleEscalationConfigs.append(config) }
	}

	// MARK: - Push completeness

	func testEveryDesiredWindowFieldReachesTheControllerOnUpdate() {
		let key: WindowKey = "codex:abc"
		var desired = DesiredWindow(key: key)
		desired.activityState = .implementing
		desired.attention = AttentionPayload(createdAt: nil, expiresAt: nil, summary: "stuck", reasonKind: "error")
		desired.attentionSourceEvent = SourceEvent(origin: "codex", kind: "tool", name: "Edit")
		desired.gateBadge = GateBadgeContent(ticketId: "P18.04", gate: "red_tdd")
		desired.platformChip = "codex"
		desired.rpgSnapshot = RpgSnapshot(
			level: 3, levelFraction: 0.5, halfHearts: 6, activeMinutes: 42, lastActivityAt: nil, reviveUntil: nil)
		desired.hudEnabled = true
		desired.sessionNumber = 2
		desired.sessionLabel = "My renamed session"
		desired.sessionTooltip = "Refactor the diff module"
		desired.conflictBubble = ConflictBubblePayload(origin: "codex")

		let controller = MockController()
		var controllers: [WindowKey: FloatingPetWindowControlling] = [key: controller]
		var diff = WindowDiff()
		diff.toUpdate[key] = desired

		PoolApply.apply(diff: diff, controllers: &controllers, spawn: { _, _ in
			XCTFail("spawn must not be invoked for an update-only diff")
			return MockController()
		})

		XCTAssertEqual(controller.appliedStates.last?.0, .implementing)
		XCTAssertEqual(controller.appliedAttention.last?.0?.summary, "stuck")
		XCTAssertEqual(controller.appliedAttention.last?.1?.origin, "codex")
		XCTAssertEqual(controller.appliedGateBadges.last ?? nil, GateBadgeContent(ticketId: "P18.04", gate: "red_tdd"))
		XCTAssertEqual(controller.appliedPlatforms.last ?? nil, "codex")
		XCTAssertEqual(controller.appliedRPGStates.last?.halfHearts, 6)
		XCTAssertEqual(controller.appliedRPGStates.last?.hudEnabled, true)
		XCTAssertEqual(controller.appliedSessionNumbers.last ?? nil, 2)
		XCTAssertEqual(controller.appliedSessionLabels.last ?? nil, "My renamed session")
		XCTAssertEqual(controller.appliedSessionTooltips.last ?? nil, "Refactor the diff module")
		XCTAssertEqual(controller.appliedConflictBubbles.last ?? nil, ConflictBubblePayload(origin: "codex"))
	}

	func testDismissedWindowIsHiddenAndRemovedFromControllers() {
		let key: WindowKey = "cursor"
		let controller = MockController()
		controller.isFloatingPetVisible = true
		var controllers: [WindowKey: FloatingPetWindowControlling] = [key: controller]
		var diff = WindowDiff()
		diff.toDismiss = [key]

		PoolApply.apply(diff: diff, controllers: &controllers, spawn: { _, _ in
			XCTFail("spawn must not be invoked for a dismiss-only diff")
			return MockController()
		})

		XCTAssertEqual(controller.isFloatingPetVisible, false)
		XCTAssertNil(controllers[key])
	}

	// MARK: - Spawn + directive-driven frame adoption

	func testFreshSpawnAdoptsDonorsLiveFrameReadAtExecutionTime() {
		let donorKey: WindowKey = "claude:s1"
		let freshKey: WindowKey = "claude:s2"
		let donor = MockController()
		donor.currentFrame = CGRect(x: 10, y: 20, width: 300, height: 400)

		var controllers: [WindowKey: FloatingPetWindowControlling] = [donorKey: donor]
		var spawning = DesiredWindow(key: freshKey)
		spawning.inheritedFrameFrom = donorKey

		var diff = WindowDiff()
		diff.toSpawn[freshKey] = spawning
		// Same tick the donor is evicted — a genuinely concurrent
		// spawn+teardown, which is exactly why the donor's frame must be
		// read BEFORE (or independent of) its own teardown removing it from
		// `controllers`.
		diff.toDismiss = [donorKey]

		let newController = MockController()
		PoolApply.apply(diff: diff, controllers: &controllers, spawn: { key, window in
			XCTAssertEqual(key, freshKey)
			XCTAssertEqual(window.inheritedFrameFrom, donorKey)
			return newController
		})

		XCTAssertEqual(newController.adoptedFrames.last, CGRect(x: 10, y: 20, width: 300, height: 400))
		XCTAssertTrue(controllers[freshKey] === newController)
		XCTAssertNil(controllers[donorKey], "donor is torn down in the same tick it hands off its frame")
	}

	func testFreshSpawnWithNoInheritedFrameNeverAdoptsAFrame() {
		let freshKey: WindowKey = "codex"
		var controllers: [WindowKey: FloatingPetWindowControlling] = [:]
		var diff = WindowDiff()
		diff.toSpawn[freshKey] = DesiredWindow(key: freshKey)

		let newController = MockController()
		PoolApply.apply(diff: diff, controllers: &controllers, spawn: { _, _ in newController })

		XCTAssertTrue(newController.adoptedFrames.isEmpty)
	}
}

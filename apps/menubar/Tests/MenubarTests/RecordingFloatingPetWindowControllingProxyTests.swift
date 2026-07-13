import AppKit
import XCTest

@testable import Codogotchi

/// Red-phase tests for P18.04's recording `FloatingPetWindowControlling`
/// proxy. Per the ticket's Outcome:
///
/// "A recording `FloatingPetWindowControlling` proxy exists: forwards every
/// call to a wrapped controller while logging pushes per tick; also runnable
/// against a stub (no real window) whose `currentFrame` reads through to a
/// live window by key — both shadow directions covered."
///
/// and Review Focus: "Proxy: verify the stub direction's `currentFrame`
/// read-through — post-cutover reversed shadowing depends on it (P18.06)."
///
/// `RecordingFloatingPetWindowControllingProxy` does not exist yet. It lives
/// OUTSIDE `Pool/Derive/` (it conforms to the AppKit-adjacent
/// `FloatingPetWindowControlling` protocol), a sibling of
/// `FloatingPetWindowPoolTests.swift`.
///
/// Design note the green phase should confirm or revise (flagged rather than
/// silently assumed): the proxy is modeled here as wrapping ONE inner
/// `FloatingPetWindowControlling` (a real controller for the normal shadow
/// direction, or a no-op stub for the reversed direction) plus an optional
/// `liveFrameLookup: (WindowKey) -> CGRect?` that — when non-nil and
/// returning non-nil — wins over the wrapped controller's own `currentFrame`.
/// This is what lets the stub direction's `currentFrame` "read through to a
/// live window by key" without the stub itself ever holding a real frame.
@MainActor
final class RecordingFloatingPetWindowControllingProxyTests: XCTestCase {

	// MARK: - Test doubles

	private final class InertController: FloatingPetWindowControlling {
		var isFloatingPetVisible = false
		var currentFrame: CGRect = .zero
		var setVisibleCalls: [Bool] = []
		var appliedStates: [(ActivityState, VisualMode)] = []
		var appliedAttention: [(AttentionPayload?, SourceEvent?)] = []
		var appliedGateBadges: [GateBadgeContent?] = []
		var appliedPlatforms: [String?] = []
		var appliedSessionNumbers: [Int?] = []
		var appliedSessionLabels: [String?] = []
		var appliedSessionTooltips: [String?] = []
		var appliedConflictBubbles: [ConflictBubblePayload?] = []
		var adoptedFrames: [CGRect] = []
		var appliedIdleEscalationConfigs: [IdleEscalationConfig] = []
		var appliedRPGStates: [(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)] =
			[]
		var appliedPromptTimerStatuses: [PromptTimerStatus?] = []
		var appliedPromptTimerPresentations: [PromptTimerPresentation?] = []

		func setFloatingPetVisible(_ visible: Bool) {
			isFloatingPetVisible = visible
			setVisibleCalls.append(visible)
		}
		func apply(state: ActivityState, visualMode: VisualMode) { appliedStates.append((state, visualMode)) }
		func applyPromptTimerStatus(_ status: PromptTimerStatus?) { appliedPromptTimerStatuses.append(status) }
		func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
			appliedPromptTimerPresentations.append(presentation)
		}
		func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
			appliedRPGStates.append((halfHearts, levelFraction, level, activeMinutes, hudEnabled))
		}
		func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
			appliedAttention.append((payload, sourceEvent))
		}
		func applyGateBadge(content: GateBadgeContent?) { appliedGateBadges.append(content) }
		func applyPlatform(origin: String?) { appliedPlatforms.append(origin) }
		func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
		func applySessionNumber(_ number: Int?) { appliedSessionNumbers.append(number) }
		func applySessionLabel(_ label: String?) { appliedSessionLabels.append(label) }
		func applySessionTooltip(_ summary: String?) { appliedSessionTooltips.append(summary) }
		func applyConflictBubble(_ payload: ConflictBubblePayload?) { appliedConflictBubbles.append(payload) }
		func adoptFrame(_ frame: CGRect) { adoptedFrames.append(frame) }
		func updateIdleEscalationConfig(_ config: IdleEscalationConfig) { appliedIdleEscalationConfigs.append(config) }
	}

	// MARK: - Forwarding fidelity (wrapping a real controller)

	func testForwardsEveryCallToTheWrappedController() {
		let key: WindowKey = "claude_code"
		let wrapped = InertController()
		let proxy = RecordingFloatingPetWindowControllingProxy(wrapping: wrapped, key: key)

		proxy.setFloatingPetVisible(true)
		proxy.apply(state: .implementing, visualMode: .normal)
		proxy.applyPromptTimerStatus(PromptTimerStatus(startedAt: Date(timeIntervalSince1970: 0), endedAt: nil))
		proxy.applyPromptTimerPresentation(PromptTimerPresentation(label: "0:05", isRunning: true))
		proxy.applyAttention(
			payload: AttentionPayload(createdAt: nil, expiresAt: nil, summary: "s", reasonKind: "r"),
			sourceEvent: SourceEvent(origin: "claude_code", kind: "tool", name: nil))
		proxy.applyGateBadge(content: GateBadgeContent(ticketId: "P18.04", gate: "red_tdd"))
		proxy.applyPlatform(origin: "claude_code")
		proxy.applyRPGState(halfHearts: 8, levelFraction: 0.2, level: 1, activeMinutes: 10, hudEnabled: true)
		proxy.applySessionNumber(1)
		proxy.applySessionLabel("Session 1")
		proxy.applySessionTooltip("hello")
		proxy.applyConflictBubble(ConflictBubblePayload(origin: "claude_code"))
		proxy.adoptFrame(CGRect(x: 1, y: 2, width: 3, height: 4))
		proxy.updateIdleEscalationConfig(.production)

		XCTAssertEqual(wrapped.setVisibleCalls, [true])
		XCTAssertEqual(wrapped.appliedStates.count, 1)
		XCTAssertEqual(wrapped.appliedStates.first?.0, .implementing)
		XCTAssertEqual(wrapped.appliedPromptTimerStatuses.first ?? nil, PromptTimerStatus(startedAt: Date(timeIntervalSince1970: 0), endedAt: nil))
		XCTAssertEqual(wrapped.appliedPromptTimerPresentations.first ?? nil, PromptTimerPresentation(label: "0:05", isRunning: true))
		XCTAssertEqual(wrapped.appliedAttention.first?.0?.summary, "s")
		XCTAssertEqual(wrapped.appliedGateBadges.first ?? nil, GateBadgeContent(ticketId: "P18.04", gate: "red_tdd"))
		XCTAssertEqual(wrapped.appliedPlatforms.first ?? nil, "claude_code")
		XCTAssertEqual(wrapped.appliedRPGStates.first?.halfHearts, 8)
		XCTAssertEqual(wrapped.appliedSessionNumbers.first ?? nil, 1)
		XCTAssertEqual(wrapped.appliedSessionLabels.first ?? nil, "Session 1")
		XCTAssertEqual(wrapped.appliedSessionTooltips.first ?? nil, "hello")
		XCTAssertEqual(wrapped.appliedConflictBubbles.first ?? nil, ConflictBubblePayload(origin: "claude_code"))
		XCTAssertEqual(wrapped.adoptedFrames.first, CGRect(x: 1, y: 2, width: 3, height: 4))
		XCTAssertEqual(wrapped.appliedIdleEscalationConfigs.first, .production)
	}

	// MARK: - Shadow direction 1: wrapping a real controller, no lookup needed

	func testWrappingARealControllerReadsCurrentFrameFromTheWrappedControllerByDefault() {
		let key: WindowKey = "codex"
		let wrapped = InertController()
		wrapped.currentFrame = CGRect(x: 5, y: 6, width: 7, height: 8)
		let proxy = RecordingFloatingPetWindowControllingProxy(wrapping: wrapped, key: key)

		XCTAssertEqual(proxy.currentFrame, CGRect(x: 5, y: 6, width: 7, height: 8))
	}

	// MARK: - Shadow direction 2: wrapping a stub, currentFrame reads through by key

	func testStubDirectionCurrentFrameReadsThroughToLiveWindowByKeyNotTheStub() {
		let key: WindowKey = "cursor"
		let stub = InertController()
		stub.currentFrame = .zero  // the stub holds no real window, ergo no real frame
		let liveFrame = CGRect(x: 100, y: 200, width: 300, height: 400)
		let proxy = RecordingFloatingPetWindowControllingProxy(
			wrapping: stub, key: key,
			liveFrameLookup: { lookedUpKey in lookedUpKey == key ? liveFrame : nil })

		XCTAssertEqual(
			proxy.currentFrame, liveFrame,
			"the stub direction must read through to the live window by key, never the stub's own currentFrame")
	}

	func testStubDirectionFallsBackToWrappedWhenLookupMissesTheKey() {
		let key: WindowKey = "cursor"
		let stub = InertController()
		stub.currentFrame = CGRect(x: 1, y: 1, width: 1, height: 1)
		let proxy = RecordingFloatingPetWindowControllingProxy(
			wrapping: stub, key: key,
			liveFrameLookup: { _ in nil })

		XCTAssertEqual(proxy.currentFrame, CGRect(x: 1, y: 1, width: 1, height: 1))
	}

	// MARK: - Push log

	func testLogsPushesPerTickInCallOrder() {
		let key: WindowKey = "claude_code"
		let wrapped = InertController()
		let proxy = RecordingFloatingPetWindowControllingProxy(wrapping: wrapped, key: key)

		proxy.apply(state: .implementing, visualMode: .normal)
		proxy.applySessionLabel("Session 1")

		XCTAssertEqual(proxy.recordedCalls.count, 2)
		XCTAssertEqual(proxy.recordedCalls.first, .apply(state: .implementing, visualMode: .normal))
		XCTAssertEqual(proxy.recordedCalls.last, .sessionLabel("Session 1"))
	}

	func testRecordsBothPromptTimerPushShapes() {
		let key: WindowKey = "claude_code"
		let wrapped = InertController()
		let proxy = RecordingFloatingPetWindowControllingProxy(wrapping: wrapped, key: key)
		let status = PromptTimerStatus(startedAt: Date(timeIntervalSince1970: 0), endedAt: nil)
		let presentation = PromptTimerPresentation(label: "0:05", isRunning: true)

		proxy.applyPromptTimerStatus(status)
		proxy.applyPromptTimerPresentation(presentation)

		XCTAssertEqual(
			proxy.recordedCalls, [.promptTimerStatus(status), .promptTimerPresentation(presentation)],
			"the raw old-pipeline push and the P18.04 presentation push must both be recorded, in call order, "
				+ "so the shadow comparator can see the old pipeline's prompt-timer push")
	}
}

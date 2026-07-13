import XCTest

@testable import Codogotchi

/// Red-phase tests for P18.05: wiring the shadow tick — `PoolDerive` running
/// on the same tick input against its own threaded `PoolMemory` — into
/// `FloatingPetWindowPool.update()`, driven by the OLD (still-authoritative)
/// pipeline. Per the ticket's Red section:
///
/// (a) a tick where both pipelines agree produces no divergence records.
/// (b) a seeded disagreement (temporarily perturbed derive input) produces
///     exactly one structured divergence record and does NOT affect the
///     driving pipeline's windows.
///
/// Neither `FloatingPetWindowPool(shadowDivergenceHandler:)` nor
/// `FloatingPetWindowPool.shadowTickInputPerturbation` exist yet — this file
/// fails to compile against `agents/p18-04-diff-apply-recording-proxy-and-comparator`'s
/// HEAD, confirming the shadow tick is not wired in.
@MainActor
final class FloatingPetWindowPoolShadowTickTests: XCTestCase {

	// MARK: - Test double

	private final class StubWindowController: FloatingPetWindowControlling {
		var isFloatingPetVisible = false
		var currentFrame: CGRect = .zero
		func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
		func apply(state: ActivityState, visualMode: VisualMode) {}
		func applyPromptTimerStatus(_ status: PromptTimerStatus?) {}
		func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {}
		func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
		func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
		func applyGateBadge(content: GateBadgeContent?) {}
		func applyPlatform(origin: String?) {}
		func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
		func applySessionNumber(_ number: Int?) {}
		func applySessionLabel(_ label: String?) {}
		func applySessionTooltip(_ summary: String?) {}
		func applyConflictBubble(_ payload: ConflictBubblePayload?) {}
		func adoptFrame(_ frame: CGRect) { currentFrame = frame }
		func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {}
	}

	// MARK: - Helpers

	private func makeSnapshot(updated: String) -> StateSnapshot {
		StateSnapshot(
			schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
			activityState: .implementing,
			updatedAt: updated,
			sourceEvent: nil,
			attention: nil)
	}

	private func makeCustomization() -> CustomizationSnapshot {
		CustomizationSnapshot(
			platformModes: [:], idleDismissTtlSeconds: 300, menubarIconMonochrome: false,
			combinedMinimalistEnabled: false, minimalistBadgeScale: 1.0)
	}

	// MARK: - (a) Agreeing tick

	func testAgreeingTickRecordsNoShadowDivergences() {
		var recorded: [[DivergenceRecord]] = []
		let pool = FloatingPetWindowPool(
			assignmentsReader: { .safeDefault },
			customizationReader: makeCustomization,
			windowFactory: { _, _ in StubWindowController() },
			sessionLabelReader: { _ in nil },
			sessionPromptSummaryReader: { _ in nil },
			sessionTitleReader: { _, _ in nil },
			retrievedSessionTitleReader: { _ in nil },
			retrievedSessionTitleWriter: { _, _ in },
			hiddenKeysLoader: { [] },
			hiddenKeysSaver: { _ in },
			shadowDivergenceHandler: { recorded.append($0) }
		)

		let snapshot = PerPlatformSnapshot(
			perPlatform: ["claude_code": makeSnapshot(updated: "2026-07-13T10:00:00.000Z")],
			gateBadges: [:], rpgSnapshot: .safeDefault)
		pool.update(snapshot: snapshot)

		XCTAssertTrue(recorded.isEmpty, "an agreeing tick must record zero shadow divergences, got \(recorded)")
	}

	// MARK: - (b) Seeded disagreement

	func testSeededDisagreementRecordsExactlyOneDivergenceWithoutAffectingDrivingWindows() {
		var recorded: [[DivergenceRecord]] = []
		let pool = FloatingPetWindowPool(
			assignmentsReader: { AssignmentsSnapshot(default: "codogotchi", platformOverrides: [:]) },
			customizationReader: makeCustomization,
			windowFactory: { _, _ in StubWindowController() },
			sessionLabelReader: { _ in nil },
			sessionPromptSummaryReader: { _ in nil },
			sessionTitleReader: { _, _ in nil },
			retrievedSessionTitleReader: { _ in nil },
			retrievedSessionTitleWriter: { _, _ in },
			hiddenKeysLoader: { [] },
			hiddenKeysSaver: { _ in },
			shadowDivergenceHandler: { recorded.append($0) }
		)
		// Seed a deliberate, controlled disagreement: perturb ONLY the
		// shadow's own derive input's assignments so `derive`'s resolved
		// `petId` diverges from the driving pipeline's real
		// `currentAssignments` — never touching the real `assignmentsReader`
		// the driving pipeline itself consumes, and never touching `windows`.
		pool.shadowTickInputPerturbation = { input in
			PoolTickInput(
				snapshot: input.snapshot,
				customization: input.customization,
				assignments: AssignmentsSnapshot(default: "perturbed-pet", platformOverrides: [:]),
				currentTime: input.currentTime,
				idleEscalationEnvironment: input.idleEscalationEnvironment,
				sessionLabels: input.sessionLabels,
				knownSessionTitles: input.knownSessionTitles,
				sessionPromptSummaries: input.sessionPromptSummaries,
				hudMode: input.hudMode)
		}

		let snapshot = PerPlatformSnapshot(
			perPlatform: ["claude_code": makeSnapshot(updated: "2026-07-13T10:00:00.000Z")],
			gateBadges: [:], rpgSnapshot: .safeDefault)
		pool.update(snapshot: snapshot)

		XCTAssertEqual(recorded.count, 1, "exactly one shadow-tick divergence batch must be recorded, got \(recorded)")
		XCTAssertEqual(
			recorded.first?.count, 1, "exactly one field-level divergence record, got \(String(describing: recorded.first))"
		)
		XCTAssertEqual(recorded.first?.first?.fieldPath, "petId")
		XCTAssertEqual(
			Set(pool.activeOrigins), ["claude_code"],
			"the driving pipeline's windows must be unaffected by the shadow's seeded disagreement")
	}
}

import XCTest

@testable import Codogotchi

private func pushSnapshot(
	state: ActivityState = .implementing,
	updated: String,
	origin: String? = nil
) -> StateSnapshot {
	StateSnapshot(
		schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
		activityState: state,
		updatedAt: updated,
		sourceEvent: origin.map { SourceEvent(origin: $0, kind: "tool", name: nil) },
		attention: nil)
}

private func pushCustomization(
	modes: [String: PlatformMode] = [:],
	sessionPets: [String: Bool] = [:],
	monochrome: Bool = false
) -> CustomizationSnapshot {
	CustomizationSnapshot(
		platformModes: modes, idleDismissTtlSeconds: 300,
		menubarIconMonochrome: monochrome, combinedMinimalistEnabled: false,
		minimalistBadgeScale: 1, sessionPetsEnabled: sessionPets,
		idleImpatientSeconds: 300, idleFrustratedSeconds: 600)
}

private func pushTick(
	_ states: [WindowKey: StateSnapshot],
	identities: [WindowKey: RenderKeyIdentity] = [:],
	customization: CustomizationSnapshot,
	memory: PoolMemory,
	labels: [WindowKey: String] = [:],
	titles: [WindowKey: String] = [:],
	summaries: [WindowKey: String] = [:],
	hudMode: PetConfig.RPGHUDMode = .mostRecent
) -> (DesiredWindows, PoolMemory) {
	PoolDerive.derive(
		input: PoolTickInput(
			snapshot: PerPlatformSnapshot(
				perPlatform: states, gateBadges: [:], rpgSnapshot: .safeDefault,
				renderKeyIdentities: identities),
			customization: customization, assignments: .safeDefault,
			currentTime: Date(timeIntervalSinceReferenceDate: 0),
			sessionLabels: labels, knownSessionTitles: titles,
			sessionPromptSummaries: summaries, hudMode: hudMode),
		memory: memory)
}

@MainActor
final class PoolDerivePushTests: XCTestCase {
	func testResolvedIdentityForSessionWindowIsItsOwnKey() {
		let key: WindowKey = "codex:session"
		let (desired, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: pushCustomization(sessionPets: ["codex": true]), memory: PoolMemory())

		XCTAssertEqual(desired.windows[key]?.resolvedIdentity, key)
	}

	func testResolvedIdentityTracksOriginFoldWinnerAndLiveLabel() {
		let customization = pushCustomization()
		let (desired, _) = pushTick(
			[
				"codex:old": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"codex:new": pushSnapshot(updated: "2026-07-01T10:00:01.000Z", origin: "codex"),
			], customization: customization, memory: PoolMemory(),
			labels: ["codex:old": "Old task", "codex:new": "New task"])

		XCTAssertEqual(desired.windows[.origin("codex")]?.resolvedIdentity, "codex:new")
		XCTAssertEqual(desired.windows[.origin("codex")]?.sessionLabel, "New task")
	}

	func testResolvedIdentityAndLabelRotateWithOriginFoldWinner() {
		let customization = pushCustomization()
		var memory = PoolMemory()
		var desired: DesiredWindows
		(desired, memory) = pushTick(
			[
				"codex:old": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"codex:new": pushSnapshot(updated: "2026-07-01T10:00:01.000Z", origin: "codex"),
			], customization: customization, memory: memory,
			labels: ["codex:new": "New task"])
		XCTAssertEqual(desired.windows[.origin("codex")]?.resolvedIdentity, "codex:new")

		(desired, _) = pushTick(
			[
				"codex:old": pushSnapshot(updated: "2026-07-01T10:00:03.000Z", origin: "codex"),
				"codex:new": pushSnapshot(updated: "2026-07-01T10:00:02.000Z", origin: "codex"),
			], customization: customization, memory: memory,
			labels: ["codex:old": "Old task"])
		XCTAssertEqual(desired.windows[.origin("codex")]?.resolvedIdentity, "codex:old")
		XCTAssertEqual(desired.windows[.origin("codex")]?.sessionLabel, "Old task")
	}

	func testFoldedWinnerUsesKnownTitleCacheAndTitleRequestIdentity() {
		let key: WindowKey = "codex:session"
		let identity = RenderKeyIdentity(origin: "codex", sessionId: "session")
		let customization = pushCustomization()
		let (requested, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			identities: [key: identity], customization: customization, memory: PoolMemory())
		XCTAssertEqual(requested.titleResolutionRequests, [identity])

		var memory = PoolMemory()
		memory.resolvedSessionTitles[key] = "Cached task"
		let (cached, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			identities: [key: identity], customization: customization, memory: memory,
			titles: [key: "Known task"])
		XCTAssertEqual(cached.windows[.origin("codex")]?.sessionLabel, "Known task")
		XCTAssertTrue(cached.titleResolutionRequests.isEmpty)
	}

	func testResolvedIdentityForSoloDefaultOriginFallsBackToOwnKey() {
		let (desired, _) = pushTick(
			["codex": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: pushCustomization(), memory: PoolMemory())

		XCTAssertEqual(desired.windows[.origin("codex")]?.resolvedIdentity, .origin("codex"))
	}

	func testResolvedIdentityTracksCombinedWinnerAndLiveLabel() {
		let customization = pushCustomization(modes: ["codex": .combined, "cursor": .combined])
		let (desired, _) = pushTick(
			[
				"codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"cursor:b": pushSnapshot(updated: "2026-07-01T10:00:01.000Z", origin: "cursor"),
			], customization: customization, memory: PoolMemory(),
			labels: ["codex:a": "Codex task", "cursor:b": "Cursor task"])

		XCTAssertEqual(desired.windows[.combined]?.resolvedIdentity, "cursor:b")
		XCTAssertEqual(desired.windows[.combined]?.sessionLabel, "Cursor task")
	}

	func testCombinedWinnerUsesFreshestUpdateAndIdleUsesCombinedDefaults() {
		let customization = pushCustomization(modes: ["codex": .combined, "cursor": .combined])
		let (desired, _) = pushTick(
			[
				"codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"cursor:b": pushSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z", origin: "cursor"),
			], customization: customization, memory: PoolMemory())
		XCTAssertEqual(desired.windows[.combined]?.activityState, .idle)
		XCTAssertEqual(desired.windows[.combined]?.platformChip, "combined")
		XCTAssertEqual(desired.windows[.combined]?.sessionLabel, "Combined")
	}

	func testCombinedTransientGapRetainsLastActiveWindowAndTimer() {
		let customization = pushCustomization(modes: ["codex": .combined])
		var memory = PoolMemory()
		var desired: DesiredWindows
		(desired, memory) = pushTick(
			["codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: customization, memory: memory)
		XCTAssertNotNil(desired.windows[.combined]?.promptTimerStatus)
		(desired, memory) = pushTick([:], customization: customization, memory: memory)
		XCTAssertNotNil(desired.windows[.combined], "last-active combined survives a transient empty poll")
		XCTAssertEqual(desired.windows[.combined]?.resolvedIdentity, "codex:a")
		XCTAssertEqual(desired.windows[.combined]?.hasActiveSession, true)

		let own = pushCustomization(modes: ["codex": .own])
		(desired, memory) = pushTick([:], customization: own, memory: memory)
		XCTAssertNil(desired.windows[.combined], "mode-switch-away is unconditional, unlike a transient gap")
		XCTAssertNil(memory.promptTimers[.combined])
	}

	func testSourceLessActiveCombinedStillUsesCombinedLabel() {
		let customization = pushCustomization(modes: ["codex": .combined])
		let (desired, _) = pushTick(
			["codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, memory: PoolMemory())
		XCTAssertNil(desired.windows[.combined]?.platformChip)
		XCTAssertEqual(desired.windows[.combined]?.sessionLabel, "Combined")
	}

	func testDirectPayloadPrecedenceAndMissingTitleRequest() {
		let key: WindowKey = "codex:abc"
		let identity = RenderKeyIdentity(origin: "codex", sessionId: "abc")
		let customization = pushCustomization(sessionPets: ["codex": true])
		let (desired, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			identities: [key: identity], customization: customization, memory: PoolMemory(),
			summaries: [key: "Refactor the renderer"])
		XCTAssertEqual(desired.windows[key]?.sessionNumber, 1)
		XCTAssertEqual(desired.windows[key]?.sessionLabel, "Session 1")
		XCTAssertEqual(desired.windows[key]?.sessionTooltip, "Refactor the renderer")
		XCTAssertEqual(desired.titleResolutionRequests, [identity])

		let (renamed, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			identities: [key: identity], customization: customization, memory: PoolMemory(),
			labels: [key: "My task"], titles: [key: "Generated title"])
		XCTAssertEqual(renamed.windows[key]?.sessionLabel, "My task")
		XCTAssertTrue(renamed.titleResolutionRequests.isEmpty)
	}

	func testHudBearerStaysStickyAcrossBackgroundUpdate() {
		let customization = pushCustomization()
		var memory = PoolMemory()
		var desired: DesiredWindows
		(desired, memory) = pushTick(
			["codex": pushSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, memory: memory)
		XCTAssertTrue(desired.windows["codex"]?.hudEnabled == true)
		(desired, _) = pushTick(
			[
				"codex": pushSnapshot(updated: "2026-07-01T10:00:00.000Z"),
				"cursor": pushSnapshot(updated: "2026-07-01T10:00:01.000Z"),
			], customization: customization, memory: memory)
		XCTAssertTrue(desired.windows["codex"]?.hudEnabled == true)
		XCTAssertFalse(desired.windows["cursor"]?.hudEnabled == true)
	}

	func testMonochromeAndIdleEscalationOutputsArePureInputDerived() {
		var memory = PoolMemory()
		let customization = pushCustomization(monochrome: true)
		let (desired, next) = pushTick([:], customization: customization, memory: memory)
		XCTAssertEqual(desired.monochromeChanged, true)
		XCTAssertEqual(desired.idleEscalationConfig.impatientAfter, 300)
		memory = next
		let (unchanged, _) = pushTick([:], customization: customization, memory: memory)
		XCTAssertNil(unchanged.monochromeChanged)
	}
}

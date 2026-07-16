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

	/// Production never feeds `derive` raw per-session keys directly for a
	/// folded platform — `LivePollingDriver` calls `resolveRenderKeys`
	/// upstream first, which collapses sessions-off/combined origins down to
	/// ONE already-folded entry (`.origin(origin)` or `.combined`) before
	/// `PerPlatformSnapshot` is ever built, carrying `renderKeyIdentities`
	/// alongside so the winning session behind that unchanged key is still
	/// knowable. `testResolvedIdentityAndLabelRotateWithOriginFoldWinner`
	/// above exercises `derive`'s OWN internal re-fold of raw per-session
	/// keys (a different, also-real input shape — `pool.update()` can be
	/// called directly with un-folded snapshots too) and happens to work
	/// even pre-fix, because that shape's `winnerEntry.key` already resolves
	/// to the actual raw session. This test reproduces the shape that
	/// exposed the reported bug: the RENDER KEY itself never changes
	/// (`.origin("codex")` both ticks), only the identity behind it does —
	/// exactly what a real sessions-off fold winner rotation looks like once
	/// `resolveRenderKeys` has already run.
	func testOriginFoldWinnerRotationResetsTimerWhenIdentityChangesUnderAnUnchangedKey() {
		let customization = pushCustomization()
		var memory = PoolMemory()
		let foldedKey: WindowKey = .origin("codex")

		(_, memory) = pushTick(
			[foldedKey: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			identities: [foldedKey: RenderKeyIdentity(origin: "codex", sessionId: "session-a")],
			customization: customization, memory: memory)
		XCTAssertEqual(
			memory.promptTimers[foldedKey]?.currentStatus()?.startedAt,
			StateJsonReader.parseISO8601Date("2026-07-01T10:00:00.000Z"))

		// Same key, same in-flight state, but resolveRenderKeys has now
		// elected a DIFFERENT session as the winner — the pre-fix tracker,
		// already running under `foldedKey`, would see nothing but ordinary
		// continuation here and never restart.
		(_, memory) = pushTick(
			[foldedKey: pushSnapshot(updated: "2026-07-01T10:05:00.000Z", origin: "codex")],
			identities: [foldedKey: RenderKeyIdentity(origin: "codex", sessionId: "session-b")],
			customization: customization, memory: memory)

		XCTAssertEqual(
			memory.promptTimers[foldedKey]?.currentStatus()?.startedAt,
			StateJsonReader.parseISO8601Date("2026-07-01T10:05:00.000Z"),
			"a winner-identity change under the same render key must restart the timer from the new winner's own updatedAt")
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

	/// Production `resolveRenderKeys` keys identities by the *fold* key
	/// (`.origin` / `.combined`), not the winning session key. Title
	/// resolution must still request the winner's LLM title on a fresh
	/// sessions-off prompt — otherwise the session-label badge stays empty
	/// until the user toggles sessions on (which caches the title) and back.
	func testSessionsOffOriginFoldRequestsTitleWhenIdentityKeyedByFold() {
		let fold: WindowKey = .origin("cursor")
		let identity = RenderKeyIdentity(origin: "cursor", sessionId: "fresh-uuid")
		let customization = pushCustomization(modes: ["cursor": .minimalist])
		let (desired, _) = pushTick(
			[fold: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "cursor")],
			identities: [fold: identity], customization: customization, memory: PoolMemory())

		XCTAssertEqual(desired.windows[fold]?.resolvedIdentity, "cursor:fresh-uuid")
		XCTAssertEqual(desired.titleResolutionRequests, [identity])
		XCTAssertNil(desired.windows[fold]?.sessionLabel)
	}

	func testSessionsOffCombinedFoldRequestsTitleWhenIdentityKeyedByFold() {
		let identity = RenderKeyIdentity(origin: "cursor", sessionId: "fresh-uuid")
		let customization = pushCustomization(modes: ["cursor": .combined])
		let (desired, _) = pushTick(
			[.combined: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "cursor")],
			identities: [.combined: identity], customization: customization, memory: PoolMemory())

		XCTAssertEqual(desired.windows[.combined]?.resolvedIdentity, "cursor:fresh-uuid")
		XCTAssertEqual(desired.windows[.combined]?.modeIndicatorBadge, "Combined")
		XCTAssertEqual(desired.titleResolutionRequests, [identity])
		XCTAssertNil(desired.windows[.combined]?.sessionLabel)
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

	func testCombinedWinnerUsesFreshestUpdateAndIdleUsesCombinedModeChip() {
		let customization = pushCustomization(modes: ["codex": .combined, "cursor": .combined])
		let (desired, _) = pushTick(
			[
				"codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"cursor:b": pushSnapshot(state: .idle, updated: "2026-07-01T10:00:01.000Z", origin: "cursor"),
			], customization: customization, memory: PoolMemory())
		XCTAssertEqual(desired.windows[.combined]?.activityState, .idle)
		XCTAssertEqual(desired.windows[.combined]?.platformChip, "combined")
		XCTAssertEqual(desired.windows[.combined]?.modeIndicatorBadge, "Combined")
		XCTAssertNil(
			desired.windows[.combined]?.sessionLabel,
			"idle Combined must not reuse mode-chip copy as the session label")
	}

	/// A prior version of `derive` observed the combined winner's state into
	/// one tracker shared across every session that has ever won the
	/// `.combined` slot (`memory.promptTimers[.combined]`). Since
	/// `PromptTimerTracker` only restarts on an idle/session_start/first-
	/// observation transition, a still-running shared tracker never noticed
	/// the underlying winning SESSION had changed on a rotation between two
	/// different in-flight sessions — the chip kept reporting the previous
	/// winner's elapsed time under the new winner's name. The fix reads
	/// `promptTimerStatus` from the winning RAW key's own tracker
	/// (`memory.promptTimers[winnerEntry.key]`), which Step 2 already
	/// independently observes for every visible key regardless of fold
	/// outcome — so `.combined` itself is never a key in `promptTimers` at
	/// all post-fix.
	func testCombinedWinnerRotationUsesNewWinnersOwnTimerNotAStaleSharedOne() {
		let customization = pushCustomization(modes: ["codex": .combined, "cursor": .combined])
		var memory = PoolMemory()

		// Tick 1: codex:a is the only entry, wins combined, starts its own
		// tracker running from its own updatedAt.
		(_, memory) = pushTick(
			["codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: customization, memory: memory)
		XCTAssertEqual(
			memory.promptTimers["codex:a"]?.currentStatus()?.startedAt,
			StateJsonReader.parseISO8601Date("2026-07-01T10:00:00.000Z"))

		// Tick 2: cursor:b appears with a later updatedAt and becomes the new
		// combined winner; codex:a is still present (unchanged, still
		// "running" in its own right) so the OLD shared-tracker code path
		// would have kept ticking from codex:a's tick-1 start instead of
		// starting fresh for cursor:b.
		var desired: DesiredWindows
		(desired, memory) = pushTick(
			[
				"codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"cursor:b": pushSnapshot(updated: "2026-07-01T10:05:00.000Z", origin: "cursor"),
			], customization: customization, memory: memory)

		XCTAssertEqual(desired.windows[.combined]?.resolvedIdentity, "cursor:b")
		XCTAssertNil(
			memory.promptTimers[.combined],
			"no tracker should ever be keyed literally .combined post-fix")
		XCTAssertEqual(
			memory.promptTimers["cursor:b"]?.currentStatus()?.startedAt,
			StateJsonReader.parseISO8601Date("2026-07-01T10:05:00.000Z"),
			"the new winner's timer must start from ITS OWN updatedAt, not codex:a's")
		XCTAssertEqual(
			memory.promptTimers["codex:a"]?.currentStatus()?.startedAt,
			StateJsonReader.parseISO8601Date("2026-07-01T10:00:00.000Z"),
			"the demoted session keeps its own independent timer untouched")
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

	func testSourceLessActiveCombinedKeepsModeChipWithoutSessionLabelFallback() {
		let customization = pushCustomization(modes: ["codex": .combined])
		let (desired, _) = pushTick(
			["codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z")],
			customization: customization, memory: PoolMemory())
		XCTAssertNil(desired.windows[.combined]?.platformChip)
		XCTAssertEqual(desired.windows[.combined]?.modeIndicatorBadge, "Combined")
		XCTAssertNil(desired.windows[.combined]?.sessionLabel)
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

	// MARK: - Mode-indicator badge (P19.04)

	func testModeIndicatorBadgeAbsentForSoloSessionWindow() {
		let key: WindowKey = "codex:session"
		let (desired, _) = pushTick(
			[key: pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: pushCustomization(sessionPets: ["codex": true]), memory: PoolMemory())

		XCTAssertNil(desired.windows[key]?.modeIndicatorBadge)
	}

	func testModeIndicatorBadgeAlwaysShowsPlatformNameForPlatformOnlyOrigin() {
		let (desired, _) = pushTick(
			["codex": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex")],
			customization: pushCustomization(), memory: PoolMemory())

		XCTAssertEqual(desired.windows[.origin("codex")]?.modeIndicatorBadge, "Codex")
	}

	func testModeIndicatorBadgeShowsPlatformNameForOriginFoldWithMultipleSessions() {
		let customization = pushCustomization()
		let (desired, _) = pushTick(
			[
				"codex:old": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"codex:new": pushSnapshot(updated: "2026-07-01T10:00:01.000Z", origin: "codex"),
			], customization: customization, memory: PoolMemory(),
			labels: ["codex:old": "Old task", "codex:new": "New task"])

		XCTAssertEqual(desired.windows[.origin("codex")]?.modeIndicatorBadge, "Codex")
		XCTAssertEqual(desired.windows[.origin("codex")]?.sessionLabel, "New task")
	}

	func testModeIndicatorBadgeShowsCombinedTextForCombinedWindow() {
		let customization = pushCustomization(modes: ["codex": .combined, "cursor": .combined])
		let (desired, _) = pushTick(
			[
				"codex:a": pushSnapshot(updated: "2026-07-01T10:00:00.000Z", origin: "codex"),
				"cursor:b": pushSnapshot(updated: "2026-07-01T10:00:01.000Z", origin: "cursor"),
			], customization: customization, memory: PoolMemory(),
			labels: ["codex:a": "Codex task", "cursor:b": "Cursor task"])

		XCTAssertEqual(desired.windows[.combined]?.modeIndicatorBadge, "Combined")
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

import XCTest

@testable import Codogotchi

/// Behavior contract for P2.07 live polling: a 1Hz `LivePollingDriver` reads
/// `state.json` from the configured `pollingTarget`, calls the renderer for
/// `(activityState, visualMode)` transitions, and pushes tooltip strings that
/// match the canonical copy in `docs/contracts/animation-state-vocabulary.md`
/// character-for-character.
///
/// Tests drive the driver via a deterministic `tickForTesting()` seam instead
/// of the production 1-second `Timer` so they do not stall `xcodebuild ... test`.
@MainActor
final class LivePollingTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func fixturesDirectory() -> URL {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/state-json")
	}

	private func makeSandboxPath() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-live-tests")
			.appendingPathComponent(UUID().uuidString)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.appendingPathComponent("state.json")
	}

	private func makeSiblingGatePath(for statePath: URL) -> URL {
		statePath.deletingLastPathComponent().appendingPathComponent("gate.json")
	}

	private func makeSiblingDeliveryContextPath(for statePath: URL) -> URL {
		statePath.deletingLastPathComponent().appendingPathComponent("delivery-context.json")
	}

	private func copyFixture(_ name: String, to target: URL) throws {
		let src = fixturesDirectory().appendingPathComponent(name)
		let data = try Data(contentsOf: src)
		try data.write(to: target, options: .atomic)
	}

	// MARK: - Recording sinks

	private final class Recorder {
		var renders: [(ActivityState, VisualMode)] = []
		var tooltips: [String?] = []
		var gateBadges: [GateBadgeContent?] = []
		var platforms: [String?] = []
		var rpgStates: [(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int)] = []
	}

	private func makeDriver(
		target: URL,
		recorder: Recorder,
		gatePath: URL? = nil,
		deliveryContextPath: URL? = nil,
		previewStatePath: URL? = nil,
		previewGatePath: URL? = nil,
		transitionLog: TransitionLog? = nil,
		now: @escaping () -> Date = { Date() }
	) -> LivePollingDriver {
		let driver = LivePollingDriver(
			pollingTargetPath: target.path,
			gatePath: gatePath?.path,
			deliveryContextPath: deliveryContextPath?.path,
			previewStatePath: previewStatePath?.path,
			previewGatePath: previewGatePath?.path,
			apply: { state, mode in recorder.renders.append((state, mode)) },
			setTooltip: { tip in recorder.tooltips.append(tip) },
			transitionLog: transitionLog,
			now: now
		)
		driver.applyGateBadge = { recorder.gateBadges.append($0) }
		driver.applyPlatform = { recorder.platforms.append($0) }
		driver.applyRPGState = { recorder.rpgStates.append(($0, $1, $2, $3)) }
		return driver
	}

	/// Minimal v5 `state.json` payload for decay tests: only the fields the
	/// reader requires plus the two the decay engine reads.
	private func writeV5StateJson(
		_ target: URL,
		halfHearts: Int,
		lastActivityAt: String?,
		activityState: String = "idle"
	) throws {
		let lastActivity =
			lastActivityAt.map { "\"\($0)\"" } ?? "null"
		try """
			{"schema_version":5,"activity_state":"\(activityState)","updated_at":"2026-01-01T00:00:00Z","level":3,"level_fraction":0.5,"half_hearts":\(halfHearts),"last_activity_at":\(lastActivity)}
			""".write(to: target, atomically: true, encoding: .utf8)
	}

	private func writePreviewStateJson(
		_ target: URL,
		state: String,
		expiresAt: String = "2099-01-01T00:00:00.000Z"
	) throws {
		try """
			{"activity_state":"\(state)","since":"2026-01-01T00:00:00Z","expires_at":"\(expiresAt)"}
			""".write(to: target, atomically: true, encoding: .utf8)
	}

	private func writePreviewGateJson(
		_ target: URL,
		gate: String,
		expiresAt: String = "2099-01-01T00:00:00.000Z"
	) throws {
		try """
			{"gate":"\(gate)","since":"2026-01-01T00:00:00Z","expires_at":"\(expiresAt)"}
			""".write(to: target, atomically: true, encoding: .utf8)
	}

	private func writeGateJson(
		_ target: URL,
		gate: String,
		expiresAt: String,
		ticketId: String = "P7.01"
	) throws {
		try """
			{"gate":"\(gate)","since":"2026-01-01T00:00:00Z","expires_at":"\(expiresAt)","plan_key":"phase-07","ticket_id":"\(ticketId)"}
			""".write(to: target, atomically: true, encoding: .utf8)
	}

	private func writeDeliveryContextJson(
		_ target: URL,
		status: String = "active",
		repoRoot: String = "/repo/soa",
		gate: String = "review_clean",
		ticketId: String = "P7.01",
		leaseExpiresAt: String = "2099-01-01T00:00:00.000Z"
	) throws {
		try """
			{"owner":"soa","status":"\(status)","repo_root":"\(repoRoot)","plan_key":"phase-07","ticket_id":"\(ticketId)","last_gate":"\(gate)","updated_at":"2026-01-01T00:00:00Z","lease_expires_at":"\(leaseExpiresAt)"}
			""".write(to: target, atomically: true, encoding: .utf8)
	}

	// MARK: - Three failure visuals

	func testFileNotFoundRendersIdleFullColorWithNoHookTooltip() {
		let recorder = Recorder()
		let target = makeSandboxPath()
		// Intentionally do NOT write any file.
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 },
			[.idle],
			"missing file must render .idle"
		)
		// Fresh install (hooks wired, no prompt run yet) is not an error: the pet
		// shows full-color idle, not desaturated. See commit 9262e2e.
		XCTAssertEqual(
			recorder.renders.map { $0.1 },
			[.normal],
			"missing file must render full-color .normal"
		)
		XCTAssertEqual(
			recorder.tooltips,
			[LivePollingTooltips.noHookDetected],
			"missing file tooltip must match the canonical no-hook copy"
		)
	}

	func testSchemaNewerRendersIdleDesaturatedWithInterpolatedSchemaNewerTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("schema-newer.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.idle])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.desaturated])
		XCTAssertEqual(
			recorder.tooltips,
			[LivePollingTooltips.schemaNewer(got: 99, expected: 6)],
			"schema-newer tooltip must format both version integers via the canonical template"
		)
		// Spot-check the literal substring so an accidental template-string drift
		// (e.g., dropping the trailing 'Update the menu bar app.') is caught
		// without needing to re-implement the template assembly here.
		XCTAssertEqual(
			recorder.tooltips.first ?? nil,
			"state.json schema_version is v99; this app supports v6. Update the menu bar app."
		)
	}

	func testFutureReviveUntilRendersTicketStartedPlaceholderRow() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		// v6 payload with an active revive window; base activity is implementing.
		try #"{"schema_version":6,"activity_state":"implementing","updated_at":"2026-06-08T00:00:00.000Z","level":3,"level_fraction":0.5,"half_hearts":4,"last_activity_at":"2026-06-08T00:00:00.000Z","revive_until":"2099-01-01T00:00:00.000Z"}"#
			.write(to: target, atomically: true, encoding: .utf8)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 }, [.ticketStarted],
			"an active revive window must render the ticket_started placeholder row over the hook state")
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.normal])
	}

	func testExpiredReviveUntilRendersBaseHookState() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try #"{"schema_version":6,"activity_state":"implementing","updated_at":"2026-06-08T00:00:00.000Z","level":3,"level_fraction":0.5,"half_hearts":4,"last_activity_at":"2026-06-08T00:00:00.000Z","revive_until":"2020-01-01T00:00:00.000Z"}"#
			.write(to: target, atomically: true, encoding: .utf8)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 }, [.implementing],
			"a lapsed revive window must fall through to the hook state")
	}

	func testSchemaMissingRendersIdleDesaturatedWithSchemaMissingTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try #"{"activity_state": "idle", "updated_at": "x"}"#
			.write(to: target, atomically: true, encoding: .utf8)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.idle])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.desaturated])
		XCTAssertEqual(
			recorder.tooltips,
			[LivePollingTooltips.schemaMissing],
			"missing schema_version tooltip must match the canonical 'may be too old' copy"
		)
	}

	func testMalformedJsonRendersIdleDesaturatedWithSchemaMissingTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try "{ not json".write(to: target, atomically: true, encoding: .utf8)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.idle])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.desaturated])
		XCTAssertEqual(
			recorder.tooltips,
			[LivePollingTooltips.schemaMissing],
			"malformed payload must route to the same 'too old' tooltip as schema-missing"
		)
	}

	// MARK: - Happy path

	func testImplementingPayloadRendersImplementingNormalWithNoTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("implementing.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.implementing])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.normal])
		XCTAssertEqual(
			recorder.tooltips,
			[nil],
			"normal-mode renders must clear the tooltip (no failure copy to surface)"
		)
		XCTAssertEqual(recorder.gateBadges, [nil], "first tick still emits an explicit nil gate badge")
	}

	func testPreviewStateOverrideWinsWithoutTelemetryOrTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let previewStatePath = target.deletingLastPathComponent().appendingPathComponent(
			"preview-state.json")
		let transitionLogPath = target.deletingLastPathComponent().appendingPathComponent(
			"state-transitions.log")
		try copyFixture("implementing.json", to: target)
		try writePreviewStateJson(previewStatePath, state: "thinking")
		let transitionLog = TransitionLog(path: transitionLogPath)
		let driver = makeDriver(
			target: target,
			recorder: recorder,
			previewStatePath: previewStatePath,
			transitionLog: transitionLog
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.thinking])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.normal])
		XCTAssertEqual(recorder.tooltips, [nil])
		XCTAssertEqual(
			recorder.gateBadges,
			[nil],
			"preview mode clears the persistent badge lane so live delivery context does not bleed into animation testing"
		)
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: transitionLogPath.path),
			"preview overrides must not append to the durable transition log"
		)
	}

	func testPreviewGateOverrideWinsOverLiveStateWithoutBadge() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let previewGatePath = target.deletingLastPathComponent().appendingPathComponent(
			"preview-gate.json")
		try copyFixture("implementing.json", to: target)
		try writePreviewGateJson(previewGatePath, gate: "ticket_started")
		let driver = makeDriver(
			target: target,
			recorder: recorder,
			previewGatePath: previewGatePath
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.ticketStarted])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.normal])
		XCTAssertEqual(recorder.tooltips, [nil])
		XCTAssertEqual(recorder.gateBadges, [nil])
	}

	func testExpiredGateFallsThroughToHookStateButBadgePersists() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let gatePath = makeSiblingGatePath(for: target)
		let deliveryContextPath = makeSiblingDeliveryContextPath(for: target)
		try copyFixture("implementing.json", to: target)
		try writeGateJson(
			gatePath,
			gate: "review_clean",
			expiresAt: "2020-01-01T00:00:00.000Z"
		)
		try writeDeliveryContextJson(deliveryContextPath)
		let driver = makeDriver(
			target: target,
			recorder: recorder,
			gatePath: gatePath,
			deliveryContextPath: deliveryContextPath
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.implementing])
		XCTAssertEqual(
			recorder.gateBadges,
			[GateBadgeContent(ticketId: "P7.01", gate: "review_clean")],
			"delivery-context.json, not expired gate.json, owns the persistent badge"
		)
	}

	func testTicketCompletedGateClearsBadgeWhileStillDrivingAnimation() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let gatePath = makeSiblingGatePath(for: target)
		let deliveryContextPath = makeSiblingDeliveryContextPath(for: target)
		try copyFixture("implementing.json", to: target)
		try writeGateJson(
			gatePath,
			gate: "ticket_completed",
			expiresAt: "2099-01-01T00:00:00.000Z"
		)
		try writeDeliveryContextJson(deliveryContextPath, status: "cleared", gate: "ticket_completed")
		let driver = makeDriver(
			target: target,
			recorder: recorder,
			gatePath: gatePath,
			deliveryContextPath: deliveryContextPath
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.ticketCompleted])
		XCTAssertEqual(
			recorder.gateBadges,
			[nil],
			"ticket_completed clears the persistent badge lane instead of leaving a stale completed-ticket chip"
		)
	}

	func testDifferentRepoHookActivitySuppressesDeliveryContextBadge() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let deliveryContextPath = makeSiblingDeliveryContextPath(for: target)
		try #"""
		{
		  "schema_version": 1,
		  "activity_state": "implementing",
		  "hp_overlay": "thriving",
		  "hp": 90,
		  "updated_at": "2026-05-29T00:00:00.000Z",
		  "source_event": {
		    "origin": "codex",
		    "kind": "tool_use",
		    "name": "Bash",
		    "repo_root": "/repo/non-soa"
		  }
		}
		"""#.write(to: target, atomically: true, encoding: .utf8)
		try writeDeliveryContextJson(deliveryContextPath, repoRoot: "/repo/soa")
		let driver = makeDriver(
			target: target,
			recorder: recorder,
			deliveryContextPath: deliveryContextPath
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.gateBadges, [nil])
	}

	// MARK: - Transition

	func testFileSwapTriggersSingleNewRenderOnNextTick() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("idle.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()
		try copyFixture("implementing.json", to: target)
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 },
			[.idle, .implementing],
			"swapping idle.json → implementing.json must produce exactly one new render on the next tick"
		)
		XCTAssertEqual(
			recorder.renders.map { $0.1 },
			[.normal, .normal]
		)
	}

	// MARK: - Stale handling: explicitly does nothing

	func testStaleUpdatedAtRendersNormallyWithoutSpecialHandling() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		// Hours-old `updated_at` with otherwise valid idle payload. Per the
		// product plan, staleness gets no special handling — the renderer
		// receives `.idle` in `.normal` mode just like a fresh idle payload.
		try #"""
		{
		  "schema_version": 1,
		  "activity_state": "idle",
		  "hp_overlay": "thriving",
		  "hp": 90,
		  "updated_at": "2020-01-01T00:00:00.000Z",
		  "source_event": { "origin": "sync", "kind": "sync_response", "name": "stale" }
		}
		"""#.write(to: target, atomically: true, encoding: .utf8)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.idle])
		XCTAssertEqual(
			recorder.renders.map { $0.1 },
			[.normal],
			"stale updated_at must not trigger .desaturated — no upper bound on staleness in v1"
		)
	}

	// MARK: - Avoidable churn

	func testRepeatedTicksWithUnchangedStateDoNotEmitDuplicateRenders() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("implementing.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()
		driver.tickForTesting()
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.count,
			1,
			"identical (state, visualMode) across ticks must collapse to a single apply call"
		)
	}

	// MARK: - Platform attribution

	func testPlatformOriginEmittedFromSourceEvent() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("implementing.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.platforms,
			["claude_code"],
			"source_event.origin must be forwarded to the platform sink"
		)
	}

	func testPlatformOriginSuppressesUnchangedRepeats() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("implementing.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()
		driver.tickForTesting()
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.platforms,
			["claude_code"],
			"an unchanged origin across ticks must emit only once"
		)
	}

	func testPlatformOriginClearsToNilOnReadFailure() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try copyFixture("implementing.json", to: target)
		let driver = makeDriver(target: target, recorder: recorder)

		driver.tickForTesting()
		try FileManager.default.removeItem(at: target)
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.platforms,
			["claude_code", nil],
			"a read failure must clear the attributed platform so no stale chip lingers"
		)
	}

	// MARK: - Half-heart decay on the poll loop (P10.07)

	func testDecaysDisplayedHalfHeartsBelowWrittenValueWhileIdle() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let lastActivity = "2026-06-04T00:00:00.000Z"
		// Written value is full (6); 16h elapsed since last activity → floor(16/8)
		// = 2 half-hearts of decay, so the HUD must show 4 even though no new hook
		// write occurred (file unchanged between the activity write and now).
		try writeV5StateJson(target, halfHearts: 6, lastActivityAt: lastActivity)
		let sixteenHoursLater = ISO8601DateFormatter().date(from: "2026-06-04T16:00:00Z")!
		let driver = makeDriver(target: target, recorder: recorder, now: { sixteenHoursLater })

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.rpgStates.last?.halfHearts, 4,
			"16h idle decays 2 half-hearts below the written 6 with no new hook write")
	}

	func testNullLastActivityAtDoesNotDecay() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		// Fresh profile: last_activity_at is null → no decay regardless of clock.
		try writeV5StateJson(target, halfHearts: 6, lastActivityAt: nil)
		let driver = makeDriver(
			target: target, recorder: recorder,
			now: { ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z")! })

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.rpgStates.last?.halfHearts, 6,
			"null last_activity_at must hold the written value (no decay)")
	}

	func testDecayCrossingBoundaryReEmitsWithoutFileChange() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let lastActivity = "2026-06-04T00:00:00.000Z"
		try writeV5StateJson(target, halfHearts: 6, lastActivityAt: lastActivity)
		// Advance the injected clock across the 8h decay boundary between ticks
		// with no file write — proves decay rides the poll loop, not a file change
		// (the codogotchi-10 change-gate-starvation pattern does not apply because
		// the displayed value is recomputed against `now` every tick).
		var current = ISO8601DateFormatter().date(from: "2026-06-04T07:59:00Z")!
		let driver = makeDriver(target: target, recorder: recorder, now: { current })

		driver.tickForTesting()
		XCTAssertEqual(recorder.rpgStates.last?.halfHearts, 6, "before 8h: full")

		current = ISO8601DateFormatter().date(from: "2026-06-04T08:01:00Z")!
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.rpgStates.last?.halfHearts, 5,
			"crossing 8h must emit a fresh decayed value even though state.json never changed")
	}
}

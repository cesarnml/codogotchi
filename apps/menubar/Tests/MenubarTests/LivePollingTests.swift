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

	/// Returns a `state.d/` directory URL under a fresh per-test tmp dir.
	/// The directory itself is NOT pre-created so fileNotFound tests work.
	private func makeSandboxPath() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-live-tests")
			.appendingPathComponent(UUID().uuidString)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.appendingPathComponent("state.d")
	}

	/// Sibling gate path — parent of the state.d directory.
	private func makeSiblingGatePath(for stateDir: URL) -> URL {
		stateDir.deletingLastPathComponent().appendingPathComponent("gate.json")
	}

	private func makeSiblingDeliveryContextPath(for stateDir: URL) -> URL {
		stateDir.deletingLastPathComponent().appendingPathComponent("delivery-context.json")
	}

	/// Creates `target/` dir and writes fixture as the single slice file.
	private func copyFixture(_ name: String, to target: URL) throws {
		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
		let src = fixturesDirectory().appendingPathComponent(name)
		let data = try Data(contentsOf: src)
		try data.write(to: target.appendingPathComponent("default.json"), options: .atomic)
	}

	/// Creates `target/` dir and writes raw JSON string as the single slice file.
	private func writeSlice(_ json: String, to target: URL) throws {
		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
		try json.write(to: target.appendingPathComponent("default.json"), atomically: true, encoding: .utf8)
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
		rpgStatePath: URL? = nil,
		gatePath: URL? = nil,
		deliveryContextPath: URL? = nil,
		previewStatePath: URL? = nil,
		previewGatePath: URL? = nil,
		transitionLog: TransitionLog? = nil,
		reader: LivePollingDriver.Reader? = nil,
		now: @escaping () -> Date = { Date() }
	) -> LivePollingDriver {
		let driver = LivePollingDriver(
			pollingTargetPath: target.path,
			rpgStatePath: rpgStatePath?.path,
			gatePath: gatePath?.path,
			deliveryContextPath: deliveryContextPath?.path,
			previewStatePath: previewStatePath?.path,
			previewGatePath: previewGatePath?.path,
			apply: { state, mode in recorder.renders.append((state, mode)) },
			setTooltip: { tip in recorder.tooltips.append(tip) },
			reader: reader ?? StateJsonReader.readDirectory(at:),
			transitionLog: transitionLog,
			now: now
		)
		driver.applyGateBadge = { recorder.gateBadges.append($0) }
		driver.applyPlatform = { recorder.platforms.append($0) }
		driver.applyRPGState = { recorder.rpgStates.append(($0, $1, $2, $3)) }
		return driver
	}

	private func writeRpgStateJson(
		_ url: URL,
		halfHearts: Int = 6,
		lastActivityAt: String? = nil,
		reviveUntil: String? = nil,
		level: Int = 1,
		levelFraction: Double = 0.0
	) throws {
		let lastActivity = lastActivityAt.map { "\"\($0)\"" } ?? "null"
		let revive = reviveUntil.map { "\"\($0)\"" } ?? "null"
		try """
			{"level":\(level),"level_fraction":\(levelFraction),"half_hearts":\(halfHearts),"active_minutes":0,"last_activity_at":\(lastActivity),"revive_until":\(revive)}
			""".write(to: url, atomically: true, encoding: .utf8)
	}

	/// Writes a v8-format slice for tests that need to drive activity state.
	/// RPG fields embedded in the JSON (level, half_hearts, last_activity_at) are silently
	/// ignored by SlicePayload in v8 — see writeRpgStateJson for RPG test inputs.
	private func writeV5StateJson(
		_ target: URL,
		halfHearts: Int,
		lastActivityAt: String?,
		activityState: String = "idle"
	) throws {
		let lastActivity =
			lastActivityAt.map { "\"\($0)\"" } ?? "null"
		try writeSlice(
			"""
			{"activity_state":"\(activityState)","updated_at":"2026-01-01T00:00:00Z","level":3,"level_fraction":0.5,"half_hearts":\(halfHearts),"last_activity_at":\(lastActivity)}
			""",
			to: target
		)
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
		let driver = makeDriver(
			target: target, recorder: recorder,
			reader: { _ in .failure(.schemaNewer(got: 99, expected: EXPECTED_STATE_SCHEMA_VERSION)) }
		)

		driver.tickForTesting()

		XCTAssertEqual(recorder.renders.map { $0.0 }, [.idle])
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.desaturated])
		XCTAssertEqual(
			recorder.tooltips,
			[LivePollingTooltips.schemaNewer(got: 99, expected: EXPECTED_STATE_SCHEMA_VERSION) as String?],
			"schema-newer tooltip must format both version integers via the canonical template"
		)
		XCTAssertEqual(
			recorder.tooltips.first ?? nil,
			"state.json schema_version is v99; this app supports v\(EXPECTED_STATE_SCHEMA_VERSION). Update the menu bar app."
		)
	}

	func testFutureReviveUntilRendersReviveRow() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let rpgTarget = makeSandboxPath()
		try writeSlice(
			#"{"activity_state":"implementing","updated_at":"2026-06-08T00:00:00.000Z"}"#,
			to: target
		)
		try writeRpgStateJson(rpgTarget, reviveUntil: "2099-01-01T00:00:00.000Z")
		let driver = makeDriver(target: target, recorder: recorder, rpgStatePath: rpgTarget)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 }, [.revive],
			"an active revive window must render the dedicated revive row over the hook state")
		XCTAssertEqual(recorder.renders.map { $0.1 }, [.normal])
	}

	func testExpiredReviveUntilRendersBaseHookState() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let rpgTarget = makeSandboxPath()
		try writeSlice(
			#"{"activity_state":"implementing","updated_at":"2026-06-08T00:00:00.000Z"}"#,
			to: target
		)
		try writeRpgStateJson(rpgTarget, reviveUntil: "2020-01-01T00:00:00.000Z")
		let driver = makeDriver(target: target, recorder: recorder, rpgStatePath: rpgTarget)

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.renders.map { $0.0 }, [.implementing],
			"a lapsed revive window must fall through to the hook state")
	}

	func testSchemaMissingRendersIdleDesaturatedWithSchemaMissingTooltip() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		let driver = makeDriver(
			target: target, recorder: recorder,
			reader: { _ in .failure(.schemaMissingOrInvalid) }
		)

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
		let driver = makeDriver(
			target: target, recorder: recorder,
			reader: { _ in .failure(.malformed) }
		)

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
		try writeSlice(
			#"""
			{"activity_state":"implementing","updated_at":"2026-05-29T00:00:00.000Z","source_event":{"origin":"codex","kind":"tool_use","name":"Bash","repo_root":"/repo/non-soa"}}
			"""#,
			to: target
		)
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
		// Hours-old content `updated_at` with otherwise valid idle payload. Per the
		// product plan, content staleness gets no special handling — the renderer
		// receives `.idle` in `.normal` mode. (mtime TTL is separate from content age.)
		try writeSlice(
			#"{"activity_state":"idle","updated_at":"2020-01-01T00:00:00.000Z","source_event":{"origin":"sync","kind":"sync_response","name":"stale"}}"#,
			to: target
		)
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
		let rpgTarget = makeSandboxPath()
		let lastActivity = "2026-06-04T00:00:00.000Z"
		// Written value is full (6); 16h elapsed since last activity → floor(16/8)
		// = 2 half-hearts of decay, so the HUD must show 4 even though no new hook
		// write occurred (file unchanged between the activity write and now).
		try writeV5StateJson(target, halfHearts: 6, lastActivityAt: lastActivity)
		try writeRpgStateJson(rpgTarget, halfHearts: 6, lastActivityAt: lastActivity)
		let sixteenHoursLater = ISO8601DateFormatter().date(from: "2026-06-04T16:00:00Z")!
		let driver = makeDriver(
			target: target, recorder: recorder, rpgStatePath: rpgTarget,
			now: { sixteenHoursLater })

		driver.tickForTesting()

		XCTAssertEqual(
			recorder.rpgStates.last?.halfHearts, 4,
			"16h idle decays 2 half-hearts below the written 6 with no new hook write")
	}

	func testNullLastActivityAtDoesNotDecay() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		// No rpgStatePath supplied → driver uses .safeDefault (halfHearts=6, lastActivityAt=nil).
		// The assertion holds because safeDefault has no timestamp to trigger decay, not
		// because the slice's null last_activity_at is read (v8 ignores slice RPG fields).
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
		let rpgTarget = makeSandboxPath()
		let lastActivity = "2026-06-04T00:00:00.000Z"
		try writeV5StateJson(target, halfHearts: 6, lastActivityAt: lastActivity)
		try writeRpgStateJson(rpgTarget, halfHearts: 6, lastActivityAt: lastActivity)
		// Advance the injected clock across the 8h decay boundary between ticks
		// with no file write — proves decay rides the poll loop, not a file change
		// (the codogotchi-10 change-gate-starvation pattern does not apply because
		// the displayed value is recomputed against `now` every tick).
		var current = ISO8601DateFormatter().date(from: "2026-06-04T07:59:00Z")!
		let driver = makeDriver(
			target: target, recorder: recorder, rpgStatePath: rpgTarget, now: { current })

		driver.tickForTesting()
		XCTAssertEqual(recorder.rpgStates.last?.halfHearts, 6, "before 8h: full")

		current = ISO8601DateFormatter().date(from: "2026-06-04T08:01:00Z")!
		driver.tickForTesting()

		XCTAssertEqual(
			recorder.rpgStates.last?.halfHearts, 5,
			"crossing 8h must emit a fresh decayed value even though state.json never changed")
	}

	// MARK: - Two-origin perPlatform tick (P13.04)

	func testTwoOriginDirectoryEmitsGlobalAggregateToMenubar() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
		// claude_code: earlier
		try """
			{"schema_version":8,"origin":"claude_code","session_id":"s1","activity_state":"implementing","hp_overlay":"thriving","hp":100,"updated_at":"2026-06-28T10:00:00.000Z","source_event":{"origin":"claude_code","kind":"tool_use","name":"Bash"}}
			""".write(to: target.appendingPathComponent("claude_code:s1.json"), atomically: true, encoding: .utf8)
		// cursor: later — wins global aggregate
		try """
			{"schema_version":8,"origin":"cursor","session_id":"s2","activity_state":"thinking","hp_overlay":"thriving","hp":100,"updated_at":"2026-06-28T10:00:01.000Z","source_event":{"origin":"cursor","kind":"tool_use","name":"Edit"}}
			""".write(to: target.appendingPathComponent("cursor:s2.json"), atomically: true, encoding: .utf8)

		var perPlatformSnapshots: [PerPlatformSnapshot] = []
		let driver = makeDriver(target: target, recorder: recorder)
		driver.applyPerPlatform = { snap in perPlatformSnapshots.append(snap) }

		driver.tickForTesting()

		// Menubar gets global aggregate (most-recent updated_at = cursor → thinking)
		XCTAssertEqual(
			recorder.renders.map { $0.0 }, [.thinking],
			"global aggregate must pick cursor's later updated_at for the menubar render"
		)
		// Pool gets per-origin breakdown with two entries
		XCTAssertEqual(perPlatformSnapshots.count, 1)
		XCTAssertEqual(
			Set(perPlatformSnapshots[0].perPlatform.keys), Set(["claude_code", "cursor"]),
			"applyPerPlatform must receive both origins"
		)
	}

	// MARK: - Per-origin SoA gate/context (Phase 15)

	/// End-to-end contract for the Phase 15 fix: two platforms concurrently
	/// mid-delivery (each with its own `<origin>:<session_id>.gate.json` /
	/// `.context.json` written by son-of-anton Phase 17) must each animate and
	/// badge with *their own* gate/ticket — not the single most-recently-written
	/// file across every platform, and not silently lost by the pool.
	func testConcurrentOriginsEachGetTheirOwnGateAnimationAndBadge() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

		// claude_code: mid red_tdd ticket P15.01, gate written first.
		try """
			{"schema_version":8,"origin":"claude_code","session_id":"s1","activity_state":"implementing","updated_at":"2026-06-28T10:00:00.000Z","source_event":{"origin":"claude_code","kind":"tool_use","name":"Bash"}}
			""".write(to: target.appendingPathComponent("claude_code:s1.json"), atomically: true, encoding: .utf8)
		try """
			{"gate":"red_tdd","since":"2026-06-28T09:59:00.000Z","expires_at":"2099-01-01T00:00:00.000Z","plan_key":"phase-15","ticket_id":"P15.01"}
			""".write(to: target.appendingPathComponent("claude_code:s1.gate.json"), atomically: true, encoding: .utf8)
		try """
			{"owner":"soa","status":"active","plan_key":"phase-15","ticket_id":"P15.01","last_gate":"red_tdd","updated_at":"2026-06-28T09:59:00.000Z","lease_expires_at":"2099-01-01T00:00:00.000Z"}
			""".write(to: target.appendingPathComponent("claude_code:s1.context.json"), atomically: true, encoding: .utf8)

		// cursor: mid open_pr ticket P15.04, gate written later — must NOT clobber
		// claude_code's badge/animation, and must NOT itself be suppressed.
		try """
			{"schema_version":8,"origin":"cursor","session_id":"s2","activity_state":"implementing","updated_at":"2026-06-28T10:00:01.000Z","source_event":{"origin":"cursor","kind":"tool_use","name":"Edit"}}
			""".write(to: target.appendingPathComponent("cursor:s2.json"), atomically: true, encoding: .utf8)
		try """
			{"gate":"open_pr","since":"2026-06-28T10:00:01.000Z","expires_at":"2099-01-01T00:00:00.000Z","plan_key":"phase-15","ticket_id":"P15.04"}
			""".write(to: target.appendingPathComponent("cursor:s2.gate.json"), atomically: true, encoding: .utf8)
		try """
			{"owner":"soa","status":"active","plan_key":"phase-15","ticket_id":"P15.04","last_gate":"open_pr","updated_at":"2026-06-28T10:00:01.000Z","lease_expires_at":"2099-01-01T00:00:00.000Z"}
			""".write(to: target.appendingPathComponent("cursor:s2.context.json"), atomically: true, encoding: .utf8)

		var perPlatformSnapshots: [PerPlatformSnapshot] = []
		let driver = makeDriver(target: target, recorder: recorder)
		driver.applyPerPlatform = { snap in perPlatformSnapshots.append(snap) }

		driver.tickForTesting()

		XCTAssertEqual(perPlatformSnapshots.count, 1)
		let snapshot = try XCTUnwrap(perPlatformSnapshots.first)

		// Each origin's own gate merges into its own animation state — the
		// legacy single global gate.json/decide() path only ever reached the
		// menubar status item, never the per-platform windows.
		XCTAssertEqual(
			snapshot.perPlatform["claude_code"]?.activityState, .redTdd,
			"claude_code must animate its own red_tdd gate")
		XCTAssertEqual(
			snapshot.perPlatform["cursor"]?.activityState, .openPr,
			"cursor must animate its own open_pr gate, unaffected by claude_code's gate")

		// Each origin's persistent ticket/gate badge is independent.
		XCTAssertEqual(snapshot.gateBadges["claude_code"]?.ticketId, "P15.01")
		XCTAssertEqual(snapshot.gateBadges["claude_code"]?.gate, "red_tdd")
		XCTAssertEqual(snapshot.gateBadges["cursor"]?.ticketId, "P15.04")
		XCTAssertEqual(snapshot.gateBadges["cursor"]?.gate, "open_pr")
	}

	/// A single-platform install with only the legacy flat `gate.json` /
	/// `delivery-context.json` (no `active-session.json` origin resolved, e.g. an
	/// older son-of-anton or a hook that never wrote a per-origin slice) must
	/// still badge that one active origin — the fallback path.
	func testSingleOriginFallsBackToLegacyFlatGateFiles() throws {
		let recorder = Recorder()
		let target = makeSandboxPath()
		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
		try """
			{"schema_version":8,"origin":"claude_code","session_id":"s1","activity_state":"implementing","updated_at":"2026-06-28T10:00:00.000Z","source_event":{"origin":"claude_code","kind":"tool_use","name":"Bash"}}
			""".write(to: target.appendingPathComponent("claude_code:s1.json"), atomically: true, encoding: .utf8)

		let gatePath = makeSiblingGatePath(for: target)
		let contextPath = makeSiblingDeliveryContextPath(for: target)
		try """
			{"gate":"poll_review","since":"2026-06-28T09:59:00.000Z","expires_at":"2099-01-01T00:00:00.000Z","plan_key":"phase-15","ticket_id":"P15.09"}
			""".write(to: gatePath, atomically: true, encoding: .utf8)
		try """
			{"owner":"soa","status":"active","plan_key":"phase-15","ticket_id":"P15.09","last_gate":"poll_review","updated_at":"2026-06-28T09:59:00.000Z","lease_expires_at":"2099-01-01T00:00:00.000Z"}
			""".write(to: contextPath, atomically: true, encoding: .utf8)

		var perPlatformSnapshots: [PerPlatformSnapshot] = []
		let driver = makeDriver(
			target: target, recorder: recorder, gatePath: gatePath, deliveryContextPath: contextPath)
		driver.applyPerPlatform = { snap in perPlatformSnapshots.append(snap) }

		driver.tickForTesting()

		let snapshot = try XCTUnwrap(perPlatformSnapshots.first)
		XCTAssertEqual(snapshot.perPlatform["claude_code"]?.activityState, .pollReview)
		XCTAssertEqual(snapshot.gateBadges["claude_code"]?.ticketId, "P15.09")
	}
}

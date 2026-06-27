import XCTest

@testable import Codogotchi

/// Behavior contract for P2.06 demo mode: the `DemoCycleDriver` that copies
/// fixture `state.json` payloads through a sandboxed polling target on a fixed
/// cycle, and the `DemoConfig` that decides whether demo mode is active and
/// which path the menubar app polls.
///
/// Tests drive the cycle via a deterministic `tickForTesting()` seam instead of
/// the production 3-second timer so they do not stall `xcodebuild ... test`.
@MainActor
final class DemoModeTests: XCTestCase {
	// MARK: - Fixture paths

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
			.appendingPathComponent("codogotchi-demo-tests")
			.appendingPathComponent(UUID().uuidString)
		return dir.appendingPathComponent("state.d")
	}

	// MARK: - DemoCycleDriver cycle order

	func testCycleDriverEmitsFirstFiveStatesInCycleOrder() throws {
		var observed: [ActivityState] = []
		let driver = DemoCycleDriver(
			sandboxedPath: makeSandboxPath(),
			fixturesDirectory: fixturesDirectory(),
			apply: { state in observed.append(state) }
		)

		for _ in 0..<5 {
			try driver.tickForTesting()
		}

		XCTAssertEqual(
			observed,
			[.idle, .implementing, .editing, .searching, .webSearch],
			"demo cycle first five states: idle → implementing → editing → searching → webSearch"
		)
	}

	func testCycleDriverLoopsBackToIdleAfterAllStates() throws {
		var observed: [ActivityState] = []
		let driver = DemoCycleDriver(
			sandboxedPath: makeSandboxPath(),
			fixturesDirectory: fixturesDirectory(),
			apply: { state in observed.append(state) }
		)

		for _ in 0..<27 {
			try driver.tickForTesting()
		}

		XCTAssertEqual(
			observed.first, .idle, "cycle must start at .idle"
		)
		XCTAssertEqual(
			observed[25], .idle, "cycle must loop back to .idle after all 25 states"
		)
		XCTAssertEqual(
			observed[26], .implementing, "second wrap must resume at .implementing"
		)
	}

	// MARK: - Atomic file write to sandboxed path

	func testCycleDriverWritesFixtureBytesAtomicallyToSandboxedPath() throws {
		let sandbox = makeSandboxPath()
		let driver = DemoCycleDriver(
			sandboxedPath: sandbox,
			fixturesDirectory: fixturesDirectory(),
			apply: { _ in }
		)

		try driver.tickForTesting()

		let sliceFile = sandbox.appendingPathComponent("demo:default.json")
		let written = try Data(contentsOf: sliceFile)
		let expected = try Data(contentsOf: fixturesDirectory().appendingPathComponent("idle.json"))
		XCTAssertEqual(
			written,
			expected,
			"first tick must copy idle.json bytes verbatim to state.d/demo:default.json"
		)
	}

	func testCycleDriverCreatesParentDirectoryOnFirstUse() throws {
		let sandbox = makeSandboxPath()
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: sandbox.deletingLastPathComponent().path),
			"sanity check: sandbox parent must not exist before the first tick"
		)

		let driver = DemoCycleDriver(
			sandboxedPath: sandbox,
			fixturesDirectory: fixturesDirectory(),
			apply: { _ in }
		)
		try driver.tickForTesting()

		var isDir: ObjCBool = false
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: sandbox.deletingLastPathComponent().path, isDirectory: &isDir),
			"driver must mkdir -p the sandbox parent on first use"
		)
		XCTAssertTrue(isDir.boolValue, "sandbox parent must be a directory, not a file")
	}

	// MARK: - DemoConfig environment + argument wiring

	func testDemoConfigDefaultsToLiveStatePath() {
		let config = DemoConfig.from(environment: [:], arguments: ["Codogotchi"])

		XCTAssertFalse(
			config.isDemoMode,
			"absent CODOGOTCHI_DEMO and absent --demo must leave demo mode off"
		)
		XCTAssertTrue(
			config.pollingTarget.path.hasSuffix("/.codogotchi/state.d"),
			"live mode polling target must point at ~/.codogotchi/state.d — got \(config.pollingTarget.path)"
		)
	}

	func testDemoConfigEnvironmentVariableEnablesDemoMode() {
		let config = DemoConfig.from(
			environment: ["CODOGOTCHI_DEMO": "1"],
			arguments: ["Codogotchi"]
		)

		XCTAssertTrue(config.isDemoMode, "CODOGOTCHI_DEMO=1 must activate demo mode")
		XCTAssertTrue(
			config.pollingTarget.path.contains("codogotchi-demo"),
			"demo mode polling target must be under a sandboxed codogotchi-demo directory — got \(config.pollingTarget.path)"
		)
		XCTAssertFalse(
			config.pollingTarget.path.hasSuffix("/.codogotchi/state.json"),
			"demo mode must never point at the real ~/.codogotchi/state.json"
		)
	}

	func testDemoConfigDemoLaunchArgumentEnablesDemoMode() {
		let config = DemoConfig.from(
			environment: [:],
			arguments: ["Codogotchi", "--demo"]
		)

		XCTAssertTrue(
			config.isDemoMode,
			"--demo launch argument must activate demo mode equivalently to CODOGOTCHI_DEMO=1"
		)
		XCTAssertFalse(
			config.pollingTarget.path.hasSuffix("/.codogotchi/state.json"),
			"--demo path must not collide with the live state path"
		)
	}

	func testDemoConfigEnvironmentZeroDoesNotEnableDemoMode() {
		let config = DemoConfig.from(
			environment: ["CODOGOTCHI_DEMO": "0"],
			arguments: ["Codogotchi"]
		)

		XCTAssertFalse(
			config.isDemoMode,
			"CODOGOTCHI_DEMO=0 must be treated as off; only \"1\" activates demo mode"
		)
	}

	// MARK: - P7.01: demo cycle covers all activity states

	func testCycleDriverExposes25StatesInRotation() {
		XCTAssertEqual(
			DemoCycleDriver.cycle.count, 25,
			"demo cycle must cover all 25 activity states"
		)
	}

	func testCycleDriverCycleContainsAllActivityStates() {
		let cycleStates = Set(DemoCycleDriver.cycle.map { $0.state })
		for state in ActivityState.allCases {
			XCTAssertTrue(cycleStates.contains(state), "cycle must include .\(state.rawValue)")
		}
	}

	// MARK: - Demo cycle tick interval

	func testDefaultDemoTickSecondsIs3() {
		XCTAssertEqual(DemoConfig.demoTickSeconds(from: [:]), 3.0)
	}

	func testDemoTickSecondsEnvVarIsHonored() {
		XCTAssertEqual(
			DemoConfig.demoTickSeconds(from: ["CODOGOTCHI_DEMO_TICK_SECONDS": "20"]), 20.0)
	}

	func testDemoTickSecondsInvalidValueFallsBackTo3() {
		XCTAssertEqual(
			DemoConfig.demoTickSeconds(from: ["CODOGOTCHI_DEMO_TICK_SECONDS": "invalid"]), 3.0)
	}

	func testDemoTickSecondsZeroValueFallsBackTo3() {
		XCTAssertEqual(
			DemoConfig.demoTickSeconds(from: ["CODOGOTCHI_DEMO_TICK_SECONDS": "0"]), 3.0)
	}

	// MARK: - P3.06: CODOGOTCHI_DEMO_FRAME_MS

	func testDefaultDemoFrameMsIs500() {
		XCTAssertEqual(DemoConfig.demoFrameMs(from: [:]), 500)
	}

	func testDemoFrameMsEnvVarIsHonored() {
		XCTAssertEqual(
			DemoConfig.demoFrameMs(from: ["CODOGOTCHI_DEMO_FRAME_MS": "83"]), 83)
	}

	func testDemoFrameMsInvalidValueFallsBackTo500() {
		XCTAssertEqual(
			DemoConfig.demoFrameMs(from: ["CODOGOTCHI_DEMO_FRAME_MS": "invalid"]), 500)
	}

	func testDemoFrameMsNegativeValueFallsBackTo500() {
		XCTAssertEqual(
			DemoConfig.demoFrameMs(from: ["CODOGOTCHI_DEMO_FRAME_MS": "-10"]), 500)
	}

	func testDemoFrameMsZeroValueFallsBackTo500() {
		XCTAssertEqual(
			DemoConfig.demoFrameMs(from: ["CODOGOTCHI_DEMO_FRAME_MS": "0"]), 500)
	}

	// MARK: - P7.01: v4 fixture files

	func testV4FixtureFilesExistAndParse() {
		let v4Filenames = [
			"testing.json", "thinking.json", "reading.json", "cramming.json",
			"waiting_for_input.json", "ticket_started.json", "ticket_completed.json",
			"review_clean.json", "adversarial_review.json", "open_pr.json",
			"poll_review.json", "record_review.json", "advance.json",
			"red_tdd.json", "green_tdd.json", "standby.json", "errored.json",
		]
		let dir = fixturesDirectory()
		for filename in v4Filenames {
			let url = dir.appendingPathComponent(filename)
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: url.path),
				"\(filename) must exist in Fixtures/state-json/"
			)
			let result = StateJsonReader.read(at: url.path)
			switch result {
			case .failure(let err):
				XCTFail("\(filename) failed to parse: \(err)")
			case .success:
				break
			}
		}
	}

	// MARK: - HUD demo snapshot mapping

	func testHUDDemoStartsFullHeartsEmptyRingLevelOne() {
		let s = HUDDemoDriver.snapshot(at: 0)
		XCTAssertEqual(s.halfHearts, 6)
		XCTAssertEqual(s.level, 1)
		XCTAssertEqual(s.levelFraction, 0, accuracy: 1e-9)
	}

	func testHUDDemoLevelIncrementsEveryEightSeconds() {
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 7.99).level, 1)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 8).level, 2)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 16).level, 3)
	}

	func testHUDDemoRingFillsWithinEachLevel() {
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 4).levelFraction, 0.5, accuracy: 1e-9)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 8).levelFraction, 0, accuracy: 1e-9)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 12).levelFraction, 0.5, accuracy: 1e-9)
	}

	func testHUDDemoHeartsTriangleWaveEveryFiveSeconds() {
		// Full → empty over 30s (one half-heart every 5s).
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 0).halfHearts, 6)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 5).halfHearts, 5)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 30).halfHearts, 0)
		// Then empty → full over the next 30s.
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 35).halfHearts, 1)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 60).halfHearts, 6)
	}

	func testHUDDemoCompletesTwoHeartCyclesAndEndsLevelSixteen() {
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 90).halfHearts, 0)
		let end = HUDDemoDriver.snapshot(at: 120)
		XCTAssertEqual(end.halfHearts, 6, "two complete heart cycles end on full hearts")
		XCTAssertEqual(end.level, 16, "15 level-ups over 120s start at 1 → end at 16")
	}

	func testHUDDemoClampsBeyondDuration() {
		let end = HUDDemoDriver.snapshot(at: 999)
		XCTAssertEqual(end.level, 16)
		XCTAssertEqual(end.halfHearts, 6)
	}

	// MARK: - Configurable HUD demo speed

	func testHUDDemoHalfHeartStepScalesWithLevelSpeedKeepingRatio() {
		// Default 5:8 heart:level ratio is preserved at any level speed.
		XCTAssertEqual(HUDDemoDriver.halfHeartStep(forSecondsPerLevel: 8), 5, accuracy: 1e-9)
		XCTAssertEqual(
			HUDDemoDriver.halfHeartStep(forSecondsPerLevel: 3), 3 * 5.0 / 8.0, accuracy: 1e-9)
	}

	func testHUDDemoSnapshotHonorsCustomLevelSpeed() {
		// 3s/level: still level 1 just before 3s, level 2 at 3s, ring half at 1.5s.
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 2.99, secondsPerLevel: 3).level, 1)
		XCTAssertEqual(HUDDemoDriver.snapshot(at: 3, secondsPerLevel: 3).level, 2)
		XCTAssertEqual(
			HUDDemoDriver.snapshot(at: 1.5, secondsPerLevel: 3).levelFraction, 0.5, accuracy: 1e-9)
	}

	func testHUDDemoSnapshotScalesHeartsWithLevelSpeed() {
		let step = HUDDemoDriver.halfHeartStep(forSecondsPerLevel: 3)
		// One half-heart lost after a single (scaled) step.
		XCTAssertEqual(
			HUDDemoDriver.snapshot(
				at: step, secondsPerLevel: 3, secondsPerHalfHeartStep: step
			).halfHearts, 5)
	}

	func testHUDDemoLevelSecondsParsesEnvOverride() {
		XCTAssertEqual(
			DemoConfig.hudDemoLevelSeconds(from: ["CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS": "3"]),
			3, accuracy: 1e-9)
	}

	func testHUDDemoLevelSecondsFallsBackWhenAbsentOrInvalid() {
		let fallback = HUDDemoDriver.defaultSecondsPerLevel
		XCTAssertEqual(DemoConfig.hudDemoLevelSeconds(from: [:]), fallback, accuracy: 1e-9)
		XCTAssertEqual(
			DemoConfig.hudDemoLevelSeconds(from: ["CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS": "0"]),
			fallback, accuracy: 1e-9)
		XCTAssertEqual(
			DemoConfig.hudDemoLevelSeconds(from: ["CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS": "abc"]),
			fallback, accuracy: 1e-9)
	}
}

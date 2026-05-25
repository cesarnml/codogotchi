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
		return dir.appendingPathComponent("state.json")
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
			[.idle, .implementing, .runningTests, .reviewing, .pushing],
			"demo cycle first five states: idle → implementing → running-tests → reviewing → pushing"
		)
	}

	func testCycleDriverLoopsBackToIdleAfterAllStates() throws {
		var observed: [ActivityState] = []
		let driver = DemoCycleDriver(
			sandboxedPath: makeSandboxPath(),
			fixturesDirectory: fixturesDirectory(),
			apply: { state in observed.append(state) }
		)

		for _ in 0..<17 {
			try driver.tickForTesting()
		}

		XCTAssertEqual(
			observed.first, .idle, "cycle must start at .idle"
		)
		XCTAssertEqual(
			observed[15], .idle, "cycle must loop back to .idle after all 15 states"
		)
		XCTAssertEqual(
			observed[16], .implementing, "second wrap must resume at .implementing"
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

		let written = try Data(contentsOf: sandbox)
		let expected = try Data(contentsOf: fixturesDirectory().appendingPathComponent("idle.json"))
		XCTAssertEqual(
			written,
			expected,
			"first tick must copy idle.json bytes verbatim to the sandboxed path"
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
			config.pollingTarget.path.hasSuffix("/.codogotchi/state.json"),
			"live mode polling target must point at ~/.codogotchi/state.json — got \(config.pollingTarget.path)"
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

	// MARK: - P3.06: 15-state cycle

	func testCycleDriverExposes15StatesInRotation() {
		XCTAssertEqual(
			DemoCycleDriver.cycle.count, 15,
			"demo cycle must cover all 15 activity states"
		)
	}

	func testCycleDriverCycleContainsAllActivityStates() {
		let cycleStates = Set(DemoCycleDriver.cycle.map { $0.state })
		for state in ActivityState.allCases {
			XCTAssertTrue(cycleStates.contains(state), "cycle must include .\(state.rawValue)")
		}
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

	// MARK: - P3.06: New fixture files

	func testNewFixtureFilesExistAndParseAsV2() {
		let newFilenames = [
			"reviewing.json", "pushing.json", "hyped.json", "focused.json",
			"nervous.json", "waiting.json", "ascended.json", "calling-for-backup.json",
			"panicking.json", "requesting-input.json", "errored.json",
		]
		let dir = fixturesDirectory()
		for filename in newFilenames {
			let url = dir.appendingPathComponent(filename)
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: url.path),
				"\(filename) must exist in Fixtures/state-json/"
			)
			let result = StateJsonReader.read(at: url.path)
			switch result {
			case .failure(let err):
				XCTFail("\(filename) failed to parse as v2 state.json: \(err)")
			case .success(let snapshot):
				XCTAssertEqual(
					snapshot.schemaVersion, 2,
					"\(filename) must have schema_version 2, got \(snapshot.schemaVersion)"
				)
			}
		}
	}
}

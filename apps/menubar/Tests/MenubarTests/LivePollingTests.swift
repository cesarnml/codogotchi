import XCTest

@testable import Menubar

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

	private func copyFixture(_ name: String, to target: URL) throws {
		let src = fixturesDirectory().appendingPathComponent(name)
		let data = try Data(contentsOf: src)
		try data.write(to: target, options: .atomic)
	}

	// MARK: - Recording sinks

	private final class Recorder {
		var renders: [(ActivityState, VisualMode)] = []
		var tooltips: [String?] = []
	}

	private func makeDriver(target: URL, recorder: Recorder) -> LivePollingDriver {
		return LivePollingDriver(
			pollingTargetPath: target.path,
			apply: { state, mode in recorder.renders.append((state, mode)) },
			setTooltip: { tip in recorder.tooltips.append(tip) }
		)
	}

	// MARK: - Three failure visuals

	func testFileNotFoundRendersIdleDesaturatedWithNoHookTooltip() {
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
		XCTAssertEqual(
			recorder.renders.map { $0.1 },
			[.desaturated],
			"missing file must render .desaturated"
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
			[LivePollingTooltips.schemaNewer(got: 99, expected: 2)],
			"schema-newer tooltip must format both version integers via the canonical template"
		)
		// Spot-check the literal substring so an accidental template-string drift
		// (e.g., dropping the trailing 'Update the menu bar app.') is caught
		// without needing to re-implement the template assembly here.
		XCTAssertEqual(
			recorder.tooltips.first ?? nil,
			"state.json schema_version is v99; this app supports v2. Update the menu bar app."
		)
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
}

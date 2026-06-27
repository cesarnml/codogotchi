import Foundation

/// Launch-time configuration for the menubar app's polling target.
///
/// `pollingTarget` is the path the polling driver reads. In live mode it is the
/// real hook output (`~/.codogotchi/state.json`); in demo mode it is a
/// sandboxed file under `$TMPDIR/codogotchi-demo/state.json` that the
/// `DemoCycleDriver` cycles fixture payloads through.
///
/// The split exists so demo mode exercises the *same* polling read path that
/// live mode (P2.07) will use — only the bytes' origin differs. The real
/// `~/.codogotchi/state.json` is never touched in demo mode.
struct DemoConfig: Equatable {
	let isDemoMode: Bool
	let pollingTarget: URL

	/// Pure helper used by tests and by `forLaunch()`. Demo mode is on when
	/// either `CODOGOTCHI_DEMO=1` is in the environment or `--demo` appears in
	/// the launch arguments. Any other value of `CODOGOTCHI_DEMO` (including
	/// `"0"`, `""`, and absent) leaves demo mode off.
	static func from(environment: [String: String], arguments: [String]) -> DemoConfig {
		let envOn = environment["CODOGOTCHI_DEMO"] == "1"
		let argOn = arguments.contains("--demo")
		if envOn || argOn {
			let tmpRoot: URL =
				environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
				?? URL(fileURLWithPath: NSTemporaryDirectory())
			return DemoConfig(
				isDemoMode: true,
				pollingTarget: tmpRoot
					.appendingPathComponent("codogotchi-demo")
					.appendingPathComponent("state.d")
			)
		}
		let home: URL =
			environment["HOME"].map { URL(fileURLWithPath: $0) }
			?? FileManager.default.homeDirectoryForCurrentUser
		return DemoConfig(
			isDemoMode: false,
			pollingTarget: home
				.appendingPathComponent(".codogotchi")
				.appendingPathComponent("state.d")
		)
	}

	/// Default demo cycle interval (seconds between activity-state fixtures).
	static let defaultDemoTickSeconds: TimeInterval = 3.0

	/// Default frame interval for demo mode (ms). Named constant so it is not
	/// scattered as a magic number across the renderer and the test suite.
	static let defaultDemoFrameMs: Int = 500

	/// Resolve the demo cycle interval in seconds from the environment.
	///
	/// `CODOGOTCHI_DEMO_TICK_SECONDS`, when present and parseable as a positive
	/// number, overrides `defaultDemoTickSeconds`. Out-of-range or unparseable
	/// values silently fall back to `defaultDemoTickSeconds`.
	static func demoTickSeconds(from environment: [String: String]) -> TimeInterval {
		guard let raw = environment["CODOGOTCHI_DEMO_TICK_SECONDS"],
			let value = Double(raw), value > 0
		else { return defaultDemoTickSeconds }
		return value
	}

	/// Resolve the demo frame interval in milliseconds from the environment.
	///
	/// `CODOGOTCHI_DEMO_FRAME_MS`, when present and parseable as a positive
	/// integer, overrides the 500 ms default. Out-of-range or unparseable
	/// values silently fall back to `defaultDemoFrameMs`.
	static func demoFrameMs(from environment: [String: String]) -> Int {
		guard let raw = environment["CODOGOTCHI_DEMO_FRAME_MS"],
			let value = Int(raw), value > 0
		else { return defaultDemoFrameMs }
		return value
	}

	/// Resolve the HUD-demo seconds-per-level from the environment.
	///
	/// `CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS`, when present and parseable as a
	/// positive number, sets how fast the HUD demo levels up; the half-heart
	/// cycle scales proportionally (see `HUDDemoDriver.halfHeartStep`).
	/// Out-of-range or unparseable values fall back to the default 8s/level.
	static func hudDemoLevelSeconds(from environment: [String: String]) -> TimeInterval {
		guard let raw = environment["CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS"],
			let value = Double(raw), value > 0
		else { return HUDDemoDriver.defaultSecondsPerLevel }
		return value
	}

	/// Whether the HUD demo should pin hearts at full and show only the level/XP
	/// sweep (the `tcl` leveling demo). Enabled by `CODOGOTCHI_HUD_DEMO_HEARTS_FULL=1`.
	static func hudDemoHeartsFull(from environment: [String: String]) -> Bool {
		environment["CODOGOTCHI_HUD_DEMO_HEARTS_FULL"] == "1"
	}

	/// Production seam: reads `ProcessInfo` at launch time.
	static func forLaunch() -> DemoConfig {
		let env = ProcessInfo.processInfo.environment
		let args = ProcessInfo.processInfo.arguments
		let result = from(environment: env, arguments: args)
		return result
	}
}

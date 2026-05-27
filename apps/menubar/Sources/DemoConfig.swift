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
					.appendingPathComponent("state.json")
			)
		}
		let home: URL =
			environment["HOME"].map { URL(fileURLWithPath: $0) }
			?? FileManager.default.homeDirectoryForCurrentUser
		return DemoConfig(
			isDemoMode: false,
			pollingTarget: home
				.appendingPathComponent(".codogotchi")
				.appendingPathComponent("state.json")
		)
	}

	/// Default frame interval for demo mode (ms). Named constant so it is not
	/// scattered as a magic number across the renderer and the test suite.
	static let defaultDemoFrameMs: Int = 500

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

	/// Production seam: reads `ProcessInfo` at launch time.
	static func forLaunch() -> DemoConfig {
		let env = ProcessInfo.processInfo.environment
		let args = ProcessInfo.processInfo.arguments
		let result = from(environment: env, arguments: args)
		return result
	}
}

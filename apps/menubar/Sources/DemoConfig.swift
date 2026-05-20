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

	/// Production seam: reads `ProcessInfo` at launch time.
	static func forLaunch() -> DemoConfig {
		return from(
			environment: ProcessInfo.processInfo.environment,
			arguments: ProcessInfo.processInfo.arguments
		)
	}
}

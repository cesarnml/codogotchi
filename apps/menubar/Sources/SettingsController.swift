import Foundation

/// Testable state machine for Settings window hook actions.
/// Window concerns live in `SettingsWindowController`.
struct SettingsController {
	typealias SubprocessRunner = (_ argv: [String]) -> HookStatusClient.RunResult

	let runner: SubprocessRunner

	init(runner: @escaping SubprocessRunner = HookStatusClient.defaultRunner) {
		self.runner = runner
	}

	/// Runs `codogotchi hooks install` synchronously.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksInstall() -> String? {
		let result = runner(["codogotchi", "hooks", "install"])
		guard result.exitCode == 0 else {
			return result.stderr.isEmpty
				? "Install failed (exit \(result.exitCode))"
				: result.stderr
		}
		return nil
	}

	/// Runs `codogotchi hooks uninstall` synchronously.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksUninstall() -> String? {
		let result = runner(["codogotchi", "hooks", "uninstall"])
		guard result.exitCode == 0 else {
			return result.stderr.isEmpty
				? "Uninstall failed (exit \(result.exitCode))"
				: result.stderr
		}
		return nil
	}
}

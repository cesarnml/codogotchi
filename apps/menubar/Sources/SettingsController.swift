import Foundation

/// Testable state machine for Settings window hook actions.
/// Window concerns live in `SettingsWindowController`.
struct SettingsController {
	typealias SubprocessRunner = (_ argv: [String]) -> HookStatusClient.RunResult

	let runner: SubprocessRunner

	init(runner: @escaping SubprocessRunner = HookStatusClient.defaultRunner) {
		self.runner = runner
	}

	private static let installArgv: [[String]] = [
		["codogotchi", "hooks", "install"],
		["codogotchi", "hooks", "install", "--platform", "cursor"],
	]

	private static let uninstallArgv: [[String]] = [
		["codogotchi", "hooks", "uninstall", "--platform", "cursor"],
		["codogotchi", "hooks", "uninstall"],
	]

	private func runHookArgvSequence(
		_ sequences: [[String]],
		failureLabel: String
	) -> String? {
		for argv in sequences {
			let result = runner(argv)
			guard result.exitCode == 0 else {
				return result.stderr.isEmpty
					? "\(failureLabel) (exit \(result.exitCode))"
					: result.stderr
			}
		}
		return nil
	}

	/// Runs `codogotchi hooks install` for Claude Code, Codex, and native Cursor.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksInstall() -> String? {
		runHookArgvSequence(Self.installArgv, failureLabel: "Install failed")
	}

	/// Idempotent re-install: re-runs install for all platforms so hook JSON points
	/// at the current bundle's absolute hook path.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksUpdate() -> String? {
		runHookArgvSequence(Self.installArgv, failureLabel: "Update failed")
	}

	/// Runs `codogotchi hooks uninstall` for Cursor, Claude Code, and Codex.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksUninstall() -> String? {
		runHookArgvSequence(Self.uninstallArgv, failureLabel: "Uninstall failed")
	}
}

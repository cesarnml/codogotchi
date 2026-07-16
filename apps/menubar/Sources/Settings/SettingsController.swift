import Foundation

/// Testable state machine for Settings window hook actions.
/// Window concerns live in `SettingsWindowController`.
struct SettingsController {
	typealias SubprocessRunner = (_ argv: [String]) -> HookStatusClient.RunResult

	let runner: SubprocessRunner

	init(runner: @escaping SubprocessRunner = HookStatusClient.defaultRunner) {
		self.runner = runner
	}

	// One command installs hooks for every coding tool detected on this machine,
	// treating all five platforms equally. Re-running picks up tools installed
	// since last time.
	private static let installArgv: [[String]] = [
		["codogotchi", "hooks", "install", "--detected"],
	]

	private static let uninstallArgv: [[String]] = [
		["codogotchi", "hooks", "uninstall", "--platform", "cursor"],
		["codogotchi", "hooks", "uninstall", "--platform", "vscode"],
		["codogotchi", "hooks", "uninstall", "--platform", "antigravity"],
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

	/// Installs hooks for every coding tool detected on this machine
	/// (Claude Code, Codex, Cursor, VS Code/Copilot, Antigravity).
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksInstall() -> String? {
		runHookArgvSequence(Self.installArgv, failureLabel: "Install failed")
	}

	/// Idempotent re-install: re-runs detected install so hook JSON points at the
	/// current bundle's absolute hook path and any newly-installed tool gets wired.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksUpdate() -> String? {
		runHookArgvSequence(Self.installArgv, failureLabel: "Update failed")
	}

	/// Runs `codogotchi hooks uninstall` across all platforms.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksUninstall() -> String? {
		runHookArgvSequence(Self.uninstallArgv, failureLabel: "Uninstall failed")
	}
}

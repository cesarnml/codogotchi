import Foundation

/// Testable state machine for the first-run onboarding flow.
/// Window concerns live in `OnboardingWindowController`.
struct OnboardingController {
	typealias InstallRunner = (_ argv: [String]) -> HookStatusClient.RunResult

	let installRunner: InstallRunner

	init(installRunner: @escaping InstallRunner = HookStatusClient.defaultRunner) {
		self.installRunner = installRunner
	}

	/// Returns true when `onboardingCompletedAt` is absent and no hooks are installed yet.
	/// Skips the sheet when hooks are already present to prevent a double-install prompt.
	func needsOnboarding(appState: FloatingAppState) -> Bool {
		guard appState.onboardingCompletedAt == nil else { return false }
		return !(appState.hooksStatus?.anyInstalled() ?? false)
	}

	/// Installs hooks for every coding tool detected on this machine
	/// (Claude Code, Codex, Cursor, VS Code/Copilot, Antigravity).
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksInstall() -> String? {
		for argv in [
			["codogotchi", "hooks", "install", "--detected"],
		] {
			let result = installRunner(argv)
			guard result.exitCode == 0 else {
				return result.stderr.isEmpty
					? "Install failed (exit \(result.exitCode))"
					: result.stderr
			}
		}
		return nil
	}

	/// Returns true when at least one installable hook platform has hooks
	/// installed. Recent firing is not required — see `isHooksNotActive`.
	func isHooksActive(_ snapshot: HooksStatusSnapshot) -> Bool {
		return !snapshot.isHooksNotActive()
	}
}

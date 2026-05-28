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

	/// Runs `codogotchi hooks install` synchronously via the injected runner.
	/// Returns nil on success; returns an error description on non-zero exit.
	func runHooksInstall() -> String? {
		let result = installRunner(["codogotchi", "hooks", "install"])
		guard result.exitCode == 0 else {
			return result.stderr.isEmpty
				? "Install failed (exit \(result.exitCode))"
				: result.stderr
		}
		return nil
	}

	/// Returns true when at least one hook platform is both installed and firing recently.
	func isHooksActive(_ snapshot: HooksStatusSnapshot) -> Bool {
		return !snapshot.isHooksNotActive()
	}
}

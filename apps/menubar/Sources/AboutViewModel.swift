import Foundation

/// View-model for the About tab.
///
/// Sources two version strings, both injectable for testing:
/// - the app version from the bundle's `CFBundleShortVersionString`
/// - the **bundled hook-binary** version from `codogotchi --version`
///
/// The hook version must come from the bundled binary (never a hardcoded Swift
/// constant) so the About tab reflects the binary actually embedded in the
/// `.app`; see P8.03 Review Focus.
struct AboutViewModel {
	let appVersionSource: () -> String
	let hookVersionSource: () -> String

	init(
		appVersionSource: @escaping () -> String = AboutViewModel.bundleShortVersion,
		hookVersionSource: @escaping () -> String = { AboutViewModel.bundledHookVersion() }
	) {
		self.appVersionSource = appVersionSource
		self.hookVersionSource = hookVersionSource
	}

	var appVersion: String { appVersionSource() }
	var hookVersion: String { hookVersionSource() }

	/// Reads `CFBundleShortVersionString` from the main bundle.
	static func bundleShortVersion() -> String {
		(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
	}

	/// Runs the bundled `codogotchi --version` and returns the trimmed stdout.
	/// Returns `"unknown"` on non-zero exit or empty output. The `runner` is
	/// injectable; the default launches the bundled binary (no PATH dependency).
	static func bundledHookVersion(
		runner: HookStatusClient.Runner = HookStatusClient.defaultRunner
	) -> String {
		let result = runner(["codogotchi", "--version"])
		guard result.exitCode == 0 else { return "unknown" }
		let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "unknown" : trimmed
	}
}

import Foundation

/// Pure version-comparison predicate for the lockstep hook-update banner.
///
/// "unknown" is treated as an indeterminate version — the bundled binary could
/// not be queried, so no banner is shown to avoid false positives.
enum LockstepPolicy {
	/// Returns true when the user should be prompted to update hooks.
	///
	/// - hooksInstalled: any platform currently has hooks installed
	/// - bundledVersion: version reported by the bundled `codogotchi` binary
	/// - installedVersion: version last recorded in `app-state.json` after install/update
	static func needsUpdate(
		hooksInstalled: Bool,
		bundledVersion: String,
		installedVersion: String?
	) -> Bool {
		guard hooksInstalled else { return false }
		guard bundledVersion != "unknown" else { return false }
		return bundledVersion != installedVersion
	}
}

import Foundation

/// Mirrors the JSON shape returned by `codogotchi hooks status --json`.
/// Stored alongside `app-state.json` as the most recent cached snapshot so UI
/// can render a CTA without re-running the subprocess on every state read.
struct HooksStatusSnapshot: Codable, Equatable {
	var codex: Platform
	var claudeCode: Platform
	var cursor: Platform
	var vscode: Platform
	var antigravity: Platform

	struct Platform: Codable, Equatable {
		var presentOnDisk: Bool
		var installableInPhase: Bool
		var installed: Bool
		var firingRecently: Bool
		var lastEventAt: String?
		var sourceOrigin: String?
	}

	/// Returns true when at least one installable platform has hooks installed on disk,
	/// regardless of whether any hook has fired recently. Used to suppress the onboarding
	/// sheet when the user configured hooks outside the in-app install flow.
	func anyInstalled() -> Bool {
		[codex, claudeCode, cursor, vscode, antigravity]
			.filter { $0.installableInPhase }
			.contains { $0.installed }
	}

	/// Hooks are "not active" when no installable platform has hooks installed
	/// on disk. Recent firing is intentionally NOT part of this predicate.
	///
	/// `firingRecently` is a decaying, single-origin signal — only the platform
	/// that produced the most recent state event is ever marked firing, and it
	/// flips back to false once the 5-minute window elapses. Gating "active" on
	/// it conflated "did the user happen to drive this tool in the last few
	/// minutes" with "are the hooks wired correctly", so a correctly-installed
	/// hook that simply hadn't fired yet surfaced a misleading "Hooks not active
	/// — Retry install" CTA and pushed users to reinstall hooks that were fine.
	///
	/// Installation is the right health signal: it is stable, doesn't decay, and
	/// is what a "Retry install" CTA can actually fix. Only platforms installable
	/// in the current phase are considered, so phase-deferred platforms can never
	/// suppress the CTA via a stale or hand-edited snapshot. This now matches
	/// `anyInstalled()` exactly.
	func isHooksNotActive() -> Bool {
		return !anyInstalled()
	}
}

extension HooksStatusSnapshot {
	static func fixtureNotInstalled() -> HooksStatusSnapshot {
		let off = Platform(
			presentOnDisk: false,
			installableInPhase: false,
			installed: false,
			firingRecently: false,
			lastEventAt: nil,
			sourceOrigin: nil
		)
		return HooksStatusSnapshot(
			codex: off,
			claudeCode: off,
			cursor: off,
			vscode: off,
			antigravity: off
		)
	}
}

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

	/// Hooks are "not active" when there is no installed-and-firing platform.
	/// Onboarding shows the CTA until at least one platform is both installed
	/// and has reported a recent hook-driven event (per CLI status contract).
	/// Only platforms that are installable in the current phase are considered,
	/// so phase-deferred platforms (cursor, vscode, antigravity) can never
	/// suppress the CTA via a stale or hand-edited snapshot.
	func isHooksNotActive() -> Bool {
		let active = [codex, claudeCode, cursor, vscode, antigravity]
			.filter { $0.installableInPhase }
			.contains { $0.installed && $0.firingRecently }
		return !active
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

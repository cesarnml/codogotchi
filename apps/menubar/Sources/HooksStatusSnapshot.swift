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
		/// codogotchi hooks are present but not fully wired for the current
		/// expected event set (e.g. an install predating a newly-added event).
		/// The integration is real and firing, so it counts as present.
		var partiallyInstalled: Bool = false
		var firingRecently: Bool
		var lastEventAt: String?
		var sourceOrigin: String?

		/// True when codogotchi hooks are present at all — fully wired OR partial.
		/// This is the honest "is the integration here" signal; `installed` alone
		/// is the stricter "fully wired / up to date" signal.
		var present: Bool { installed || partiallyInstalled }
	}

	/// Returns true when at least one installable platform has codogotchi hooks
	/// present on disk (fully wired or partial), regardless of whether any hook
	/// has fired recently. Used to suppress the onboarding sheet when the user
	/// configured hooks outside the in-app install flow, and as the basis for the
	/// "Hooks not active" predicate.
	func anyInstalled() -> Bool {
		[codex, claudeCode, cursor, vscode, antigravity]
			.filter { $0.installableInPhase }
			.contains { $0.present }
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

extension HooksStatusSnapshot.Platform {
	private enum CodingKeys: String, CodingKey {
		case presentOnDisk, installableInPhase, installed, partiallyInstalled
		case firingRecently, lastEventAt, sourceOrigin
	}

	/// Custom decode so a snapshot written by an older build — or a cached
	/// `app-state.json` from before `partiallyInstalled` existed — still decodes
	/// instead of failing the whole load. The synthesized decoder would require
	/// the key; here it defaults to false when absent.
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		presentOnDisk = try c.decode(Bool.self, forKey: .presentOnDisk)
		installableInPhase = try c.decode(Bool.self, forKey: .installableInPhase)
		installed = try c.decode(Bool.self, forKey: .installed)
		partiallyInstalled =
			try c.decodeIfPresent(Bool.self, forKey: .partiallyInstalled) ?? false
		firingRecently = try c.decode(Bool.self, forKey: .firingRecently)
		lastEventAt = try c.decodeIfPresent(String.self, forKey: .lastEventAt)
		sourceOrigin = try c.decodeIfPresent(String.self, forKey: .sourceOrigin)
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

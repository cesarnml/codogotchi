import Foundation

/// View-model for the General tab.
///
/// Maps a `HooksStatusSnapshot` to per-platform display rows and builds the
/// diagnostics payload. Owns status refresh so the window controller can call
/// `refresh()` after any hook action and re-bind `rows`.
final class GeneralTabViewModel {
	/// A single platform row as the tab renders it.
	struct PlatformRow: Equatable {
		let name: String
		let installed: Bool
		let partiallyInstalled: Bool
		let firingRecently: Bool
		let lastEventAt: String?
		let sourceOrigin: String?
		let installable: Bool
	}

	/// Current per-platform rows. Updated by `applySnapshot(_:)` and `refresh()`.
	private(set) var rows: [PlatformRow] = []

	/// Most recent snapshot retained for diagnostics JSON assembly.
	private(set) var lastSnapshot: HooksStatusSnapshot?

	/// Version last recorded in `app-state.json` after a successful install/update.
	/// Set by `SettingsWindowController` after a successful hook operation.
	var installedHookVersion: String?

	/// True when the bundled binary is newer than the last-recorded installed version.
	var needsBannerUpdate: Bool {
		LockstepPolicy.needsUpdate(
			hooksInstalled: rows.contains { $0.installed },
			bundledVersion: hookVersion,
			installedVersion: installedHookVersion
		)
	}

	private let statusClient: HookStatusClient
	private let appVersion: String
	private let hookVersion: String

	init(
		statusClient: HookStatusClient = HookStatusClient(),
		appVersion: String = AboutViewModel.bundleShortVersion(),
		hookVersion: String = AboutViewModel.bundledHookVersion()
	) {
		self.statusClient = statusClient
		self.appVersion = appVersion
		self.hookVersion = hookVersion
	}

	/// Updates rows from an already-fetched snapshot. Safe to call on any queue.
	func applySnapshot(_ snapshot: HooksStatusSnapshot) {
		lastSnapshot = snapshot
		rows = [
			row("Codex", snapshot.codex),
			row("Claude Code", snapshot.claudeCode),
			row("Cursor", snapshot.cursor),
			row("VS Code", snapshot.vscode),
			row("Antigravity", snapshot.antigravity),
		]
	}

	/// Fetches a fresh snapshot from `statusClient` and applies it.
	/// Silently no-ops on client failure so callers are not broken by a missing CLI.
	func refresh() {
		guard let snap = try? statusClient.fetch() else { return }
		applySnapshot(snap)
	}

	/// Returns a JSON string suitable for clipboard diagnostics support.
	/// Shape matches `codogotchi hooks status --json`: all optional fields are
	/// emitted as `null` (never omitted) so support tooling sees the same schema
	/// as the CLI regardless of which platforms have fired recently.
	func diagnosticsJSON() -> String {
		let snap = lastSnapshot
		let dict: [String: Any] = [
			"codogotchi": appVersion,
			"hookBinary": hookVersion,
			"hooksStatus": snap.map { statusDict($0) } ?? ([String: Any]() as Any),
		]
		let data = (try? JSONSerialization.data(
			withJSONObject: dict,
			options: [.prettyPrinted, .sortedKeys]
		)) ?? Data()
		return String(data: data, encoding: .utf8) ?? "{}"
	}

	// MARK: - Private

	/// Builds the `hooksStatus` dict matching the `hooks status --json` contract.
	/// All optional fields are explicit `NSNull()` when absent so consumers see
	/// a stable schema rather than key-absent JSON.
	private func statusDict(_ snap: HooksStatusSnapshot) -> [String: Any] {
		return [
			"codex": platformDict(snap.codex),
			"claude_code": platformDict(snap.claudeCode),
			"cursor": platformDict(snap.cursor),
			"vscode": platformDict(snap.vscode),
			"antigravity": platformDict(snap.antigravity),
		]
	}

	private func platformDict(_ p: HooksStatusSnapshot.Platform) -> [String: Any] {
		return [
			"present_on_disk": p.presentOnDisk,
			"installable_in_phase": p.installableInPhase,
			"installed": p.installed,
			"partially_installed": p.partiallyInstalled,
			"firing_recently": p.firingRecently,
			"last_event_at": p.lastEventAt.map { $0 as Any } ?? (NSNull() as Any),
			"source_origin": p.sourceOrigin.map { $0 as Any } ?? (NSNull() as Any),
		]
	}

	private func row(_ name: String, _ p: HooksStatusSnapshot.Platform) -> PlatformRow {
		PlatformRow(
			name: name,
			installed: p.installed,
			partiallyInstalled: p.partiallyInstalled,
			firingRecently: p.firingRecently,
			lastEventAt: p.lastEventAt,
			sourceOrigin: p.sourceOrigin,
			installable: p.installableInPhase
		)
	}
}

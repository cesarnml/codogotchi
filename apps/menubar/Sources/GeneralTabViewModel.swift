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
		let firingRecently: Bool
		let lastEventAt: String?
		let sourceOrigin: String?
		let installable: Bool
	}

	/// Current per-platform rows. Updated by `applySnapshot(_:)` and `refresh()`.
	private(set) var rows: [PlatformRow] = []

	/// Most recent snapshot retained for diagnostics JSON assembly.
	private(set) var lastSnapshot: HooksStatusSnapshot?

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
	/// Shape: `{ "codogotchi": "<version>", "hookBinary": "<version>", "hooksStatus": { ... } }`
	func diagnosticsJSON() -> String {
		var dict: [String: Any] = [
			"codogotchi": appVersion,
			"hookBinary": hookVersion,
		]
		if let snap = lastSnapshot {
			let encoder = JSONEncoder()
			encoder.keyEncodingStrategy = .convertToSnakeCase
			encoder.outputFormatting = .sortedKeys
			if let data = try? encoder.encode(snap),
				let obj = try? JSONSerialization.jsonObject(with: data)
			{
				dict["hooksStatus"] = obj
			}
		}
		let data = (try? JSONSerialization.data(
			withJSONObject: dict,
			options: [.prettyPrinted, .sortedKeys]
		)) ?? Data()
		return String(data: data, encoding: .utf8) ?? "{}"
	}

	// MARK: - Private

	private func row(_ name: String, _ p: HooksStatusSnapshot.Platform) -> PlatformRow {
		PlatformRow(
			name: name,
			installed: p.installed,
			firingRecently: p.firingRecently,
			lastEventAt: p.lastEventAt,
			sourceOrigin: p.sourceOrigin,
			installable: p.installableInPhase
		)
	}
}

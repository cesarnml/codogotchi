import Foundation

/// Reports a single anonymous event to Convex the first time the app is
/// launched under a new version — the signal Sparkle auto-updates leave
/// behind. No user identifier is ever sent, just {appVersion, previousVersion,
/// platform}, and it fires at most once per version bump.
///
/// Deliberately kept out of `app-state.json`/`AppStateStore`: that file's
/// schema is shared with the CLI and floating-pet windows, and this is an
/// unrelated, purely-local bookkeeping concern.
enum UpdateTelemetryReporter {
	private static let apiBase = "https://savory-mosquito-241.convex.site"

	private static func storeURL() -> URL {
		CodogotchiFolders.dataFolderURL().appendingPathComponent("update-telemetry.json")
	}

	private struct Store: Codable {
		let lastReportedVersion: String
	}

	/// Call once per launch. No-op unless the current bundle version differs
	/// from the last one recorded — i.e. an update (Sparkle or manual) landed
	/// since the last launch. Silently records the current version on first
	/// run without reporting, so fresh installs don't count as an "update".
	///
	/// The marker is written *before* the network call, and skips sending
	/// entirely if the write fails — favoring a silently dropped event over a
	/// retry storm that would resend on every subsequent launch.
	static func reportIfUpdated(currentVersion: String) {
		let url = storeURL()
		let previous = (try? Data(contentsOf: url))
			.flatMap { try? JSONDecoder().decode(Store.self, from: $0) }
			.map(\.lastReportedVersion)

		guard previous != currentVersion else { return }

		let updated = Store(lastReportedVersion: currentVersion)
		guard let data = try? JSONEncoder().encode(updated) else { return }
		do {
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try data.write(to: url, options: .atomic)
		} catch {
			return
		}

		if let previous {
			send(appVersion: currentVersion, previousVersion: previous)
		}
	}

	private static func send(appVersion: String, previousVersion: String) {
		guard let url = URL(string: "\(apiBase)/track-update-install") else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: String] = [
			"appVersion": appVersion,
			"previousVersion": previousVersion,
			"platform": "macos",
		]
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)
		URLSession.shared.dataTask(with: request).resume()
	}
}

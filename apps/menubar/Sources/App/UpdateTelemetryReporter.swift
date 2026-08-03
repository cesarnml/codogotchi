import Foundation

/// Reports a single anonymous event to Convex the first time the app is
/// launched under a new build — the signal Sparkle auto-updates leave behind.
/// No user identifier is ever sent, just {appVersion, appBuild, previousVersion,
/// previousBuild, platform}, and it fires at most once per build bump.
///
/// Keyed on `CFBundleVersion` (the build) as well as `CFBundleShortVersionString`
/// (the marketing version) because Sparkle compares *builds*: it will happily
/// install build 18 over build 17 while both call themselves "3.1.0". Keying on
/// the marketing version alone made every such update invisible to telemetry.
///
/// Deliberately kept out of `app-state.json`/`AppStateStore`: that file's
/// schema is shared with the CLI and floating-pet windows, and this is an
/// unrelated, purely-local bookkeeping concern.
enum UpdateTelemetryReporter {
	private static let apiBase = "https://savory-mosquito-241.convex.site"

	static func storeURL() -> URL {
		CodogotchiFolders.dataFolderURL().appendingPathComponent("update-telemetry.json")
	}

	/// The payload handed to the network layer. Surfaced as a type (rather than
	/// inlined into `send`) so tests can assert on exactly what would be
	/// reported without performing a network call.
	struct Report: Equatable {
		let appVersion: String
		let appBuild: String
		let previousVersion: String
		let previousBuild: String?
	}

	/// `lastReportedBuild` is optional so markers written by <= 3.1.0 (which
	/// recorded only the marketing version) still decode. A nil build means
	/// "unknown, not yet backfilled" and is never treated as a build change —
	/// see `reportIfUpdated`.
	private struct Store: Codable {
		let lastReportedVersion: String
		let lastReportedBuild: String?
	}

	/// Call once per launch. No-op unless the current bundle version *or* build
	/// differs from the last one recorded — i.e. an update (Sparkle or manual)
	/// landed since the last launch. Silently records the current version on
	/// first run without reporting, so fresh installs don't count as an
	/// "update".
	///
	/// Markers written before build tracking existed carry no build. Those are
	/// backfilled silently on the next launch rather than reported, so shipping
	/// this change does not emit a phantom "update" event for every existing
	/// install.
	///
	/// The marker is written *before* the network call, and skips sending
	/// entirely if the write fails — favoring a silently dropped event over a
	/// retry storm that would resend on every subsequent launch.
	/// `url` and `emit` are injected so `UpdateTelemetryReporterTests` can drive
	/// every state of this machine against a temp file with no network calls.
	/// Production callers use the defaults.
	static func reportIfUpdated(
		currentVersion: String,
		currentBuild: String,
		url: URL = storeURL(),
		emit: (Report) -> Void = { send($0) }
	) {
		let previous = (try? Data(contentsOf: url))
			.flatMap { try? JSONDecoder().decode(Store.self, from: $0) }

		let versionChanged = previous?.lastReportedVersion != currentVersion
		// A nil previous build is "unknown" (pre-build-tracking marker), not a
		// change — reporting it would fire once for every existing install.
		let buildChanged = previous?.lastReportedBuild.map { $0 != currentBuild } ?? false

		guard versionChanged || buildChanged else {
			// Same version, no build recorded yet: backfill the marker quietly so
			// the *next* build bump is detectable, and report nothing.
			if previous?.lastReportedBuild == nil {
				_ = writeStore(version: currentVersion, build: currentBuild, to: url)
			}
			return
		}

		guard writeStore(version: currentVersion, build: currentBuild, to: url) else { return }

		if let previous {
			emit(
				Report(
					appVersion: currentVersion,
					appBuild: currentBuild,
					previousVersion: previous.lastReportedVersion,
					previousBuild: previous.lastReportedBuild
				)
			)
		}
	}

	/// Atomically persists the marker. Returns false if encoding or the write
	/// failed, in which case the caller must not report.
	private static func writeStore(version: String, build: String, to url: URL) -> Bool {
		let updated = Store(lastReportedVersion: version, lastReportedBuild: build)
		guard let data = try? JSONEncoder().encode(updated) else { return false }
		do {
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try data.write(to: url, options: .atomic)
		} catch {
			return false
		}
		return true
	}

	private static func send(_ report: Report) {
		guard let url = URL(string: "\(apiBase)/track-update-install") else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		var body: [String: String] = [
			"appVersion": report.appVersion,
			"appBuild": report.appBuild,
			"previousVersion": report.previousVersion,
			"platform": "macos",
		]
		if let previousBuild = report.previousBuild {
			body["previousBuild"] = previousBuild
		}
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)
		URLSession.shared.dataTask(with: request).resume()
	}
}

import Foundation

/// TTL presets for the idle-dismiss picker, in display order.
enum IdleDismissTTL: Int, CaseIterable {
	case oneMinute = 60
	case fiveMinutes = 300
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case never = 0

	var label: String {
		switch self {
		case .oneMinute: return "1 minute"
		case .fiveMinutes: return "5 minutes"
		case .fifteenMinutes: return "15 minutes"
		case .thirtyMinutes: return "30 minutes"
		case .oneHour: return "1 hour"
		case .never: return "Never"
		}
	}

	/// Returns the preset whose rawValue matches `seconds`, or nil if no match.
	static func matching(_ seconds: Int) -> IdleDismissTTL? {
		allCases.first { $0.rawValue == seconds }
	}
}

/// View model for the Customization settings tab.
///
/// Exposes per-platform mode pickers and an idle-dismiss TTL picker.
/// Changes are immediately persisted to `customization.json` via a
/// read-merge-write so unmanaged keys (e.g. `menubar_icon_monochrome`)
/// are never clobbered.
final class CustomizationTabViewModel {
	/// Fixed origin list mirroring the TS `SourceEventOrigin` union.
	/// Shown in stable display order so the UI is consistent across sessions.
	static let origins: [String] = [
		"claude_code", "vscode", "codex", "cursor", "antigravity",
	]

	private(set) var platformModes: [String: PlatformMode]
	private(set) var idleDismissTtlSeconds: Int
	private let filePath: String

	init(filePath: String = CodogotchiFolders.customizationPath()) {
		self.filePath = filePath
		let snapshot = CustomizationJsonReader.read(at: filePath)
		self.platformModes = snapshot.platformModes
		self.idleDismissTtlSeconds = snapshot.idleDismissTtlSeconds
	}

	func mode(for origin: String) -> PlatformMode {
		platformModes[origin] ?? .own
	}

	func setMode(_ mode: PlatformMode, for origin: String) {
		if mode == .own {
			platformModes.removeValue(forKey: origin)
		} else {
			platformModes[origin] = mode
		}
		persist()
	}

	func setTTL(_ seconds: Int) {
		idleDismissTtlSeconds = seconds
		persist()
	}

	// MARK: - Private

	private func persist() {
		let url = URL(fileURLWithPath: filePath)
		// Read-merge-write: load existing keys first so unmanaged keys
		// (e.g. menubar_icon_monochrome written by P13.07) survive this write.
		var payload: [String: Any] = [:]
		let fileExists = FileManager.default.fileExists(atPath: filePath)
		if fileExists {
			// Abort if the file exists but cannot be read or parsed — starting from
			// {} would silently clobber unmanaged keys like menubar_icon_monochrome.
			guard let data = try? Data(contentsOf: url),
				let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			else {
				NSLog(
					"CustomizationTabViewModel: aborting write — existing file unreadable or not a JSON object"
				)
				return
			}
			payload = existing
		}
		// Seed schema_version on new files; preserve it from existing files.
		if payload["schema_version"] == nil {
			payload["schema_version"] = 1
		}
		let modesPayload: [String: String] = platformModes.mapValues { $0.rawValue }
		if modesPayload.isEmpty {
			payload.removeValue(forKey: "platform_modes")
		} else {
			payload["platform_modes"] = modesPayload
		}
		payload["idle_dismiss_ttl_seconds"] = idleDismissTtlSeconds
		guard JSONSerialization.isValidJSONObject(payload),
			let data = try? JSONSerialization.data(
				withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
		else { return }
		try? data.write(to: url, options: .atomic)
	}
}

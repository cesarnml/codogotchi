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
		var proposed = platformModes
		if mode == .own {
			proposed.removeValue(forKey: origin)
		} else {
			proposed[origin] = mode
		}
		// NSNull removes the key when all modes are default (.own), avoiding an
		// empty platform_modes object in the file.
		let modesValue: Any =
			proposed.isEmpty ? NSNull() : proposed.mapValues { $0.rawValue }
		do {
			try ConfigFileWriter.merge(
				["platform_modes": modesValue],
				into: URL(fileURLWithPath: filePath)
			)
			platformModes = proposed
		} catch {
			NSLog("CustomizationTabViewModel: mode write failed — \(error)")
		}
	}

	func setTTL(_ seconds: Int) {
		do {
			try ConfigFileWriter.merge(
				["idle_dismiss_ttl_seconds": seconds],
				into: URL(fileURLWithPath: filePath)
			)
			idleDismissTtlSeconds = seconds
		} catch {
			NSLog("CustomizationTabViewModel: TTL write failed — \(error)")
		}
	}
}

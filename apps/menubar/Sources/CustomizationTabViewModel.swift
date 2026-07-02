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

/// Session Cap dropdown options for the Platform Settings card: 2–10 (no 1,
/// since a cap of 1 defeats the point of session-keyed panels) plus Unlimited,
/// which persists as `CustomizationSnapshot.unlimitedSessionCap` (`0`).
enum SessionCapOption: Int, CaseIterable {
	case two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10
	case unlimited = 0

	var label: String {
		self == .unlimited ? "Unlimited" : "\(rawValue)"
	}

	/// Returns the option whose rawValue matches `cap`, or nil if no match.
	static func matching(_ cap: Int) -> SessionCapOption? {
		allCases.first { $0.rawValue == cap }
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
	private(set) var combinedMinimalistEnabled: Bool
	private(set) var minimalistBadgeScale: Double
	private(set) var sessionPetsEnabled: [String: Bool]
	private(set) var sessionCap: [String: Int]
	private let filePath: String

	init(filePath: String = CodogotchiFolders.customizationPath()) {
		self.filePath = filePath
		let snapshot = CustomizationJsonReader.read(at: filePath)
		self.platformModes = snapshot.platformModes
		self.idleDismissTtlSeconds = snapshot.idleDismissTtlSeconds
		self.combinedMinimalistEnabled = snapshot.combinedMinimalistEnabled
		self.minimalistBadgeScale = snapshot.minimalistBadgeScale
		self.sessionPetsEnabled = snapshot.sessionPetsEnabled
		self.sessionCap = snapshot.sessionCap
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

	func setCombinedMinimalistEnabled(_ enabled: Bool) {
		do {
			try ConfigFileWriter.merge(
				["combined_minimalist_enabled": enabled],
				into: URL(fileURLWithPath: filePath)
			)
			combinedMinimalistEnabled = enabled
		} catch {
			NSLog("CustomizationTabViewModel: combined-minimalist write failed — \(error)")
		}
	}

	/// Effective per-origin session cap for UI display: the persisted value, or
	/// the shared default (`CustomizationSnapshot.defaultSessionCap`) when the
	/// origin has never had an explicit cap written. Read-only resolution —
	/// does not itself persist anything.
	func effectiveSessionCap(for origin: String) -> Int {
		sessionCap[origin] ?? CustomizationSnapshot.defaultSessionCap
	}

	func setSessionPetsEnabled(_ enabled: Bool, for origin: String) {
		var proposed = sessionPetsEnabled
		proposed[origin] = enabled
		do {
			try ConfigFileWriter.merge(
				["session_pets_enabled": proposed],
				into: URL(fileURLWithPath: filePath)
			)
			sessionPetsEnabled = proposed
		} catch {
			NSLog("CustomizationTabViewModel: session-pets-enabled write failed — \(error)")
		}
	}

	/// Persists the per-origin session cap. Callers pass
	/// `CustomizationSnapshot.unlimitedSessionCap` (`0`) for the Unlimited option.
	func setSessionCap(_ cap: Int, for origin: String) {
		var proposed = sessionCap
		proposed[origin] = cap
		do {
			try ConfigFileWriter.merge(
				["session_cap": proposed],
				into: URL(fileURLWithPath: filePath)
			)
			sessionCap = proposed
		} catch {
			NSLog("CustomizationTabViewModel: session-cap write failed — \(error)")
		}
	}

	func setMinimalistBadgeScale(_ scale: Double) {
		let clamped = max(
			Double(GateBadgeLayout.achievableMinScale), min(Double(GateBadgeLayout.achievableMaxScale), scale)
		)
		do {
			try ConfigFileWriter.merge(
				["minimalist_badge_scale": clamped],
				into: URL(fileURLWithPath: filePath)
			)
			minimalistBadgeScale = clamped
		} catch {
			NSLog("CustomizationTabViewModel: badge scale write failed — \(error)")
		}
	}
}

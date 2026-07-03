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
	private(set) var sessionPetsActivatedAt: [String: String]
	private(set) var sessionPetsGrandfatheredSessionId: [String: String]
	private let filePath: String
	/// Live `state.d/` directory read at the instant session-pets is toggled
	/// on for an origin, to identify the session to grandfather in as
	/// "Session 1". Overridable so tests can point at a fixture directory.
	private let stateDirectoryPath: String
	/// `session-labels.json` path, read/written to carry the plain-origin
	/// custom label over to the grandfathered session on an off->on toggle.
	/// Overridable so tests do not touch the real file.
	private let sessionLabelPath: String
	/// Clock used to stamp `sessionPetsActivatedAt` on an off->on toggle.
	/// Overridable so tests can assert exact, non-flaky timestamps instead of
	/// racing the wall clock's 1-second ISO 8601 string resolution.
	private let now: () -> Date

	init(
		filePath: String = CodogotchiFolders.customizationPath(),
		stateDirectoryPath: String = CodogotchiFolders.stateDirectoryPath(),
		sessionLabelPath: String = SessionLabelStore.path(),
		now: @escaping () -> Date = Date.init
	) {
		self.filePath = filePath
		self.stateDirectoryPath = stateDirectoryPath
		self.sessionLabelPath = sessionLabelPath
		self.now = now
		let snapshot = CustomizationJsonReader.read(at: filePath)
		self.platformModes = snapshot.platformModes
		self.idleDismissTtlSeconds = snapshot.idleDismissTtlSeconds
		self.combinedMinimalistEnabled = snapshot.combinedMinimalistEnabled
		self.minimalistBadgeScale = snapshot.minimalistBadgeScale
		self.sessionPetsEnabled = snapshot.sessionPetsEnabled
		self.sessionCap = snapshot.sessionCap
		self.sessionPetsActivatedAt = snapshot.sessionPetsActivatedAt
		self.sessionPetsGrandfatheredSessionId = snapshot.sessionPetsGrandfatheredSessionId
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
	/// origin has never had an explicit cap written, or the value is negative
	/// (matching `CustomizationSnapshot.sessionCap`'s documented "absent or
	/// negative" contract — a negative value can only reach the file via manual
	/// edit, since this VM never writes one). `0` (Unlimited) is a real value
	/// and passes through unchanged. Read-only resolution — does not itself
	/// persist anything.
	func effectiveSessionCap(for origin: String) -> Int {
		guard let cap = sessionCap[origin], cap >= 0 else {
			return CustomizationSnapshot.defaultSessionCap
		}
		return cap
	}

	func setSessionPetsEnabled(_ enabled: Bool, for origin: String) {
		let wasEnabled = sessionPetsEnabled[origin] ?? false
		var proposed = sessionPetsEnabled
		proposed[origin] = enabled

		var updates: [String: Any] = ["session_pets_enabled": proposed]
		var proposedActivatedAt = sessionPetsActivatedAt
		var proposedGrandfather = sessionPetsGrandfatheredSessionId

		// Off->on transition: re-arm the grandfather/activity gate for this
		// origin. Every prior toggle's activation state is overwritten, matching
		// "resets every time a user goes from off to on" — a stale grandfather
		// from a much earlier toggle must never linger into this one.
		if enabled, !wasEnabled {
			proposedActivatedAt[origin] = ISO8601DateFormatter().string(from: now())
			if let winnerSessionId = Self.currentWinnerSessionId(
				for: origin, stateDirectoryPath: stateDirectoryPath
			) {
				proposedGrandfather[origin] = winnerSessionId
			} else {
				// No live session for this origin right now — nothing to
				// grandfather; the first session with activity after `now`
				// becomes Session 1 naturally under the activity gate.
				proposedGrandfather.removeValue(forKey: origin)
			}
			updates["session_pets_activated_at"] = proposedActivatedAt
			updates["session_pets_grandfathered_session_id"] = proposedGrandfather
		}

		do {
			try ConfigFileWriter.merge(updates, into: URL(fileURLWithPath: filePath))
			sessionPetsEnabled = proposed
			sessionPetsActivatedAt = proposedActivatedAt
			sessionPetsGrandfatheredSessionId = proposedGrandfather
		} catch {
			NSLog("CustomizationTabViewModel: session-pets-enabled write failed — \(error)")
			return
		}

		// Carry over the plain-origin window's existing custom label (if any)
		// to the grandfathered session's new key, so a rename survives the
		// toggle. Runs only after the customization write above succeeds, and
		// only when a grandfather was actually identified.
		if enabled, !wasEnabled, let winnerSessionId = proposedGrandfather[origin],
			let existingLabel = SessionLabelStore.label(for: origin, at: sessionLabelPath)
		{
			SessionLabelStore.setLabel(existingLabel, for: "\(origin):\(winnerSessionId)", at: sessionLabelPath)
		}
	}

	/// Resolves the `session_id` currently winning render selection for
	/// `origin` — the freshest non-stale-mtime slice in `state.d/`, matching
	/// `StateJsonReader`'s winner semantics — or `nil` when no live session
	/// exists for it. Used at the instant session-pets is toggled on so that
	/// session can be grandfathered in as "Session 1" instead of every live
	/// sibling appearing at once.
	private static func currentWinnerSessionId(
		for origin: String, stateDirectoryPath: String
	) -> String? {
		guard
			case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
				at: stateDirectoryPath)
		else { return nil }
		let prefix = "\(origin):"
		let winner = perSession
			.filter { $0.key.hasPrefix(prefix) }
			.max { a, b in
				let dateA = StateJsonReader.parseISO8601Date(a.value.updatedAt) ?? .distantPast
				let dateB = StateJsonReader.parseISO8601Date(b.value.updatedAt) ?? .distantPast
				return dateA < dateB
			}
		guard let winnerKey = winner?.key else { return nil }
		return String(winnerKey.dropFirst(prefix.count))
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

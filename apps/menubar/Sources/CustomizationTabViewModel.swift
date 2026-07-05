import Foundation

/// Shared shape for an `Int`-backed Settings picker preset: `rawValue` is the
/// persisted value, `label` is the picker's display text, and `matching(_:)`
/// resolves a persisted value back to its case. `IdleDismissTTL`,
/// `IdleEscalationTiming`, and `SessionCapOption` all conform instead of each
/// hand-rolling the identical `matching(_:)` lookup.
protocol LabeledIntPreset: RawRepresentable, CaseIterable where RawValue == Int {
	var label: String { get }
}

extension LabeledIntPreset {
	/// Returns the case whose rawValue matches `value`, or nil if no match.
	static func matching(_ value: Int) -> Self? {
		allCases.first { $0.rawValue == value }
	}
}

/// TTL presets for the idle-dismiss picker, in display order.
enum IdleDismissTTL: Int, LabeledIntPreset {
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
}

/// Timing presets for the Pet Idle Escalation Timing pickers ("Impatient
/// After:"/"Frustrated After:"), in display order. `allCases` order doubles
/// as the "next step up" ordering `CustomizationTabViewModel` uses to keep
/// Frustrated above Impatient — every non-`.never` case's `rawValue` is its
/// seconds count, already ascending in declaration order.
enum IdleEscalationTiming: Int, LabeledIntPreset {
	case fiveMinutes = 300
	case tenMinutes = 600
	case thirtyMinutes = 1800
	case sixtyMinutes = 3600
	case oneTwentyMinutes = 7200
	case never = 0

	var label: String {
		switch self {
		case .fiveMinutes: return "5 minutes"
		case .tenMinutes: return "10 minutes"
		case .thirtyMinutes: return "30 minutes"
		case .sixtyMinutes: return "60 minutes"
		case .oneTwentyMinutes: return "120 minutes"
		case .never: return "Never"
		}
	}
}

/// Session Cap dropdown options for the Platform Settings card: 2–10 (no 1,
/// since a cap of 1 defeats the point of session-keyed panels) plus Unlimited,
/// which persists as `CustomizationSnapshot.unlimitedSessionCap` (`0`).
enum SessionCapOption: Int, LabeledIntPreset {
	case two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10
	case unlimited = 0

	var label: String {
		self == .unlimited ? "Unlimited" : "\(rawValue)"
	}
}

extension Notification.Name {
	/// Posted after a `customization.json` write made outside the Settings UI —
	/// the floating panels' right-click mode-switch affordances (Pet Mode ↔
	/// Minimalist Mode) — so an open Customization tab can `reload()` its view
	/// model and re-sync its controls. The Settings tab's own writes never post
	/// this; its controls are already the source of those changes.
	static let customizationDidChangeExternally = Notification.Name(
		"CodogotchiCustomizationDidChangeExternally")
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
	private(set) var idleImpatientSeconds: Int
	private(set) var idleFrustratedSeconds: Int
	private(set) var evictSessionPetsEnabled: Bool
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
		self.idleImpatientSeconds = snapshot.idleImpatientSeconds
		self.idleFrustratedSeconds = snapshot.idleFrustratedSeconds
		self.evictSessionPetsEnabled = snapshot.evictSessionPetsEnabled
	}

	/// Re-reads `customization.json` and replaces all in-memory state. Used when
	/// another writer changed the file behind this instance's back — e.g. the
	/// floating panels' right-click mode-switch affordances, which persist via
	/// their own short-lived view model and then post
	/// `.customizationDidChangeExternally` so the open Settings tab can re-sync.
	func reload() {
		let snapshot = CustomizationJsonReader.read(at: filePath)
		platformModes = snapshot.platformModes
		idleDismissTtlSeconds = snapshot.idleDismissTtlSeconds
		combinedMinimalistEnabled = snapshot.combinedMinimalistEnabled
		minimalistBadgeScale = snapshot.minimalistBadgeScale
		sessionPetsEnabled = snapshot.sessionPetsEnabled
		sessionCap = snapshot.sessionCap
		sessionPetsActivatedAt = snapshot.sessionPetsActivatedAt
		sessionPetsGrandfatheredSessionId = snapshot.sessionPetsGrandfatheredSessionId
		idleImpatientSeconds = snapshot.idleImpatientSeconds
		idleFrustratedSeconds = snapshot.idleFrustratedSeconds
		evictSessionPetsEnabled = snapshot.evictSessionPetsEnabled
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

	/// Persists the Impatient threshold. Also bumps the Frustrated threshold to
	/// the next timed option above the new Impatient value (wrapping to
	/// `.never` past the last option) when Frustrated would no longer sit
	/// strictly above it — this is the "Frustrated defaults to one step above
	/// Impatient" coupling. `IdleEscalationTiming`'s rawValue IS its seconds
	/// count and every non-`.never` case is already declared in ascending
	/// order, so "next option above" is a plain rawValue comparison rather
	/// than an index lookup.
	///
	/// Setting Impatient to "Never" also forces Frustrated to "Never": with
	/// Impatient disabled there is nothing left for Frustrated to sit above,
	/// and `escalation(forElapsed:)` checks the Frustrated threshold first —
	/// leaving a stale finite Frustrated value would let the pet escalate
	/// straight to "Frustrated" even though the user asked to disable
	/// escalation. Only reacts to Impatient changes; `setIdleFrustratedSeconds`
	/// never adjusts Impatient back.
	func setIdleImpatientSeconds(_ seconds: Int) {
		let timedOptions = IdleEscalationTiming.allCases.filter { $0 != .never }
		let newFrustrated: Int
		if seconds == IdleEscalationTiming.never.rawValue {
			newFrustrated = IdleEscalationTiming.never.rawValue
		} else if idleFrustratedSeconds != IdleEscalationTiming.never.rawValue,
			idleFrustratedSeconds > seconds
		{
			newFrustrated = idleFrustratedSeconds
		} else {
			newFrustrated = (timedOptions.first { $0.rawValue > seconds } ?? .never).rawValue
		}
		do {
			try ConfigFileWriter.merge(
				[
					"idle_impatient_seconds": seconds,
					"idle_frustrated_seconds": newFrustrated,
				],
				into: URL(fileURLWithPath: filePath)
			)
			idleImpatientSeconds = seconds
			idleFrustratedSeconds = newFrustrated
		} catch {
			NSLog("CustomizationTabViewModel: idle-impatient write failed — \(error)")
		}
	}

	/// Persists the Frustrated threshold directly — never adjusts Impatient.
	func setIdleFrustratedSeconds(_ seconds: Int) {
		do {
			try ConfigFileWriter.merge(
				["idle_frustrated_seconds": seconds],
				into: URL(fileURLWithPath: filePath)
			)
			idleFrustratedSeconds = seconds
		} catch {
			NSLog("CustomizationTabViewModel: idle-frustrated write failed — \(error)")
		}
	}

	/// Persists the "Evict Session Pets" kill-switch. `true` (default)
	/// preserves today's rank-based session-cap eviction; `false` protects
	/// every incumbent session from eviction regardless of rank.
	func setEvictSessionPetsEnabled(_ enabled: Bool) {
		do {
			try ConfigFileWriter.merge(
				["evict_session_pets_enabled": enabled],
				into: URL(fileURLWithPath: filePath)
			)
			evictSessionPetsEnabled = enabled
		} catch {
			NSLog("CustomizationTabViewModel: evict-session-pets write failed — \(error)")
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
			// Fractional seconds matter here: a whole-seconds-only timestamp
			// truncates toward the past, so a sibling session's write from just
			// before the real toggle instant (but within the same wall-clock
			// second) would wrongly parse as strictly after the truncated
			// activation and slip past the gate below.
			let formatter = ISO8601DateFormatter()
			formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
			proposedActivatedAt[origin] = formatter.string(from: now())
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
		// toggle. Runs only after the customization write above succeeds, only
		// when a grandfather was actually identified, and only when that exact
		// session doesn't already have its own label — a session-pets-on rename
		// made directly to the grandfathered key (from an earlier activation
		// cycle) is more specific than the collapsed plain-origin label and
		// must not be clobbered by it.
		if enabled, !wasEnabled, let winnerSessionId = proposedGrandfather[origin],
			let existingLabel = SessionLabelStore.label(for: origin, at: sessionLabelPath)
		{
			let grandfatherKey = "\(origin):\(winnerSessionId)"
			if SessionLabelStore.label(for: grandfatherKey, at: sessionLabelPath) == nil {
				SessionLabelStore.setLabel(existingLabel, for: grandfatherKey, at: sessionLabelPath)
			}
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
		// Sorted iteration + strict `>` (not `max(by:)` over the raw Dictionary)
		// mirrors resolveRenderKeys's tie-break exactly: an unsorted Dictionary's
		// iteration order is unspecified, so two sessions sharing an identical
		// `updated_at` would otherwise resolve to an arbitrary, run-to-run
		// nondeterministic winner instead of the lexicographically first key.
		var winnerKey: String?
		var winnerDate = Date.distantPast
		for key in perSession.keys.sorted() where key.hasPrefix(prefix) {
			guard let snapshot = perSession[key] else { continue }
			let date = StateJsonReader.parseISO8601Date(snapshot.updatedAt) ?? .distantPast
			guard date > winnerDate else { continue }
			winnerDate = date
			winnerKey = key
		}
		guard let winnerKey else { return nil }
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

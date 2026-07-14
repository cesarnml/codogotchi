import Foundation

/// All 19 states of the v4 animation-state-vocabulary closed enum.
///
/// Raw values match the hook's emitted strings exactly (snake_case). Any string
/// not in this enum — including future states the renderer has not yet painted —
/// decodes as `.idle` via `init(from:)`. This is the "unknown-state → idle"
/// fallback preserved through all phases.
///
/// Closed-enum decoding (no `unknown(String)` case) is deliberate: the renderer
/// must `switch` exhaustively without a `default:` and the contract doc forbids
/// string escape hatches.
enum ActivityState: String, Equatable, Codable, CaseIterable {
	// Floor / hook states
	case idle = "idle"
	case revive = "revive"
	case standby = "standby"
	case errored = "errored"
	case waitingForInput = "waiting_for_input"
	// Heuristic-tier hook states (Codex sheet rows 7–8)
	case implementing = "implementing"
	case editing = "editing"
	case searching = "searching"
	case webSearch = "web_search"
	case verifying = "verifying"
	case gitOps = "git_ops"
	case testing = "testing"
	case thinking = "thinking"
	case reading = "reading"
	case cramming = "cramming"
	// SoA gate states (codogotchi sheet — reliable tier)
	case ticketStarted = "ticket_started"
	case redTdd = "red_tdd"
	case greenTdd = "green_tdd"
	case adversarialReview = "adversarial_review"
	case openPr = "open_pr"
	case pollReview = "poll_review"
	case recordReview = "record_review"
	case advance = "advance"
	case ticketCompleted = "ticket_completed"
	case reviewClean = "review_clean"

	init(from decoder: Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = ActivityState(rawValue: raw) ?? .idle
	}

	/// Short, human-readable label for the floating-pet animation badge.
	/// Distinct from `rawValue` (the snake_case wire string): concise title-case
	/// copy a user reads at a glance. The three review-family gate states are
	/// disambiguated (`Adv Review` / `Polling` / `Recording` / `Review Clean`).
	var displayLabel: String {
		switch self {
		case .idle: return "Idle"
		case .revive: return "Revive"
		case .standby: return "Standby"
		case .errored: return "Error"
		case .waitingForInput: return "Waiting"
		case .implementing: return "Coding"
		case .editing: return "Editing"
		case .searching: return "Searching"
		case .webSearch: return "Web Search"
		case .verifying: return "Verifying"
		case .gitOps: return "Git Ops"
		case .testing: return "Testing"
		case .thinking: return "Thinking"
		case .reading: return "Reading"
		case .cramming: return "Cramming"
		case .ticketStarted: return "Ticket Start"
		case .redTdd: return "Red TDD"
		case .greenTdd: return "Green TDD"
		case .adversarialReview: return "Adv Review"
		case .openPr: return "Open PR"
		case .pollReview: return "Polling"
		case .recordReview: return "Recording"
		case .advance: return "Advancing"
		case .ticketCompleted: return "Ticket Done"
		case .reviewClean: return "Review Clean"
		}
	}

	/// True while the badge represents the agent *actively working* ("in flight").
	/// Drives the scanning shimmer on the animation badge label — a moving
	/// highlight that reads as live progress. The four floor states
	/// (idle/standby/errored/waiting), including escalated-idle, are at rest and
	/// render the label statically. Every heuristic-tier and gate state shimmers.
	var isInFlight: Bool {
		switch self {
		case .idle, .standby, .errored, .waitingForInput:
			return false
		default:
			return true
		}
	}
}

/// Subset of the hook's `source_event` payload that the transition log
/// records alongside each observed state change. Field names match the
/// contract doc (`docs/contracts/animation-state-vocabulary.md`) verbatim:
/// `origin`, `kind`, `name`. Optional in `StateSnapshot` because earlier
/// hook versions and demo fixtures may omit the field entirely.
struct SourceEvent: Equatable, Decodable {
	let origin: String?
	let kind: String?
	let name: String?
	let repoRoot: String?
	/// macOS bundle ID of the terminal that launched the hook process, populated
	/// by `detectTerminalBundleId` in hook-binary.ts. Used by the Focus button
	/// to bring the correct app to front for CLI-sourced hooks (claude_code, codex
	/// CLI) where the target is the terminal, not a fixed IDE app.
	let terminalBundleId: String?

	init(
		origin: String?,
		kind: String?,
		name: String?,
		repoRoot: String? = nil,
		terminalBundleId: String? = nil
	) {
		self.origin = origin
		self.kind = kind
		self.name = name
		self.repoRoot = repoRoot
		self.terminalBundleId = terminalBundleId
	}
}

/// The `attention` object from the v3 schema. Present when `activity_state`
/// is `standby` or `errored`; absent otherwise. `expiresAt` drives the renderer's
/// TTL policy (P6.07): if the timestamp is in the past the renderer treats the
/// state as `idle` regardless of the written `activity_state`. `summary` and
/// `reasonKind` are the user-facing copy shown in the attention bubble (P6.08).
struct AttentionPayload: Equatable, Decodable {
	let createdAt: String?
	let expiresAt: String?
	let summary: String?
	let reasonKind: String?
}

extension AttentionPayload {
	/// Returns true when `expiresAt` is parseable and strictly in the past.
	/// Mirrors the two-pass ISO 8601 strategy in `StateJsonReader.resolveActivityState`.
	func isExpired(now: Date = Date()) -> Bool {
		guard let str = expiresAt else { return false }
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: str) { return d < now }
		fmt.formatOptions = [.withInternetDateTime]
		if let d = fmt.date(from: str) { return d < now }
		return false
	}
}

/// Decoded form of `~/.codogotchi/state.json` v1.
///
/// Only the fields Phase 02 reads are declared. The schema permits richer
/// payloads (`hp`, `hp_overlay`); those are tolerated as unknown JSON keys
/// and ignored by `JSONDecoder` so the renderer cannot crash on shapes it
/// does not yet paint. `sourceEvent` is the one nested object the renderer
/// does consume — the transition log (P2.08) writes its `origin`/`kind`/
/// `name` triplet on every observed state change. `attention` carries the
/// TTL expiry for `standby` states (P6.07).
struct StateSnapshot: Equatable {
	let schemaVersion: Int
	let activityState: ActivityState
	let updatedAt: String
	let sourceEvent: SourceEvent?
	let attention: AttentionPayload?
	/// Raw Bash/Shell command string the producer classified, when the event
	/// was a shell tool use. Carried through so the transition log can record
	/// which command drove a state change — the signal needed to audit the
	/// producer-side bucketing heuristic after the fact.
	let toolCommand: String?
	// v5 RPG progression fields (P10.06). Absent for ≤v4 payloads; default to
	// safe values so the HUD renders sensibly before the first v5 write.
	let level: Int
	let levelFraction: Double
	let halfHearts: Int
	/// Active-minute carry toward the next half-heart (0…59). Drives the revival
	/// progress meter shown while the pet is ghosted: fraction = activeMinutes / 60.
	/// Absent for ≤v4 payloads and older v5 writers — defaults to 0.
	let activeMinutes: Int
	/// ISO 8601 datetime string or nil. Nil means no activity recorded yet
	/// (fresh install / null from writer) — the decay engine treats nil as "no decay".
	let lastActivityAt: String?
	/// v6 revive hint (P-revive). ISO 8601 datetime the writer sets to now+5s on a
	/// half-heart *gain*; nil when no gain occurred on this write. While it parses
	/// and is in the future the renderer plays the revive celebration. Absent for
	/// ≤v5 payloads — defaults to nil.
	let reviveUntil: String?
	/// v10 sticky clocks (P20.01/P20.02). Raw ISO 8601 strings, carried through
	/// verbatim — parsing to `Date` happens at the point of use (`PromptTimerTracker`,
	/// the future Settings > Sessions "Started" subtitle). All four are optional
	/// and independently nil-able: a ≤v9 payload, or any payload the hook did not
	/// stamp, omits some or all of them, and every consumer falls back to today's
	/// `updated_at` heuristics when a stamp it needs is absent.
	///
	/// `promptStartedAt` — when the current in-flight turn began.
	let promptStartedAt: String?
	/// `sessionStartedAt` — when this session file was first born; unlike the
	/// other three, this one is NOT a turn clock and survives Force Idle / any
	/// other idle rewrite of the slice.
	let sessionStartedAt: String?
	/// `erroredSince` — when the slice entered its current uninterrupted errored
	/// run; the tracker freezes 60s after this stamp rather than after whichever
	/// poll tick happened to first observe the errored state.
	let erroredSince: String?
	/// `turnEndedAt` — when the current turn's clock froze/ended (e.g. entering
	/// standby with an active attention bubble).
	let turnEndedAt: String?

	init(
		schemaVersion: Int,
		activityState: ActivityState,
		updatedAt: String,
		sourceEvent: SourceEvent?,
		attention: AttentionPayload?,
		toolCommand: String? = nil,
		level: Int = 1,
		levelFraction: Double = 0.0,
		halfHearts: Int = 6,
		activeMinutes: Int = 0,
		lastActivityAt: String? = nil,
		reviveUntil: String? = nil,
		promptStartedAt: String? = nil,
		sessionStartedAt: String? = nil,
		erroredSince: String? = nil,
		turnEndedAt: String? = nil
	) {
		self.schemaVersion = schemaVersion
		self.activityState = activityState
		self.updatedAt = updatedAt
		self.sourceEvent = sourceEvent
		self.attention = attention
		self.toolCommand = toolCommand
		self.level = level
		self.levelFraction = levelFraction
		self.halfHearts = halfHearts
		self.activeMinutes = activeMinutes
		self.lastActivityAt = lastActivityAt
		self.reviveUntil = reviveUntil
		self.promptStartedAt = promptStartedAt
		self.sessionStartedAt = sessionStartedAt
		self.erroredSince = erroredSince
		self.turnEndedAt = turnEndedAt
	}
}

/// Renderer-internal escalation of the `idle` state by elapsed-idle time.
/// These are NOT `ActivityState` cases (the wire enum never leaves `idle`);
/// they select alternate lite-sheet rows and an escalated badge label while the
/// agent stays continuously idle, and reset on the next state transition.
enum IdleEscalation: Equatable {
	case none
	case impatient
	case frustrated

	/// Badge copy while escalated. `nil` at `.none` so the badge falls back to
	/// the underlying state's `displayLabel` ("Idle").
	var badgeLabel: String? {
		switch self {
		case .none: return nil
		case .impatient: return "Impatient"
		case .frustrated: return "Frustrated"
		}
	}
}

/// Elapsed-idle thresholds that drive `IdleEscalation`. Production defaults are
/// 5 minutes → impatient, 10 minutes → frustrated. Both are overridable from the
/// environment for fast manual testing (values in milliseconds):
///   `CODOGOTCHI_IDLE_IMPATIENT_MS` / `CODOGOTCHI_IDLE_FRUSTRATED_MS`.
struct IdleEscalationConfig: Equatable {
	var impatientAfter: TimeInterval
	var frustratedAfter: TimeInterval

	static let production = IdleEscalationConfig(
		impatientAfter: 5 * 60,
		frustratedAfter: 10 * 60
	)

	/// Resolves the effective config: `customization` (Settings > Customization's
	/// persisted `idle_impatient_seconds`/`idle_frustrated_seconds`, `0` treated
	/// as "Never") seeds the base, then the environment variables below are
	/// still honored on top for fast manual/demo testing — this keeps `tcib`
	/// and similar tooling working unchanged even once the thresholds are
	/// user-configurable.
	static func resolve(
		customization: CustomizationSnapshot? = nil,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> IdleEscalationConfig {
		var config = production
		if let customization {
			config.impatientAfter = customization.idleImpatientSeconds == 0
				? .infinity : TimeInterval(customization.idleImpatientSeconds)
			config.frustratedAfter = customization.idleFrustratedSeconds == 0
				? .infinity : TimeInterval(customization.idleFrustratedSeconds)
		}
		if let seconds = positiveSeconds(environment["CODOGOTCHI_IDLE_IMPATIENT_MS"]) {
			config.impatientAfter = seconds
		}
		if let seconds = positiveSeconds(environment["CODOGOTCHI_IDLE_FRUSTRATED_MS"]) {
			config.frustratedAfter = seconds
		}
		return config
	}

	/// Escalation level for a continuous-idle `elapsed` duration (seconds).
	func escalation(forElapsed elapsed: TimeInterval) -> IdleEscalation {
		if elapsed >= frustratedAfter { return .frustrated }
		if elapsed >= impatientAfter { return .impatient }
		return .none
	}

	/// The minimum continuous-idle elapsed time that maps to `level` — i.e. the
	/// floor of that level's window. Inverse of `escalation(forElapsed:)`, used
	/// to re-anchor the idle clock after a manual step-down so the elapsed-time
	/// recompute agrees with the level rather than demoting further.
	func elapsedFloor(for level: IdleEscalation) -> TimeInterval {
		switch level {
		case .none: return 0
		case .impatient: return impatientAfter
		case .frustrated: return frustratedAfter
		}
	}

	/// Initial idle age (seconds) to backdate the idle clock to at launch, read
	/// from `CODOGOTCHI_IDLE_BACKDATE_MS` (milliseconds). Used by the `tcib`
	/// idle-bump demo to start the pet already escalated (e.g. frustrated) under
	/// otherwise production timing, so the click-hold de-escalation can be
	/// exercised without waiting out the real 30-minute window. Returns 0 (no
	/// backdating) when unset or invalid.
	static func backdateSeconds(
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> TimeInterval {
		positiveSeconds(environment["CODOGOTCHI_IDLE_BACKDATE_MS"]) ?? 0
	}

	private static func positiveSeconds(_ raw: String?) -> TimeInterval? {
		guard let raw, let ms = Double(raw), ms > 0 else { return nil }
		return ms / 1000.0
	}
}

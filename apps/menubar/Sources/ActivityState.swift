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
	case standby = "standby"
	case errored = "errored"
	case waitingForInput = "waiting_for_input"
	// Heuristic-tier hook states (Codex sheet rows 7–8)
	case implementing = "implementing"
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
	/// macOS bundle ID of the terminal that launched the hook process, populated
	/// by `detectTerminalBundleId` in hook-binary.ts. Used by the Focus button
	/// to bring the correct app to front for CLI-sourced hooks (claude_code, codex
	/// CLI) where the target is the terminal, not a fixed IDE app.
	let terminalBundleId: String?

	init(origin: String?, kind: String?, name: String?, terminalBundleId: String? = nil) {
		self.origin = origin
		self.kind = kind
		self.name = name
		self.terminalBundleId = terminalBundleId
	}
}

/// The `attention` object from the v3 schema. Present when `activity_state`
/// is `standby` or `errored`; absent otherwise. `expiresAt` drives the renderer's
/// TTL policy (P6.07): if the timestamp is in the past the renderer treats the
/// state as `idle` regardless of the written `activity_state`. `summary` and
/// `reasonKind` are the user-facing copy shown in the attention bubble (P6.08).
struct AttentionPayload: Equatable, Decodable {
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
}

import Foundation

/// All 15 states of the v2 animation-state-vocabulary closed enum.
///
/// Raw values match the hook's emitted strings exactly (snake_case; hyphenated
/// for `running-tests` and `calling_for_backup`). Any string not in this enum
/// — including future states the renderer has not yet painted — decodes as
/// `.idle` via `init(from:)`. This is the "unknown-state → idle" fallback
/// called out in P2.03's ticket spec and preserved through Phase 03.
///
/// Closed-enum decoding (no `unknown(String)` case) is deliberate: the
/// renderer must `switch` exhaustively without a `default:` and the contract
/// doc forbids string escape hatches.
enum ActivityState: String, Equatable, Codable, CaseIterable {
	// Floor states (Codex sheet — rendered since Phase 02)
	case idle = "idle"
	case implementing = "implementing"
	case runningTests = "running-tests"
	// New Codex-sheet states (wired in P3.03)
	case waiting = "waiting"
	case requestingInput = "requesting_input"
	case errored = "errored"
	// SoA-gate states (reliable tier — rendered via codogotchi sheet in P3.04)
	case hyped = "hyped"
	case focused = "focused"
	case nervous = "nervous"
	case celebrating = "celebrating"
	case ascended = "ascended"
	case callingForBackup = "calling_for_backup"
	case panicking = "panicking"
	// Heuristic-tier states (rendered via codogotchi sheet in P3.04)
	case reviewing = "reviewing"
	case pushing = "pushing"

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
}

/// Decoded form of `~/.codogotchi/state.json` v1.
///
/// Only the fields Phase 02 reads are declared. The schema permits richer
/// payloads (`hp`, `hp_overlay`); those are tolerated as unknown JSON keys
/// and ignored by `JSONDecoder` so the renderer cannot crash on shapes it
/// does not yet paint. `sourceEvent` is the one nested object the renderer
/// does consume — the transition log (P2.08) writes its `origin`/`kind`/
/// `name` triplet on every observed state change.
struct StateSnapshot: Equatable {
	let schemaVersion: Int
	let activityState: ActivityState
	let updatedAt: String
	let sourceEvent: SourceEvent?
}

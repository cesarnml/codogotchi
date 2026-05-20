import Foundation

/// Floor-state subset of the v1 animation-state-vocabulary closed enum that
/// Phase 02 renders.
///
/// The contract (`docs/contracts/animation-state-vocabulary.md`) defines more
/// states than Phase 02 paints. Any contract-listed state outside the four
/// floor cases — and any string the hook might emit that isn't in the
/// contract — decodes as `.idle` via `init(from:)`. This is the
/// "unknown-state → idle" fallback called out in P2.03's ticket spec.
///
/// Closed-enum decoding (no `unknown(String)` case) is deliberate: the
/// renderer must `switch` exhaustively without a `default:` and the contract
/// doc forbids string escape hatches.
enum ActivityState: String, Equatable, Codable {
	case idle = "idle"
	case implementing = "implementing"
	case runningTests = "running-tests"
	case celebrating = "celebrating"

	init(from decoder: Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = ActivityState(rawValue: raw) ?? .idle
	}
}

/// Decoded form of `~/.codogotchi/state.json` v1.
///
/// Only the fields Phase 02 reads are declared. The schema permits richer
/// payloads (`hp`, `hp_overlay`, `source_event`); those are tolerated as
/// unknown JSON keys and ignored by `JSONDecoder` so the renderer cannot
/// crash on shapes it does not yet paint.
struct StateSnapshot: Equatable {
	let schemaVersion: Int
	let activityState: ActivityState
	let updatedAt: String
}

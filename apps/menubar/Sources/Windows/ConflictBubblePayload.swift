import Foundation

/// P15.08 conflict-bubble content: the platform (`origin`) whose session cap
/// is blocking a newcomer. Distinct from `AttentionPayload`, which mirrors a
/// single session's `state.json` attention — this signal is pool-level
/// (`FloatingPetWindowPool.blockedOrigins`), not per-session state.
struct ConflictBubblePayload: Equatable {
	let origin: String
}

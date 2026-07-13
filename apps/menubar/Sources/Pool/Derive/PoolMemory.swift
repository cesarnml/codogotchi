import Foundation

/// Pure, `Equatable` fold state for `PoolDerive.derive` — the value-type home
/// for the cross-tick mutables `FloatingPetWindowPool` currently stores
/// directly on itself. See each field's doc comment for the exact
/// `FloatingPetWindowPool` stored property it replaces.
///
/// P18.01 wires only the fields Steps 1–5b and the eligibility-bounding block
/// need: the TTL/first-seen/last-updated clocks and the two elections. This
/// is a deliberate, ticket-scoped subset, not the full field-by-field
/// transcription the phase eventually needs — selection state (slot
/// occupancy, pruned origins, hidden keys, spawned modes, evicted-frame FIFO)
/// arrives with P18.02, and push-spec state (prompt timers, session
/// identities, conflict-bubble bookkeeping) arrives with P18.03. Each is
/// additive: no field defined here changes shape once a later ticket starts
/// writing it. See the P18.01 ticket Rationale for the explicit deferred list.
struct PoolMemory: Equatable {
	/// TTL clock per render key — advances only while the key is doing work
	/// (`activityState != .idle`), seeded on first sight so a freshly-observed
	/// idle pet still gets a full TTL grace window. Mirrors
	/// `FloatingPetWindowPool.lastSeenAt`.
	var lastSeenAt: [WindowKey: Date] = [:]

	/// First-seen clock per render key — set once, never refreshed. Mirrors
	/// `FloatingPetWindowPool.firstSeenAt`.
	var firstSeenAt: [WindowKey: Date] = [:]

	/// Most-recent snapshot `updated_at` per render key, used to elect
	/// `lastActiveRenderKey`. Mirrors `FloatingPetWindowPool.lastUpdatedAt`.
	var lastUpdatedAt: [WindowKey: Date] = [:]

	/// Render key currently holding last-active TTL immunity. Mirrors
	/// `FloatingPetWindowPool.lastActiveRenderKey`.
	var lastActiveRenderKey: WindowKey?

	/// Sticky RPG-HUD-bearer render key ("Show HUD on Most Recent Pet"):
	/// re-elects only when the current holder drops out of eligibility or is
	/// no longer in-flight. Mirrors `FloatingPetWindowPool.hudBearingRenderKey`.
	var hudBearingRenderKey: WindowKey?

	init() {}
}

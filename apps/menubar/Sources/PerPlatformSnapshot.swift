import Foundation

/// Aggregated snapshot produced by one poll tick over `state.d/`.
/// `perPlatform` maps each active origin to its most-recent `StateSnapshot`
/// (last-writer-wins within the mtime staleTTL window, grouped by origin),
/// with its `activityState` already merged against that origin's own SoA gate
/// (see `LivePollingDriver.resolvePerPlatform`).
/// `gateBadges` maps each origin to its persistent ticket/gate badge content,
/// independent of the gate animation TTL — absent when the origin has no
/// active SoA delivery context.
/// `rpgSnapshot` carries the shared RPG progression values from `rpg-state.json`.
/// `renderKeyIdentities` recovers the winning `(origin, session_id)` behind each
/// `perPlatform` render key. It is populated by `LivePollingDriver` from
/// `resolveRenderKeys`; downstream session labeling (P15.05+) reads it. Defaults
/// to empty so existing per-origin construction sites (pool tests) compile and
/// behave unchanged.
struct PerPlatformSnapshot {
    let perPlatform: [String: StateSnapshot]
    let gateBadges: [String: GateBadgeContent]
    let rpgSnapshot: RpgSnapshot
    let renderKeyIdentities: [String: RenderKeyIdentity]

    init(
        perPlatform: [String: StateSnapshot],
        gateBadges: [String: GateBadgeContent],
        rpgSnapshot: RpgSnapshot,
        renderKeyIdentities: [String: RenderKeyIdentity] = [:]
    ) {
        self.perPlatform = perPlatform
        self.gateBadges = gateBadges
        self.rpgSnapshot = rpgSnapshot
        self.renderKeyIdentities = renderKeyIdentities
    }
}

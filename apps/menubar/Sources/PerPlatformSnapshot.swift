import Foundation

/// Aggregated snapshot produced by one poll tick over `state.d/`.
/// `perPlatform` maps each active origin to its most-recent `StateSnapshot`
/// (last-writer-wins within the mtime staleTTL window, grouped by origin).
/// `rpgSnapshot` carries the shared RPG progression values from `rpg-state.json`.
struct PerPlatformSnapshot {
    let perPlatform: [String: StateSnapshot]
    let rpgSnapshot: RpgSnapshot
}

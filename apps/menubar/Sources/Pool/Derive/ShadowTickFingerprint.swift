import Foundation

/// Deterministic, replayable identity for one shadow-compare tick (P18.05
/// Review Focus: "are they actually replayable — a fingerprint sufficient to
/// reconstruct the table row?"). Built from exactly the inputs `derive`
/// consumed this tick — the current time plus every render key's activity
/// state and `updated_at` — sorted so the string never depends on
/// `Dictionary` iteration order. A human (or a regression test) reading a
/// `DivergenceRecord.tickFingerprint` from the shadow-divergence log can
/// reconstruct the exact snapshot shape that produced it.
///
/// Pure, no AppKit — lives under `Pool/Derive/` alongside the rest of the
/// pure fold.
enum ShadowTickFingerprint {
	static func make(snapshot: PerPlatformSnapshot, currentTime: Date) -> String {
		let entries = snapshot.perPlatform
			.map { key, state in "\(key.rawValue)=\(state.activityState.rawValue)@\(state.updatedAt)" }
			.sorted()
			.joined(separator: ",")
		let iso = ISO8601DateFormatter().string(from: currentTime)
		return "t=\(iso);entries=[\(entries)]"
	}
}

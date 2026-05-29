import Foundation

/// Decoded form of `~/.codogotchi/gate.json`. Written by the SoA delivery
/// orchestrator (son-of-anton Phase 17) to signal active gate states to the
/// renderer. The renderer reads this file on its poll loop and merges it with
/// `state.json` via `resolveActivityState`.
struct GateSnapshot {
	let gate: String
	let since: String
	let expiresAt: String
	let planKey: String?
	let ticketId: String?

	/// Returns true when `expiresAt` is parseable and strictly in the past.
	/// Uses the same two-pass ISO 8601 strategy as `StateJsonReader`.
	func isExpired(now: Date = Date()) -> Bool {
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: expiresAt) { return d < now }
		fmt.formatOptions = [.withInternetDateTime]
		if let d = fmt.date(from: expiresAt) { return d < now }
		return false
	}
}

/// Reads `gate.json` from disk and returns either a decoded `GateSnapshot`
/// or nil when the file is absent or malformed.
///
/// Missing file and malformed JSON are both normal "no gate" conditions —
/// neither is an error that should interrupt the render loop. The renderer
/// treats nil as "no active gate; show hook animation."
enum GateJsonReader {
	/// Reads gate.json from the given path. Returns nil for missing or malformed.
	static func read(at path: String) -> GateSnapshot? {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return nil }
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		guard let gate = root["gate"] as? String,
			let since = root["since"] as? String,
			let expiresAt = root["expires_at"] as? String
		else { return nil }
		let planKey = root["plan_key"] as? String
		let ticketId = root["ticket_id"] as? String
		return GateSnapshot(
			gate: gate,
			since: since,
			expiresAt: expiresAt,
			planKey: planKey,
			ticketId: ticketId
		)
	}
}

/// Merge resolver: returns the `ActivityState` to render given an optional
/// gate snapshot and the hook's current `state.json` activity state.
///
/// Precedence (highest to lowest):
/// 1. Unexpired gate with a sprite row in `CodogotchiPet.rowMap` → gate state.
/// 2. Gate expired, gate artless/unknown, or no gate → hook state.
///
/// The "has a sprite row" check is the single gate-renderability predicate —
/// it covers both unknown-skew gates (unknown ActivityState rawValue) and
/// artless gates (known v4 state but not yet in the row map).
func resolveActivityState(
	gate: GateSnapshot?,
	hookState: ActivityState,
	now: Date = Date()
) -> ActivityState {
	guard let gate = gate,
		!gate.isExpired(now: now),
		let gateState = ActivityState(rawValue: gate.gate),
		CodogotchiPet.rowMap[gateState] != nil
	else {
		return hookState
	}
	return gateState
}

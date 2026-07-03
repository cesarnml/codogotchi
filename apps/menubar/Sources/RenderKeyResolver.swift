import Foundation

/// The `(origin, session_id)` identity of the slice that won a given render key.
///
/// A render key can be a plain `origin`, an `origin:session_id`, or `"combined"`
/// (which collapses several origins). The plain-origin and combined keys lose
/// the session component on their own, so this identity is carried alongside the
/// render map to recover the winning `(origin, session_id)` for downstream
/// labeling (session badges, tooltips) in later Phase 15 tickets.
struct RenderKeyIdentity: Equatable {
	let origin: String
	let sessionId: String
}

/// Output of `resolveRenderKeys`: the render-keyed winner snapshots plus the
/// parallel identity lookup keyed identically.
struct RenderKeyResolution: Equatable {
	let states: [String: StateSnapshot]
	let identities: [String: RenderKeyIdentity]
}

/// Pure reducer from the per-session state map (keyed `origin:session_id`) to the
/// render set for a given customization snapshot. Takes data in, returns data
/// out — free of any pool/window concerns so the pool (P15.04) and tests can
/// exercise it directly.
///
/// Render-key rules:
/// - **Combined** origins fold to the single `"combined"` key regardless of the
///   session-pets setting.
/// - **Own / Minimalist** (and any other non-combined mode) with session-pets
///   **off** fold each origin's sessions to a single plain-`origin` key.
/// - **Own / Minimalist** with session-pets **on** keep each `origin:session_id`
///   key, subject to the grandfather/activity gate: only the origin's
///   grandfathered session (recorded at the most recent off->on toggle) and
///   sessions with activity strictly after that toggle's timestamp are
///   admitted — see the gate's inline comment below.
///
/// Within every render key the winner is the session with the newest
/// `updated_at` (strict `>`), matching `readPerPlatformDirectoryImpl`'s
/// last-writer-wins tie-break. Sessions sharing an identical `updated_at`
/// resolve deterministically to the lexicographically smallest per-session
/// key (sorted iteration + strict `>` keeps the first seen). With an
/// all-default customization (every origin `.own`, session-pets off) this
/// reproduces today's per-origin map exactly.
func resolveRenderKeys(
	perSession: [String: StateSnapshot],
	customization: CustomizationSnapshot
) -> RenderKeyResolution {
	var states: [String: StateSnapshot] = [:]
	var identities: [String: RenderKeyIdentity] = [:]

	func consider(renderKey: String, origin: String, sessionId: String, snapshot: StateSnapshot) {
		let candidate = StateJsonReader.parseISO8601Date(snapshot.updatedAt) ?? .distantPast
		if let existing = states[renderKey] {
			let existingDate = StateJsonReader.parseISO8601Date(existing.updatedAt) ?? .distantPast
			guard candidate > existingDate else { return }
		}
		states[renderKey] = snapshot
		identities[renderKey] = RenderKeyIdentity(origin: origin, sessionId: sessionId)
	}

	// Sorted iteration makes the equal-`updated_at` tie deterministic — plain
	// Dictionary order is unspecified and would pick an arbitrary winner.
	for key in perSession.keys.sorted() {
		guard let snapshot = perSession[key] else { continue }
		let (origin, sessionId) = splitSessionKey(key)
		let mode = customization.platformModes[origin] ?? .own
		let renderKey: String
		if mode == .combined {
			renderKey = "combined"
		} else {
			let sessionPetsOn = customization.sessionPetsEnabled[origin] ?? false
			if sessionPetsOn {
				// Grandfather/activity gate (P15-QC): on this origin's most recent
				// off->on toggle, `CustomizationTabViewModel` grandfathers in
				// whichever session was the collapsed single pet at that instant —
				// that session is exempt below and renders unconditionally. Every
				// OTHER sibling session must show activity strictly after the
				// activation timestamp; a sibling that predates the toggle (or has
				// gone untouched since) is excluded entirely, not just held back,
				// so it never appears until it does something new. An origin with
				// no recorded activation (never been through this toggle — e.g.
				// data from before this gate existed) admits every session
				// unconditionally, matching pre-gate behavior exactly.
				if let activatedAtRaw = customization.sessionPetsActivatedAt[origin],
					let activatedAt = StateJsonReader.parseISO8601Date(activatedAtRaw)
				{
					let isGrandfather = customization.sessionPetsGrandfatheredSessionId[origin] == sessionId
					if !isGrandfather {
						let updatedAt = StateJsonReader.parseISO8601Date(snapshot.updatedAt) ?? .distantPast
						guard updatedAt > activatedAt else { continue }
					}
				}
				renderKey = key
			} else {
				renderKey = origin
			}
		}
		consider(renderKey: renderKey, origin: origin, sessionId: sessionId, snapshot: snapshot)
	}

	return RenderKeyResolution(states: states, identities: identities)
}

/// Splits an `origin:session_id` per-session key back into its components,
/// splitting on the first colon (origin never contains one). A key with no
/// colon degrades to `(key, "default")` for defensiveness — the reader always
/// emits a colon-bearing key.
private func splitSessionKey(_ key: String) -> (origin: String, sessionId: String) {
	guard let colon = key.firstIndex(of: ":") else { return (key, "default") }
	let origin = String(key[key.startIndex..<colon])
	let session = String(key[key.index(after: colon)...])
	return (origin, session)
}

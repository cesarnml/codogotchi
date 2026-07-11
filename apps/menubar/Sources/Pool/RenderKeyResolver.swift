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
	let states: [WindowKey: StateSnapshot]
	let identities: [WindowKey: RenderKeyIdentity]
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
	var states: [WindowKey: StateSnapshot] = [:]
	var identities: [WindowKey: RenderKeyIdentity] = [:]

	func consider(renderKey: WindowKey, origin: String, sessionId: String, snapshot: StateSnapshot) {
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
		// `perSession` is keyed by the `state.d/` per-session identity
		// (built by `StateJsonReader.readPerSessionDirectory` from slice
		// filenames — the sanctioned slice-filename boundary), so parsing it
		// through `WindowKey`'s own rawValue path is the single parse site
		// rather than a bespoke colon split. A key with no colon degrades to
		// `(key, "default")` for defensiveness, mirroring the pre-WindowKey
		// contract — the reader always emits a colon-bearing key in
		// practice, but nothing here depends on that.
		let (origin, sessionId): (String, String)
		switch WindowKey(rawValue: key) {
		case .session(let o, let id): (origin, sessionId) = (o, id)
		case .origin(let o): (origin, sessionId) = (o, "default")
		case .combined: (origin, sessionId) = (key, "default")
			case .none: continue
		}
		let mode = customization.platformModes[origin] ?? .own
		let renderKey: WindowKey
		if mode == .combined {
			renderKey = .combined
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
				renderKey = .session(origin: origin, id: sessionId)
			} else {
				renderKey = .origin(origin)
			}
		}
		consider(renderKey: renderKey, origin: origin, sessionId: sessionId, snapshot: snapshot)
	}

	return RenderKeyResolution(states: states, identities: identities)
}

/// Joins `(origin, sessionId)` into the `"<origin>:<session_id>"` key shape
/// consumed throughout `state.d/`. Delegates to `WindowKey.session(origin:id:)
/// .rawValue` — the single source of truth for that format — for callers
/// that need the raw `String` form (e.g. a lookup key into a `String`-keyed
/// sidecar map, not a `WindowKey` itself).
func makeSessionKey(origin: String, sessionId: String) -> String {
	WindowKey.session(origin: origin, id: sessionId).rawValue
}

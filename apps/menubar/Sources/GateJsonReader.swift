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

	/// Returns true when `expiresAt` is in the past or unparseable.
	///
	/// An unparseable `expiresAt` is treated as expired (not as never-expiring)
	/// so a corrupt gate.json never silently locks the renderer into a gate state.
	/// Uses the same two-pass ISO 8601 strategy as `StateJsonReader`.
	func isExpired(now: Date = Date()) -> Bool {
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: expiresAt) { return d < now }
		fmt.formatOptions = [.withInternetDateTime]
		if let d = fmt.date(from: expiresAt) { return d < now }
		// Unparseable date → treat as expired; do not activate the gate.
		return true
	}
}

/// Persistent floating-pet badge content derived from the raw gate sidecar.
///
/// This is intentionally independent of `expires_at`: gate animation TTL only
/// controls render precedence, not whether the operator can still see which
/// ticket/gate pair most recently fired.
struct GateBadgeContent: Equatable {
	let ticketId: String
	let gate: String
}

/// Durable SoA delivery context. Unlike `gate.json`, this file owns the
/// persistent ticket/gate badges and is explicitly leased so stale context
/// eventually clears even if a delivery run exits without a final gate.
struct DeliveryContextSnapshot {
	let owner: String
	let status: String
	let repoRoot: String?
	let planKey: String?
	let ticketId: String?
	let lastGate: String?
	let updatedAt: String?
	let leaseExpiresAt: String?

	func isExpired(now: Date = Date()) -> Bool {
		guard let leaseExpiresAt else { return true }
		return parseISO8601Date(leaseExpiresAt).map { $0 < now } ?? true
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

enum DeliveryContextReader {
	static func read(at path: String) -> DeliveryContextSnapshot? {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return nil }
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		guard let owner = root["owner"] as? String,
			let status = root["status"] as? String
		else { return nil }
		return DeliveryContextSnapshot(
			owner: owner,
			status: status,
			repoRoot: root["repo_root"] as? String,
			planKey: root["plan_key"] as? String,
			ticketId: root["ticket_id"] as? String,
			lastGate: root["last_gate"] as? String,
			updatedAt: root["updated_at"] as? String,
			leaseExpiresAt: root["lease_expires_at"] as? String
		)
	}
}

/// Reads gate/context slices out of `state.d/`, keyed either by origin or by
/// the full `<origin>:<session_id>` identity encoded in
/// `<origin>:<session_id>.gate.json` / `.context.json` filenames
/// (son-of-anton Phase 17's direct-gate-write). Mirrors
/// `StateJsonReader.readPerPlatformDirectory` / `readPerSessionDirectory`'s
/// directory-scan shapes so the per-platform window pool can badge each
/// origin's — or, with session-pets on, each session's — own gate
/// independently instead of the single most-recently-written file across
/// every platform (or every sibling session on one platform).
enum PerPlatformGateReader {
	struct Entry {
		let gate: GateSnapshot?
		let context: DeliveryContextSnapshot?
	}

	/// Origin-aggregate view: one `Entry` per origin, the newest gate/context
	/// slice across every session on that origin. This is what session-pets-off
	/// and `"combined"` render keys use — both have already folded multiple
	/// sessions into one window, so there is no single session identity left to
	/// key on and "newest across the origin" is the correct badge.
	///
	/// `listing`, when supplied, is a `state.d/` enumeration already produced once
	/// for this poll tick — the reader consumes it instead of issuing its own
	/// `contentsOfDirectory`. When omitted (direct callers, tests) it self-scans
	/// exactly as before. Only the enumeration is shared; each gate/context file
	/// is still opened and decoded here.
	static func read(at dirPath: String, listing: StateDirectoryListing? = nil) -> [String: Entry] {
		let scan = scanEntries(at: dirPath, listing: listing)
		return merge(gates: scan.originGates, contexts: scan.originContexts)
	}

	/// Per-session view: one `Entry` per `"<origin>:<session_id>"` key, matching
	/// the render-key shape `resolveRenderKeys` emits when session-pets is on for
	/// an origin. Each session-pet panel badges from exactly its own gate/context
	/// sidecar instead of whichever sibling session on the same origin happened
	/// to write most recently — the collapse `read()`'s origin-only keying has
	/// when several sessions on one origin are mid-delivery concurrently.
	static func readPerSession(at dirPath: String, listing: StateDirectoryListing? = nil) -> [String: Entry] {
		let scan = scanEntries(at: dirPath, listing: listing)
		return merge(gates: scan.sessionGates, contexts: scan.sessionContexts)
	}

	private struct Scan {
		let originGates: [String: (mtime: Date, snapshot: GateSnapshot)]
		let originContexts: [String: (mtime: Date, snapshot: DeliveryContextSnapshot)]
		let sessionGates: [String: (mtime: Date, snapshot: GateSnapshot)]
		let sessionContexts: [String: (mtime: Date, snapshot: DeliveryContextSnapshot)]
	}

	private static func scanEntries(at dirPath: String, listing: StateDirectoryListing?) -> Scan {
		let empty = Scan(originGates: [:], originContexts: [:], sessionGates: [:], sessionContexts: [:])
		let entries: [StateDirectoryListing.Entry]
		if let listing {
			entries = listing.entries
		} else {
			guard let scanned = StateDirectoryListing.scan(at: dirPath) else { return empty }
			entries = scanned.entries
		}

		var originGates: [String: (mtime: Date, snapshot: GateSnapshot)] = [:]
		var originContexts: [String: (mtime: Date, snapshot: DeliveryContextSnapshot)] = [:]
		var sessionGates: [String: (mtime: Date, snapshot: GateSnapshot)] = [:]
		var sessionContexts: [String: (mtime: Date, snapshot: DeliveryContextSnapshot)] = [:]

		for entry in entries {
			let name = entry.name
			guard !name.contains(".tmp-") else { continue }
			let filePath = (dirPath as NSString).appendingPathComponent(name)
			guard let mtime = entry.mtime else { continue }

			if name.hasSuffix(".gate.json"),
				let (origin, sessionId) = originAndSession(of: name, suffix: ".gate.json"),
				let snapshot = GateJsonReader.read(at: filePath)
			{
				if originGates[origin] == nil || mtime > originGates[origin]!.mtime {
					originGates[origin] = (mtime, snapshot)
				}
				let sessionKey = "\(origin):\(sessionId)"
				if sessionGates[sessionKey] == nil || mtime > sessionGates[sessionKey]!.mtime {
					sessionGates[sessionKey] = (mtime, snapshot)
				}
			} else if name.hasSuffix(".context.json"),
				let (origin, sessionId) = originAndSession(of: name, suffix: ".context.json"),
				let snapshot = DeliveryContextReader.read(at: filePath)
			{
				if originContexts[origin] == nil || mtime > originContexts[origin]!.mtime {
					originContexts[origin] = (mtime, snapshot)
				}
				let sessionKey = "\(origin):\(sessionId)"
				if sessionContexts[sessionKey] == nil || mtime > sessionContexts[sessionKey]!.mtime {
					sessionContexts[sessionKey] = (mtime, snapshot)
				}
			}
		}

		return Scan(
			originGates: originGates, originContexts: originContexts,
			sessionGates: sessionGates, sessionContexts: sessionContexts)
	}

	private static func merge(
		gates: [String: (mtime: Date, snapshot: GateSnapshot)],
		contexts: [String: (mtime: Date, snapshot: DeliveryContextSnapshot)]
	) -> [String: Entry] {
		var result: [String: Entry] = [:]
		for key in Set(gates.keys).union(contexts.keys) {
			result[key] = Entry(gate: gates[key]?.snapshot, context: contexts[key]?.snapshot)
		}
		return result
	}

	/// Extracts `(origin, session_id)` from a `<origin>:<session_id>.<suffix>`
	/// filename. Returns nil when the name has no `:` separator — a legacy flat
	/// file or a malformed slice — so the caller skips it rather than mis-keying
	/// on the whole filename.
	private static func originAndSession(
		of name: String, suffix: String
	) -> (origin: String, sessionId: String)? {
		let base = String(name.dropLast(suffix.count))
		guard let colonIndex = base.firstIndex(of: ":") else { return nil }
		let origin = String(base[base.startIndex..<colonIndex])
			.trimmingCharacters(in: .whitespaces)
		let session = String(base[base.index(after: colonIndex)...])
			.trimmingCharacters(in: .whitespaces)
		guard !origin.isEmpty, !session.isEmpty else { return nil }
		return (origin, session)
	}
}

/// Merge resolver: returns the `ActivityState` to render given an optional
/// gate snapshot and the hook's current `state.json` activity state.
///
/// Precedence (highest to lowest):
/// 1. Unexpired gate with a SoA sprite row AND a loaded SoA sheet → gate state.
/// 2. Gate expired, gate artless/unknown, SoA sheet absent, or no gate → hook state.
///
/// The SoA-sheet presence check prevents gate elevation when the sheet is absent
/// at runtime — without it a gate state would silently resolve to idle instead of
/// falling through to the hook animation (Phase 07 contract preserved).
func resolveActivityState(
	gate: GateSnapshot?,
	hookState: ActivityState,
	codogotchiPet: CodogotchiPet? = nil,
	now: Date = Date()
) -> ActivityState {
	guard let gate = gate,
		!gate.isExpired(now: now),
		let gateState = ActivityState(rawValue: gate.gate),
		CodogotchiPet.soaRowMap[gateState] != nil,
		codogotchiPet == nil || codogotchiPet?.soaSheet != nil
	else {
		return hookState
	}
	return gateState
}

/// Revive override: while `revive_until` is parseable and strictly in the
/// future, the renderer plays the revive celebration on top of whatever state
/// the gate/hook resolver produced.
///
/// The celebration uses the dedicated Lite-Basic `revive` row when that sheet
/// is loaded; otherwise the base state is preserved so the renderer does not
/// point at a missing row.
func resolveReviveState(
	base: ActivityState,
	reviveUntil: String?,
	codogotchiPet: CodogotchiPet? = nil,
	now: Date = Date()
) -> ActivityState {
	guard let reviveUntil,
		let expiry = parseGateISO8601Date(reviveUntil),
		expiry > now,
		codogotchiPet == nil || codogotchiPet?.liteBasicSheet != nil
	else {
		return base
	}
	return .revive
}

/// Two-pass ISO 8601 parse (fractional-seconds first, whole-seconds fallback)
/// matching the writer's output and the rest of the renderer's date handling.
private func parseGateISO8601Date(_ string: String) -> Date? {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let date = formatter.date(from: string) { return date }
	formatter.formatOptions = [.withInternetDateTime]
	return formatter.date(from: string)
}

func resolveGateBadgeContent(
	deliveryContext: DeliveryContextSnapshot?,
	sourceEvent: SourceEvent?,
	now: Date = Date()
) -> GateBadgeContent? {
	guard let deliveryContext,
		deliveryContext.owner == "soa",
		deliveryContext.status == "active",
		!deliveryContext.isExpired(now: now),
		let ticketId = deliveryContext.ticketId?.trimmingCharacters(in: .whitespacesAndNewlines),
		!ticketId.isEmpty,
		let gate = deliveryContext.lastGate?.trimmingCharacters(in: .whitespacesAndNewlines),
		!gate.isEmpty
	else {
		return nil
	}

	if let activeRepo = sourceEvent?.repoRoot,
		let contextRepo = deliveryContext.repoRoot,
		canonicalRepoRoot(activeRepo) != canonicalRepoRoot(contextRepo)
	{
		return nil
	}

	return GateBadgeContent(ticketId: ticketId, gate: gate)
}

/// Normalizes a checkout path to its main-worktree root using only the
/// filesystem — no `git` subprocess.
///
/// SoA delivery always runs in a *linked worktree* (e.g. `…/codogotchi_p10_03`)
/// while the operator's active editor — and therefore the hook that writes
/// `state.json`'s `source_event.repo_root` — typically reports the *primary*
/// checkout (e.g. `…/codogotchi`). Comparing those raw paths in
/// `resolveGateBadgeContent` made the repo-guard treat every worktree as a
/// foreign project and silently suppress the ticket/gate badge. Normalizing both
/// sides to the shared main root makes the guard mean what it says: "is this the
/// same repository?" rather than "is this the same on-disk directory?".
///
/// - A primary checkout has a `.git` *directory*; the path is returned unchanged.
/// - A linked worktree has a `.git` *file* containing
///   `gitdir: <main>/.git/worktrees/<name>`; the main root is the prefix before
///   `/.git/worktrees/`.
/// - Any unrecognized shape (missing `.git`, pruned worktree, unexpected
///   contents) returns the input unchanged so the guard degrades to its prior
///   exact-match behavior rather than guessing.
func canonicalRepoRoot(_ path: String) -> String {
	let normalized =
		path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
	let dotGit = normalized + "/.git"
	var isDirectory: ObjCBool = false
	guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory)
	else {
		return normalized
	}
	if isDirectory.boolValue { return normalized }
	guard let contents = try? String(contentsOfFile: dotGit, encoding: .utf8) else {
		return normalized
	}
	let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
	let prefix = "gitdir:"
	guard trimmed.hasPrefix(prefix) else { return normalized }
	let gitdir = String(trimmed.dropFirst(prefix.count))
		.trimmingCharacters(in: .whitespaces)
	guard let range = gitdir.range(of: "/.git/worktrees/") else { return normalized }
	return String(gitdir[gitdir.startIndex..<range.lowerBound])
}

private func parseISO8601Date(_ string: String) -> Date? {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let date = formatter.date(from: string) { return date }
	formatter.formatOptions = [.withInternetDateTime]
	return formatter.date(from: string)
}

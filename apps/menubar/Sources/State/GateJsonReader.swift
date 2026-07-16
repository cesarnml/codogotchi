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

/// Reads gate/context slices out of `state.d/`, keyed by the full
/// `<origin>:<session_id>` identity encoded in `<origin>:<session_id>.gate.json`
/// / `.context.json` filenames (son-of-anton Phase 17's direct-gate-write).
/// Mirrors `StateJsonReader.readPerSessionDirectory`'s directory-scan shape so
/// the per-platform window pool can badge each session's own gate
/// independently instead of the single most-recently-written file across
/// every sibling session on one platform.
///
/// There is no origin-aggregate ("newest gate anywhere on this origin") view:
/// `resolveRenderKeys` always resolves a `RenderKeyIdentity(origin, sessionId)`
/// for every render key — plain-origin and `"combined"` keys included, not
/// just session-pet-on keys — so `LivePollingDriver.resolveRenderedPlatforms`
/// can key directly off that winning identity's own session slice regardless
/// of how the key is displayed. An origin-wide "newest gate write" fallback
/// used to exist here and fed a render key with a *different* session's gate
/// than the one whose state actually won that key — see
/// `resolveRenderedPlatforms`'s doc comment.
enum PerPlatformGateReader {
	struct Entry {
		let gate: GateSnapshot?
		let context: DeliveryContextSnapshot?
	}

	/// One `Entry` per session-keyed `WindowKey` (`.session(origin:id:)`),
	/// matching the identity shape `resolveRenderKeys` emits for every render
	/// key.
	///
	/// `listing`, when supplied, is a `state.d/` enumeration already produced
	/// once for this poll tick — the reader consumes it instead of issuing its
	/// own `contentsOfDirectory`. When omitted (direct callers, tests) it
	/// self-scans exactly as before. Only the enumeration is shared; each
	/// gate/context file is still opened and decoded here.
	static func read(
		at dirPath: String, listing: StateDirectoryListing? = nil
	) -> [WindowKey: Entry] {
		let (sessionGates, sessionContexts) = scanEntries(at: dirPath, listing: listing)
		return merge(gates: sessionGates, contexts: sessionContexts)
	}

	private static func scanEntries(at dirPath: String, listing: StateDirectoryListing?) -> (
		gates: [WindowKey: (mtime: Date, snapshot: GateSnapshot)],
		contexts: [WindowKey: (mtime: Date, snapshot: DeliveryContextSnapshot)]
	) {
		let entries: [StateDirectoryListing.Entry]
		if let listing {
			entries = listing.entries
		} else {
			guard let scanned = StateDirectoryListing.scan(at: dirPath) else { return ([:], [:]) }
			entries = scanned.entries
		}

		var sessionGates: [WindowKey: (mtime: Date, snapshot: GateSnapshot)] = [:]
		var sessionContexts: [WindowKey: (mtime: Date, snapshot: DeliveryContextSnapshot)] = [:]

		for entry in entries {
			let name = entry.name
			guard !name.contains(".tmp-") else { continue }
			let filePath = (dirPath as NSString).appendingPathComponent(name)
			guard let mtime = entry.mtime else { continue }

			if name.hasSuffix(".gate.json"),
				let sessionKey = sessionWindowKey(of: name, suffix: ".gate.json"),
				let snapshot = GateJsonReader.read(at: filePath)
			{
				if sessionGates[sessionKey] == nil || mtime > sessionGates[sessionKey]!.mtime {
					sessionGates[sessionKey] = (mtime, snapshot)
				}
			} else if name.hasSuffix(".context.json"),
				let sessionKey = sessionWindowKey(of: name, suffix: ".context.json"),
				let snapshot = DeliveryContextReader.read(at: filePath)
			{
				if sessionContexts[sessionKey] == nil || mtime > sessionContexts[sessionKey]!.mtime {
					sessionContexts[sessionKey] = (mtime, snapshot)
				}
			}
		}

		return (sessionGates, sessionContexts)
	}

	private static func merge(
		gates: [WindowKey: (mtime: Date, snapshot: GateSnapshot)],
		contexts: [WindowKey: (mtime: Date, snapshot: DeliveryContextSnapshot)]
	) -> [WindowKey: Entry] {
		var result: [WindowKey: Entry] = [:]
		for key in Set(gates.keys).union(contexts.keys) {
			result[key] = Entry(gate: gates[key]?.snapshot, context: contexts[key]?.snapshot)
		}
		return result
	}

	/// Extracts the session-keyed `WindowKey` (`.session(origin:id:)`) from a
	/// `<origin>:<session_id>.<suffix>` filename. Returns nil when the name
	/// has no `:` separator, or an empty origin/session-id half — a legacy
	/// flat file or a malformed slice — so the caller skips it rather than
	/// mis-keying on the whole filename.
	///
	/// This is the sanctioned slice-filename boundary (P16.04): the colon
	/// split here is unavoidable — a filename is not itself a bare
	/// `WindowKey` rawValue, it has a `.gate.json`/`.context.json` suffix
	/// appended and (defensively) surrounding whitespace to strip — but the
	/// parsed halves are handed straight to `WindowKey.session(origin:id:)`
	/// rather than reassembled into a raw string for a second parse pass.
	private static func sessionWindowKey(
		of name: String, suffix: String
	) -> WindowKey? {
		let base = String(name.dropLast(suffix.count))
		guard let colonIndex = base.firstIndex(of: ":") else { return nil }
		let origin = String(base[base.startIndex..<colonIndex])
			.trimmingCharacters(in: .whitespaces)
		let session = String(base[base.index(after: colonIndex)...])
			.trimmingCharacters(in: .whitespaces)
		guard !origin.isEmpty, !session.isEmpty else { return nil }
		return .session(origin: origin, id: session)
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
/// `path` is often a subdirectory of the checkout, not its root — the hook
/// that writes `source_event.repo_root` reports whatever `cwd`/`workspace_roots`
/// the calling tool happens to report, which is sometimes several levels deep.
/// Walking up parent directories looking for the first `.git` mirrors the TS
/// `canonicalRepoRoot` in `hook-binary.ts` so both sides land on the same root
/// even when the raw path isn't the top of the repo.
///
/// - A primary checkout has a `.git` *directory* at some ancestor; that
///   ancestor is returned.
/// - A linked worktree has a `.git` *file* containing
///   `gitdir: <main>/.git/worktrees/<name>`; the main root is the prefix before
///   `/.git/worktrees/`.
/// - If no ancestor (up to the filesystem root) has a `.git`, the input is
///   returned unchanged so the guard degrades to its prior exact-match
///   behavior rather than guessing.
func canonicalRepoRoot(_ path: String) -> String {
	let original =
		path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
	var dir = original
	while true {
		if let found = resolveDotGit(dir) { return found }
		let parent = (dir as NSString).deletingLastPathComponent
		if parent.isEmpty || parent == dir { return original }
		dir = parent
	}
}

/// Resolves the `.git` entry at exactly `dir`, if any. Returns the repo root
/// for that entry, or `nil` if `dir` has no `.git` (caller should check the
/// parent directory next).
private func resolveDotGit(_ dir: String) -> String? {
	let dotGit = dir + "/.git"
	var isDirectory: ObjCBool = false
	guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory)
	else {
		return nil
	}
	if isDirectory.boolValue { return dir }
	guard let contents = try? String(contentsOfFile: dotGit, encoding: .utf8) else {
		return dir
	}
	let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
	let prefix = "gitdir:"
	guard trimmed.hasPrefix(prefix) else { return dir }
	let gitdir = String(trimmed.dropFirst(prefix.count))
		.trimmingCharacters(in: .whitespaces)
	guard let range = gitdir.range(of: "/.git/worktrees/") else { return dir }
	return String(gitdir[gitdir.startIndex..<range.lowerBound])
}

private func parseISO8601Date(_ string: String) -> Date? {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let date = formatter.date(from: string) { return date }
	formatter.formatOptions = [.withInternetDateTime]
	return formatter.date(from: string)
}

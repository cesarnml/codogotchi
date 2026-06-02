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

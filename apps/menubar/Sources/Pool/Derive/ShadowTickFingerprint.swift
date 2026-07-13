import CryptoKit
import Foundation

/// Deterministic, replayable identity for one shadow-compare tick (P18.05
/// Review Focus: "are they actually replayable — a fingerprint sufficient to
/// reconstruct the table row?"). Built from the ENTIRE `PoolTickInput` the
/// old pipeline's `runShadowTick` epilogue handed to `PoolDerive.derive` this
/// tick — snapshot (per-key activity state, `updatedAt`, source event,
/// attention, gate badges, RPG progression, render-key identities),
/// customization, assignments, the resolved HUD mode, the idle-escalation
/// environment overrides, and the three read/effect-seam maps — never just a
/// hand-picked subset. Two materially different tick inputs must never
/// collide on the same fingerprint, or a logged divergence stops being
/// replayable.
///
/// Every `Dictionary`-typed field is sorted by key before being folded into
/// the canonical string, so the fingerprint never depends on Swift's
/// per-process `Dictionary`/`Set` hash-seed iteration order — the same tick
/// input always produces the same fingerprint, in this process or a replay
/// in a fresh one.
///
/// User-authored or platform-derived free text (`sessionLabels`,
/// `knownSessionTitles`, `sessionPromptSummaries`, a state's `toolCommand`,
/// `AttentionPayload.summary`) is folded in as a length tag rather than
/// embedded verbatim — mirroring `PoolShadowComparator`'s redaction of the
/// same class of field. This still changes the digest whenever that text
/// changes (so two genuinely different ticks still diverge), without
/// persisting raw content into the replay log.
///
/// Pure, no AppKit — lives under `Pool/Derive/` alongside the rest of the
/// pure fold.
enum ShadowTickFingerprint {
	static func make(input: PoolTickInput) -> String {
		let iso = ISO8601DateFormatter().string(from: input.currentTime)
		let canonical = canonicalString(for: input)
		let digest = SHA256.hash(data: Data(canonical.utf8))
			.map { String(format: "%02x", $0) }.joined()
		return "t=\(iso);digest=\(digest)"
	}

	// MARK: - Canonical, sorted, redacted representation of `PoolTickInput`

	private static func canonicalString(for input: PoolTickInput) -> String {
		[
			"snapshot=[\(describeSnapshot(input.snapshot))]",
			"customization=[\(describeCustomization(input.customization))]",
			"assignments=[\(describeAssignments(input.assignments))]",
			"currentTime=\(input.currentTime.timeIntervalSince1970)",
			"idleEscalationEnvironment=[\(sortedStringDict(input.idleEscalationEnvironment))]",
			"sessionLabels=[\(sortedRedactedDict(input.sessionLabels))]",
			"knownSessionTitles=[\(sortedRedactedDict(input.knownSessionTitles))]",
			"sessionPromptSummaries=[\(sortedRedactedDict(input.sessionPromptSummaries))]",
			"hudMode=\(input.hudMode)",
		].joined(separator: ";")
	}

	private static func describeSnapshot(_ snapshot: PerPlatformSnapshot) -> String {
		let perPlatform = snapshot.perPlatform
			.map { key, state in "\(key.rawValue)=(\(describeState(state)))" }
			.sorted()
			.joined(separator: ",")
		let gateBadges = snapshot.gateBadges
			.map { key, badge in "\(key.rawValue)=\(badge.ticketId)/\(badge.gate)" }
			.sorted()
			.joined(separator: ",")
		let renderKeyIdentities = snapshot.renderKeyIdentities
			.map { key, identity in "\(key.rawValue)=\(identity.origin):\(identity.sessionId)" }
			.sorted()
			.joined(separator: ",")
		let rpg = snapshot.rpgSnapshot
		let rpgString =
			"level=\(rpg.level),levelFraction=\(rpg.levelFraction),halfHearts=\(rpg.halfHearts),"
			+ "activeMinutes=\(rpg.activeMinutes),lastActivityAt=\(rpg.lastActivityAt ?? "nil"),"
			+ "reviveUntil=\(rpg.reviveUntil ?? "nil")"
		return
			"perPlatform=[\(perPlatform)];gateBadges=[\(gateBadges)];rpgSnapshot=(\(rpgString));"
			+ "renderKeyIdentities=[\(renderKeyIdentities)]"
	}

	private static func describeState(_ state: StateSnapshot) -> String {
		let sourceEvent = describeSourceEvent(state.sourceEvent)
		let attention = describeAttention(state.attention)
		let toolCommand = state.toolCommand.map { "<redacted:\($0.count)ch>" } ?? "nil"
		return
			"schemaVersion=\(state.schemaVersion),activityState=\(state.activityState.rawValue),"
			+ "updatedAt=\(state.updatedAt),sourceEvent=(\(sourceEvent)),attention=(\(attention)),"
			+ "toolCommand=\(toolCommand),level=\(state.level),levelFraction=\(state.levelFraction),"
			+ "halfHearts=\(state.halfHearts),activeMinutes=\(state.activeMinutes),"
			+ "lastActivityAt=\(state.lastActivityAt ?? "nil"),reviveUntil=\(state.reviveUntil ?? "nil")"
	}

	private static func describeSourceEvent(_ sourceEvent: SourceEvent?) -> String {
		guard let sourceEvent else { return "nil" }
		return
			"origin=\(sourceEvent.origin ?? "nil"),kind=\(sourceEvent.kind ?? "nil"),"
			+ "name=\(sourceEvent.name ?? "nil"),repoRoot=\(sourceEvent.repoRoot ?? "nil"),"
			+ "terminalBundleId=\(sourceEvent.terminalBundleId ?? "nil")"
	}

	/// Mirrors `PoolShadowComparator.describeAttention`'s redaction of
	/// `summary` (user-facing free text) — kept as a separate, independently
	/// verified implementation here since a divergence's fingerprint and its
	/// record are logged together but computed from different call sites.
	private static func describeAttention(_ payload: AttentionPayload?) -> String {
		guard let payload else { return "nil" }
		let summary = payload.summary.map { "<redacted:\($0.count)ch>" } ?? "nil"
		return
			"createdAt=\(payload.createdAt ?? "nil"),expiresAt=\(payload.expiresAt ?? "nil"),"
			+ "summary=\(summary),reasonKind=\(payload.reasonKind ?? "nil")"
	}

	private static func describeCustomization(_ customization: CustomizationSnapshot) -> String {
		[
			"platformModes=[\(sortedRawRepresentableDict(customization.platformModes))]",
			"idleDismissTtlSeconds=\(customization.idleDismissTtlSeconds)",
			"menubarIconMonochrome=\(customization.menubarIconMonochrome)",
			"combinedMinimalistEnabled=\(customization.combinedMinimalistEnabled)",
			"minimalistBadgeScale=\(customization.minimalistBadgeScale)",
			"sessionPetsEnabled=[\(sortedBoolDict(customization.sessionPetsEnabled))]",
			"sessionCap=[\(sortedIntDict(customization.sessionCap))]",
			"sessionPetsActivatedAt=[\(sortedStringDict(customization.sessionPetsActivatedAt))]",
			"sessionPetsGrandfatheredSessionId=[\(sortedStringDict(customization.sessionPetsGrandfatheredSessionId))]",
			"idleImpatientSeconds=\(customization.idleImpatientSeconds)",
			"idleFrustratedSeconds=\(customization.idleFrustratedSeconds)",
			"evictSessionPetsEnabled=\(customization.evictSessionPetsEnabled)",
			"archiveSessionAfterIdleSeconds=\(customization.archiveSessionAfterIdleSeconds)",
			"pruneArchivedSessionsAfterSeconds=\(customization.pruneArchivedSessionsAfterSeconds)",
		].joined(separator: ",")
	}

	private static func describeAssignments(_ assignments: AssignmentsSnapshot) -> String {
		"default=\(assignments.default),platformOverrides=[\(sortedStringDict(assignments.platformOverrides))]"
	}

	// MARK: - Deterministic dictionary folding

	private static func sortedStringDict(_ dict: [String: String]) -> String {
		dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
	}

	private static func sortedBoolDict(_ dict: [String: Bool]) -> String {
		dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
	}

	private static func sortedIntDict(_ dict: [String: Int]) -> String {
		dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
	}

	private static func sortedRawRepresentableDict<V: RawRepresentable>(_ dict: [String: V]) -> String
	where V.RawValue == String {
		dict.map { "\($0.key)=\($0.value.rawValue)" }.sorted().joined(separator: ",")
	}

	/// Sorted string-string dictionary with values redacted to a length tag —
	/// `sessionLabels`/`knownSessionTitles`/`sessionPromptSummaries` all carry
	/// user-authored or platform-derived free text (a rename, a resolved
	/// thread title, a submitted-prompt summary).
	private static func sortedRedactedDict(_ dict: [WindowKey: String]) -> String {
		dict.map { key, value in "\(key.rawValue)=<redacted:\(value.count)ch>" }.sorted().joined(separator: ",")
	}
}

import Foundation

/// Display and routing mode for a given platform origin.
enum PlatformMode: String, Equatable {
	/// Each origin gets its own floating window (default).
	case own
	/// All combined-mode origins share a single floating window.
	case combined
	/// Origin renders a compact badge strip instead of a pet sprite and RPG HUD.
	case minimalist
	/// Origin is hidden; no window is spawned for it.
	case off

	/// Whether per-session pet panels are offerable for a platform in this mode.
	/// Combined folds all sessions into one shared window and Off spawns no
	/// window at all, so session-pets has nothing to attach to in either case.
	var supportsSessionPets: Bool {
		self == .own || self == .minimalist
	}
}

/// Decoded form of `~/.codogotchi/customization.json`. All fields have safe
/// defaults so the pool stays functional when the file is absent or malformed.
struct CustomizationSnapshot {
	let platformModes: [String: PlatformMode]
	let idleDismissTtlSeconds: Int
	let menubarIconMonochrome: Bool
	/// When true, all Minimalist-mode origins share a single compact panel
	/// instead of one strip per origin, mirroring Combined mode's grouping.
	let combinedMinimalistEnabled: Bool
	/// Scale factor (0.75…1.5) applied to the Minimalist PlatformChip and
	/// AnimationBadge, set by the Settings > Customization size slider.
	let minimalistBadgeScale: Double
	/// Per-origin opt-in for per-session pet panels. Absent origins are treated
	/// as disabled by consumers; this reader preserves the map as written.
	let sessionPetsEnabled: [String: Bool]
	/// Per-origin session-panel cap. `0` is the Unlimited sentinel; absent or
	/// negative values resolve to the default cap of 3 at the point of use
	/// (P15.04/P15.07/P15.09), never in this reader.
	let sessionCap: [String: Int]
	/// Per-origin timestamp (ISO 8601) of the most recent session-pets off→on
	/// toggle, written by `CustomizationTabViewModel.setSessionPetsEnabled`.
	/// Absent for an origin that has never gone through that toggle (including
	/// data written before this field existed) — `resolveRenderKeys` treats a
	/// missing entry as "no gate", admitting every session exactly like before
	/// this grandfather/activity gate existed.
	let sessionPetsActivatedAt: [String: String]
	/// Per-origin `session_id` grandfathered as "Session 1" at the instant of
	/// the most recent off→on toggle recorded in `sessionPetsActivatedAt` — the
	/// session that was already the collapsed single pet before the toggle.
	/// Exempt from the activity gate above; every other sibling session must
	/// show activity strictly after the activation timestamp to render.
	let sessionPetsGrandfatheredSessionId: [String: String]
	/// Elapsed-idle seconds before a pet's badge escalates to "Impatient".
	/// `0` is the Never sentinel (mirrors `idleDismissTtlSeconds`). Feeds
	/// `IdleEscalationConfig.resolve(customization:)`.
	let idleImpatientSeconds: Int
	/// Elapsed-idle seconds before a pet's badge escalates to "Frustrated".
	/// `0` is the Never sentinel. Feeds `IdleEscalationConfig.resolve(customization:)`.
	let idleFrustratedSeconds: Int
	/// Global kill-switch for `SessionSelectionPolicy`'s rank-based session-cap
	/// eviction. `true` (default) preserves today's behavior — a newcomer
	/// session can evict a lower-ranked incumbent when the cap is full. `false`
	/// protects every incumbent from eviction regardless of rank; a newcomer
	/// only fills a slot that isn't already held.
	let evictSessionPetsEnabled: Bool
	/// Elapsed-idle seconds after which a Settings → Sessions "Active"/"Live"
	/// session slice moves into the "Archived" tier. Drives
	/// `SessionsTabViewModel`'s Active/Live vs. Archived tier boundary.
	let archiveSessionAfterIdleSeconds: Int
	/// Age past which an Archived session slice is deleted outright. Drives
	/// both `SessionsTabViewModel`'s Archived tier's upper bound and
	/// `SlicePruner`'s automatic sweep horizon — the two are kept in lockstep
	/// so a slice the Sessions tab still shows as Archived is never silently
	/// deleted by the background pruner ahead of the UI's own horizon.
	let pruneArchivedSessionsAfterSeconds: Int

	/// Sentinel written to `session_cap` for the Unlimited option — every
	/// session-keyed panel renders, nothing is evicted (see `SessionSelectionPolicy`).
	static let unlimitedSessionCap = 0
	/// Default per-origin cap when an origin has session-pets enabled but no
	/// explicit cap has ever been persisted. Single source of truth for the
	/// consumers that resolve this default (`FloatingPetWindowPool`,
	/// `SessionNumberAllocatorState`, `CustomizationTabViewModel`/Settings UI).
	/// Unlimited by default — session panels are opt-out, not capacity-limited.
	static let defaultSessionCap = CustomizationSnapshot.unlimitedSessionCap
	/// Default "Archive Session After Idle" TTL — 1 hour.
	static let defaultArchiveSessionAfterIdleSeconds = 1 * 60 * 60
	/// Default "Prune Archived Sessions" TTL — 12 hours.
	static let defaultPruneArchivedSessionsAfterSeconds = 12 * 60 * 60
	/// Default "Hide Idle Pet After" — Never (`0` is the Never sentinel).
	static let defaultIdleDismissTtlSeconds = 0
	/// Default "Pet Idle Impatient After" — 10 minutes.
	static let defaultIdleImpatientSeconds = 10 * 60
	/// Default "Pet Idle Frustrated After" — 30 minutes.
	static let defaultIdleFrustratedSeconds = 30 * 60
	/// Default Minimalist PlatformChip/AnimationBadge scale — the largest size
	/// Own mode can actually reach (see `GateBadgeLayout.achievableMaxScale`).
	static let defaultMinimalistBadgeScale = Double(GateBadgeLayout.achievableMaxScale)
	/// Default "Enable Minimalist mode for Combined pet" — on, matching every
	/// platform defaulting to Minimalist below.
	static let defaultCombinedMinimalistEnabled = true
	/// Every platform origin Codogotchi ships hooks for. Single source of
	/// truth for the per-origin defaults below — kept in sync with
	/// `CustomizationTabViewModel.origins` and `ASSIGNMENT_BADGE_KEYS`.
	private static let knownOrigins = ["claude_code", "vscode", "codex", "cursor", "antigravity"]
	/// Default per-platform display mode — Minimalist for every known origin.
	static let defaultPlatformModes: [String: PlatformMode] = Dictionary(
		uniqueKeysWithValues: knownOrigins.map { ($0, PlatformMode.minimalist) })
	/// Default per-platform session-pets opt-in — enabled for every known origin.
	static let defaultSessionPetsEnabled: [String: Bool] = Dictionary(
		uniqueKeysWithValues: knownOrigins.map { ($0, true) })

	/// Explicit initializer (not the synthesized memberwise init) so the two new
	/// session-pets maps carry `[:]` defaults. This keeps existing
	/// `CustomizationSnapshot(...)` call sites in the pool/UI tests compiling
	/// unchanged — no pool wiring belongs in this contract-only ticket — while
	/// `read` and `safeDefault` still pass them explicitly.
	init(
		platformModes: [String: PlatformMode],
		idleDismissTtlSeconds: Int,
		menubarIconMonochrome: Bool,
		combinedMinimalistEnabled: Bool,
		minimalistBadgeScale: Double,
		sessionPetsEnabled: [String: Bool] = [:],
		sessionCap: [String: Int] = [:],
		sessionPetsActivatedAt: [String: String] = [:],
		sessionPetsGrandfatheredSessionId: [String: String] = [:],
		idleImpatientSeconds: Int = CustomizationSnapshot.defaultIdleImpatientSeconds,
		idleFrustratedSeconds: Int = CustomizationSnapshot.defaultIdleFrustratedSeconds,
		evictSessionPetsEnabled: Bool = true,
		archiveSessionAfterIdleSeconds: Int = CustomizationSnapshot.defaultArchiveSessionAfterIdleSeconds,
		pruneArchivedSessionsAfterSeconds: Int = CustomizationSnapshot
			.defaultPruneArchivedSessionsAfterSeconds
	) {
		self.platformModes = platformModes
		self.idleDismissTtlSeconds = idleDismissTtlSeconds
		self.menubarIconMonochrome = menubarIconMonochrome
		self.combinedMinimalistEnabled = combinedMinimalistEnabled
		self.minimalistBadgeScale = minimalistBadgeScale
		self.sessionPetsEnabled = sessionPetsEnabled
		self.sessionCap = sessionCap
		self.sessionPetsActivatedAt = sessionPetsActivatedAt
		self.sessionPetsGrandfatheredSessionId = sessionPetsGrandfatheredSessionId
		self.idleImpatientSeconds = idleImpatientSeconds
		self.idleFrustratedSeconds = idleFrustratedSeconds
		self.evictSessionPetsEnabled = evictSessionPetsEnabled
		self.archiveSessionAfterIdleSeconds = archiveSessionAfterIdleSeconds
		self.pruneArchivedSessionsAfterSeconds = pruneArchivedSessionsAfterSeconds
	}

	static let safeDefault = CustomizationSnapshot(
		platformModes: CustomizationSnapshot.defaultPlatformModes,
		idleDismissTtlSeconds: CustomizationSnapshot.defaultIdleDismissTtlSeconds,
		menubarIconMonochrome: false,
		combinedMinimalistEnabled: CustomizationSnapshot.defaultCombinedMinimalistEnabled,
		minimalistBadgeScale: CustomizationSnapshot.defaultMinimalistBadgeScale,
		sessionPetsEnabled: CustomizationSnapshot.defaultSessionPetsEnabled,
		sessionCap: [:],
		sessionPetsActivatedAt: [:],
		sessionPetsGrandfatheredSessionId: [:],
		idleImpatientSeconds: CustomizationSnapshot.defaultIdleImpatientSeconds,
		idleFrustratedSeconds: CustomizationSnapshot.defaultIdleFrustratedSeconds,
		evictSessionPetsEnabled: true,
		archiveSessionAfterIdleSeconds: CustomizationSnapshot.defaultArchiveSessionAfterIdleSeconds,
		pruneArchivedSessionsAfterSeconds: CustomizationSnapshot.defaultPruneArchivedSessionsAfterSeconds
	)
}

/// Reads `customization.json` from disk and returns a `CustomizationSnapshot`.
/// Any IO error or decode failure returns `CustomizationSnapshot.safeDefault`.
///
/// Unknown `platform_modes` values degrade to `.own` so future mode strings
/// never break an older build.
enum CustomizationJsonReader {
	static func read(at path: String) -> CustomizationSnapshot {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return .safeDefault }

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let payload = try? decoder.decode(CustomizationPayload.self, from: data) else {
			return .safeDefault
		}

		// Merge the payload's explicit per-origin choices over the shared
		// defaults, rather than falling back to `.own`/disabled for any origin
		// the user never touched — an origin absent from an older or partial
		// file should pick up today's default, exactly like a fresh install.
		let explicitModes = (payload.platformModes ?? [:])
			.mapValues { PlatformMode(rawValue: $0) ?? .own }
		let modes = CustomizationSnapshot.defaultPlatformModes.merging(explicitModes) { _, new in new }
		let sessionPetsEnabled = CustomizationSnapshot.defaultSessionPetsEnabled
			.merging(payload.sessionPetsEnabled ?? [:]) { _, new in new }
		let rawTtl = payload.idleDismissTtlSeconds ?? CustomizationSnapshot.defaultIdleDismissTtlSeconds
		let rawScale = payload.minimalistBadgeScale ?? CustomizationSnapshot.defaultMinimalistBadgeScale
		let rawImpatient = payload.idleImpatientSeconds ?? CustomizationSnapshot.defaultIdleImpatientSeconds
		let rawFrustrated = payload.idleFrustratedSeconds ?? CustomizationSnapshot.defaultIdleFrustratedSeconds
		let rawArchiveAfterIdle =
			payload.archiveSessionAfterIdleSeconds
			?? CustomizationSnapshot.defaultArchiveSessionAfterIdleSeconds
		let rawPruneArchived =
			payload.pruneArchivedSessionsAfterSeconds
			?? CustomizationSnapshot.defaultPruneArchivedSessionsAfterSeconds
		return CustomizationSnapshot(
			platformModes: modes,
			idleDismissTtlSeconds: rawTtl < 0 ? CustomizationSnapshot.defaultIdleDismissTtlSeconds : rawTtl,
			menubarIconMonochrome: payload.menubarIconMonochrome ?? false,
			combinedMinimalistEnabled: payload.combinedMinimalistEnabled
				?? CustomizationSnapshot.defaultCombinedMinimalistEnabled,
			minimalistBadgeScale: max(
				Double(GateBadgeLayout.achievableMinScale), min(Double(GateBadgeLayout.achievableMaxScale), rawScale)
			),
			sessionPetsEnabled: sessionPetsEnabled,
			sessionCap: payload.sessionCap ?? [:],
			sessionPetsActivatedAt: payload.sessionPetsActivatedAt ?? [:],
			sessionPetsGrandfatheredSessionId: payload.sessionPetsGrandfatheredSessionId ?? [:],
			idleImpatientSeconds: rawImpatient < 0 ? CustomizationSnapshot.defaultIdleImpatientSeconds : rawImpatient,
			idleFrustratedSeconds: rawFrustrated < 0
				? CustomizationSnapshot.defaultIdleFrustratedSeconds : rawFrustrated,
			evictSessionPetsEnabled: payload.evictSessionPetsEnabled ?? true,
			archiveSessionAfterIdleSeconds: rawArchiveAfterIdle < 0
				? CustomizationSnapshot.defaultArchiveSessionAfterIdleSeconds : rawArchiveAfterIdle,
			pruneArchivedSessionsAfterSeconds: rawPruneArchived < 0
				? CustomizationSnapshot.defaultPruneArchivedSessionsAfterSeconds : rawPruneArchived
		)
	}
}

private struct CustomizationPayload: Decodable {
	let platformModes: [String: String]?
	let idleDismissTtlSeconds: Int?
	let menubarIconMonochrome: Bool?
	let combinedMinimalistEnabled: Bool?
	let minimalistBadgeScale: Double?
	let sessionPetsEnabled: [String: Bool]?
	let sessionCap: [String: Int]?
	let sessionPetsActivatedAt: [String: String]?
	let sessionPetsGrandfatheredSessionId: [String: String]?
	let idleImpatientSeconds: Int?
	let idleFrustratedSeconds: Int?
	let evictSessionPetsEnabled: Bool?
	let archiveSessionAfterIdleSeconds: Int?
	let pruneArchivedSessionsAfterSeconds: Int?
}

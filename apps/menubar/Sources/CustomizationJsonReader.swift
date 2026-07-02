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

	/// Sentinel written to `session_cap` for the Unlimited option — every
	/// session-keyed panel renders, nothing is evicted (see `SessionSelectionPolicy`).
	static let unlimitedSessionCap = 0
	/// Default per-origin cap when an origin has session-pets enabled but no
	/// explicit cap has ever been persisted. Single source of truth for the
	/// consumers that resolve this default (`FloatingPetWindowPool`,
	/// `SessionNumberAllocator`, `CustomizationTabViewModel`/Settings UI).
	static let defaultSessionCap = 3

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
		sessionCap: [String: Int] = [:]
	) {
		self.platformModes = platformModes
		self.idleDismissTtlSeconds = idleDismissTtlSeconds
		self.menubarIconMonochrome = menubarIconMonochrome
		self.combinedMinimalistEnabled = combinedMinimalistEnabled
		self.minimalistBadgeScale = minimalistBadgeScale
		self.sessionPetsEnabled = sessionPetsEnabled
		self.sessionCap = sessionCap
	}

	static let safeDefault = CustomizationSnapshot(
		platformModes: [:],
		idleDismissTtlSeconds: 300,
		menubarIconMonochrome: false,
		combinedMinimalistEnabled: false,
		minimalistBadgeScale: 1.0,
		sessionPetsEnabled: [:],
		sessionCap: [:]
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

		let modes = (payload.platformModes ?? [:])
			.mapValues { PlatformMode(rawValue: $0) ?? .own }
		let rawTtl = payload.idleDismissTtlSeconds ?? 300
		let rawScale = payload.minimalistBadgeScale ?? 1.0
		return CustomizationSnapshot(
			platformModes: modes,
			idleDismissTtlSeconds: rawTtl < 0 ? 300 : rawTtl,
			menubarIconMonochrome: payload.menubarIconMonochrome ?? false,
			combinedMinimalistEnabled: payload.combinedMinimalistEnabled ?? false,
			minimalistBadgeScale: max(
				Double(GateBadgeLayout.achievableMinScale), min(Double(GateBadgeLayout.achievableMaxScale), rawScale)
			),
			sessionPetsEnabled: payload.sessionPetsEnabled ?? [:],
			sessionCap: payload.sessionCap ?? [:]
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
}

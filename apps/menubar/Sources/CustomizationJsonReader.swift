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

	static let safeDefault = CustomizationSnapshot(
		platformModes: [:],
		idleDismissTtlSeconds: 300,
		menubarIconMonochrome: false,
		combinedMinimalistEnabled: false,
		minimalistBadgeScale: 1.0
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
				Double(GateBadgeLayout.minScale), min(Double(GateBadgeLayout.maxScale), rawScale)
			)
		)
	}
}

private struct CustomizationPayload: Decodable {
	let platformModes: [String: String]?
	let idleDismissTtlSeconds: Int?
	let menubarIconMonochrome: Bool?
	let combinedMinimalistEnabled: Bool?
	let minimalistBadgeScale: Double?
}

import Foundation

/// Display and routing mode for a given platform origin.
enum PlatformMode: String, Equatable {
	/// Each origin gets its own floating window (default).
	case own
	/// All combined-mode origins share a single floating window.
	case combined
	/// Origin is hidden; no window is spawned for it.
	case off
}

/// Decoded form of `~/.codogotchi/customization.json`. All fields have safe
/// defaults so the pool stays functional when the file is absent or malformed.
struct CustomizationSnapshot {
	let platformModes: [String: PlatformMode]
	let idleDismissTtlSeconds: Int
	let menubarIconMonochrome: Bool

	static let safeDefault = CustomizationSnapshot(
		platformModes: [:],
		idleDismissTtlSeconds: 300,
		menubarIconMonochrome: false
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
		return CustomizationSnapshot(
			platformModes: modes,
			idleDismissTtlSeconds: rawTtl < 0 ? 300 : rawTtl,
			menubarIconMonochrome: payload.menubarIconMonochrome ?? false
		)
	}
}

private struct CustomizationPayload: Decodable {
	let platformModes: [String: String]?
	let idleDismissTtlSeconds: Int?
	let menubarIconMonochrome: Bool?
}

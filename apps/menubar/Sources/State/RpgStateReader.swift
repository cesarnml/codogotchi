import Foundation

/// RPG progression values read from `~/.codogotchi/rpg-state.json`.
/// All fields have safe defaults so the HUD stays functional when the file is
/// absent or cannot be parsed.
struct RpgSnapshot: Equatable {
	let level: Int
	let levelFraction: Double
	let halfHearts: Int
	let activeMinutes: Int
	let lastActivityAt: String?
	let reviveUntil: String?

	static let safeDefault = RpgSnapshot(
		level: 1,
		levelFraction: 0.0,
		halfHearts: MAX_HALF_HEARTS,
		activeMinutes: 0,
		lastActivityAt: nil,
		reviveUntil: nil
	)
}

/// Reads `rpg-state.json` and returns an `RpgSnapshot`. Any IO error or decode
/// failure returns `RpgSnapshot.safeDefault` — callers never see throws.
enum RpgStateReader {
	static func read(at path: String) -> RpgSnapshot {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return .safeDefault }

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let payload = try? decoder.decode(RpgPayload.self, from: data) else {
			return .safeDefault
		}

		return RpgSnapshot(
			level: payload.level ?? 1,
			levelFraction: payload.levelFraction ?? 0.0,
			halfHearts: payload.halfHearts ?? MAX_HALF_HEARTS,
			activeMinutes: payload.activeMinutes ?? 0,
			lastActivityAt: payload.lastActivityAt ?? nil,
			reviveUntil: payload.reviveUntil ?? nil
		)
	}
}

private struct RpgPayload: Decodable {
	let level: Int?
	let levelFraction: Double?
	let halfHearts: Int?
	let activeMinutes: Int?
	let lastActivityAt: String??
	let reviveUntil: String??
}

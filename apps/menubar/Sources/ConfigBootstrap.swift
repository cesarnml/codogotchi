import Foundation

/// First-launch bootstrap: ensure `~/.codogotchi/config.json` exists with a
/// minimal Lite config. Coordinates with P5.04 pet seed order so the first
/// frame can show Maew without `codogotchi setup`.
enum ConfigBootstrap {
	enum Outcome: Equatable {
		case wrote
		case alreadyExists
	}

	enum Failure: Error {
		case writeFailed(underlying: Error)
	}

	/// Writes the minimal Lite config when missing. Does not overwrite an
	/// existing config — Outcome `.alreadyExists` signals no-op.
	@discardableResult
	static func ensureLiteConfig() throws -> Outcome {
		let url = PetConfig.configURL()
		if FileManager.default.fileExists(atPath: url.path) {
			return .alreadyExists
		}

		let payload: [String: Any] = [
			"profile_id": UUID().uuidString,
			"pet": DEFAULT_PET_NAME,
			"features": ["rpg_enabled": false],
		]

		do {
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			let data = try JSONSerialization.data(
				withJSONObject: payload,
				options: [.prettyPrinted, .sortedKeys]
			)
			try data.write(to: url, options: .atomic)
		} catch {
			throw Failure.writeFailed(underlying: error)
		}
		return .wrote
	}
}

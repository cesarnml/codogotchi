import Foundation

/// The compiled-in default pet name. Both loaders reference this constant;
/// `"maew"` does not appear as a literal anywhere else in Sources/.
let DEFAULT_PET_NAME = "maew"

/// Reads `~/.codogotchi/config.json` (or `$CODOGOTCHI_HOME/config.json`)
/// at call time and returns the `pet` key value. Falls back to `DEFAULT_PET_NAME`
/// on any read or parse failure — missing file, malformed JSON, or absent key.
enum PetConfig {
	/// Returns the configured pet name, or `DEFAULT_PET_NAME` on soft failure.
	static func resolvedPetName() -> String {
		let url = configURL()
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let pet = obj["pet"] as? String, !pet.isEmpty
		else { return DEFAULT_PET_NAME }
		return pet
	}

	static func configURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"), let home = String(validatingUTF8: cStr) {
			return URL(fileURLWithPath: home).appendingPathComponent("config.json")
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("config.json")
	}

	/// Updates the `pet` key in `~/.codogotchi/config.json`, preserving every
	/// other field (`profile_id`, `features.rpg_enabled`, RPG-tier keys, …).
	///
	/// Read-merge-write rather than clobber: writing a bare `{ "pet": petName }`
	/// would strip `profile_id` and `features.rpg_enabled`, which the CLI's
	/// Lite/RPG config schema requires — that invalidates the config and breaks
	/// `codogotchi hooks install/update` ("expected Lite/RPG schema with explicit
	/// features.rpg_enabled"). When no parseable config exists yet, fall back to a
	/// minimal valid Lite config so we never emit a schema-invalid file.
	static func write(petName: String, to url: URL) throws {
		let parent = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

		var obj: [String: Any]
		if let data = try? Data(contentsOf: url),
			let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		{
			obj = existing
		} else {
			// No valid config on disk — synthesize a minimal Lite config so the
			// result still satisfies the CLI schema.
			obj = [
				"profile_id": UUID().uuidString,
				"features": ["rpg_enabled": false],
			]
		}
		obj["pet"] = petName

		let data = try JSONSerialization.data(
			withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
		try data.write(to: url, options: .atomic)
	}
}

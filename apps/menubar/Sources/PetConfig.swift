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
}

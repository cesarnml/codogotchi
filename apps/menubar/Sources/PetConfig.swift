import Foundation

/// The compiled-in default pet name. Both loaders reference this constant;
/// `"maew"` does not appear as a literal anywhere else in Sources/.
let DEFAULT_PET_NAME = "maew"

/// Reads `~/.codogotchi/config.json` (or `$CODOGOTCHI_HOME/config.json`)
/// at call time and returns the `pet` key value. Falls back to `DEFAULT_PET_NAME`
/// on any read or parse failure — missing file, malformed JSON, or absent key.
enum PetConfig {
	struct HealthLogicSettings: Equatable {
		var inactivityDecayHours: Double
		var inactivityDecayHalfHearts: Int
		var activityRegenMinutes: Int
		var activityRegenHalfHearts: Int
		var diseaseAnimationsEnabled: Bool

		static let defaults = HealthLogicSettings(
			inactivityDecayHours: 8,
			inactivityDecayHalfHearts: 1,
			activityRegenMinutes: 60,
			activityRegenHalfHearts: 1,
			diseaseAnimationsEnabled: true
		)
	}

	/// Returns `false` only when `features.rpg_hud_enabled` is explicitly `false`.
	/// Defaults to `true` (HUD visible) when the key is absent, config is
	/// missing, or the value is not a Boolean.
	static func resolvedRPGHUDEnabled() -> Bool {
		resolvedRPGHUDEnabled(from: configURL())
	}

	/// URL-injectable variant for tests and `RPGTabViewModel`.
	static func resolvedRPGHUDEnabled(from url: URL) -> Bool {
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let features = obj["features"] as? [String: Any],
			let flag = features["rpg_hud_enabled"] as? Bool
		else { return true }
		return flag
	}

	static func resolvedHealthLogicSettings() -> HealthLogicSettings {
		resolvedHealthLogicSettings(from: configURL())
	}

	static func resolvedHealthLogicSettings(from url: URL) -> HealthLogicSettings {
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let healthLogic = obj["health_logic"] as? [String: Any]
		else { return .defaults }

		let defaults = HealthLogicSettings.defaults
		return HealthLogicSettings(
			inactivityDecayHours: positiveDouble(
				healthLogic["inactivity_decay_hours"],
				default: defaults.inactivityDecayHours
			),
			inactivityDecayHalfHearts: positiveInt(
				healthLogic["inactivity_decay_half_hearts"],
				default: defaults.inactivityDecayHalfHearts
			),
			activityRegenMinutes: positiveInt(
				healthLogic["activity_regen_minutes"],
				default: defaults.activityRegenMinutes
			),
			activityRegenHalfHearts: positiveInt(
				healthLogic["activity_regen_half_hearts"],
				default: defaults.activityRegenHalfHearts
			),
			diseaseAnimationsEnabled: (healthLogic["disease_animations_enabled"] as? Bool)
				?? defaults.diseaseAnimationsEnabled
		)
	}

	static func resolvedDiseaseAnimationsEnabled() -> Bool {
		resolvedHealthLogicSettings().diseaseAnimationsEnabled
	}

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

	/// Updates `features.rpg_hud_enabled` in `~/.codogotchi/config.json`,
	/// preserving every other field using a read-merge-write approach.
	static func write(rpgHUDEnabled: Bool, to url: URL) throws {
		var obj = try readMergedConfigObject(from: url)
		var features = (obj["features"] as? [String: Any]) ?? ["rpg_enabled": false]
		features["rpg_hud_enabled"] = rpgHUDEnabled
		obj["features"] = features
		try writeConfigObject(obj, to: url)
	}

	static func write(healthLogic settings: HealthLogicSettings, to url: URL) throws {
		var obj = try readMergedConfigObject(from: url)
		obj["health_logic"] = [
			"inactivity_decay_hours": settings.inactivityDecayHours,
			"inactivity_decay_half_hearts": settings.inactivityDecayHalfHearts,
			"activity_regen_minutes": settings.activityRegenMinutes,
			"activity_regen_half_hearts": settings.activityRegenHalfHearts,
			"disease_animations_enabled": settings.diseaseAnimationsEnabled,
		]
		try writeConfigObject(obj, to: url)
	}

	private static func readMergedConfigObject(from url: URL) throws -> [String: Any] {
		let parent = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

		if let data = try? Data(contentsOf: url),
			let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		{
			return existing
		}
		return [
			"profile_id": UUID().uuidString,
			"features": ["rpg_enabled": false],
		]
	}

	private static func writeConfigObject(_ obj: [String: Any], to url: URL) throws {
		let data = try JSONSerialization.data(
			withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
		try data.write(to: url, options: .atomic)
	}

	private static func positiveInt(_ value: Any?, default defaultValue: Int) -> Int {
		if let int = value as? Int, int > 0 { return int }
		if let double = value as? Double, double > 0 { return Int(double.rounded()) }
		return defaultValue
	}

	private static func positiveDouble(_ value: Any?, default defaultValue: Double) -> Double {
		if let double = value as? Double, double > 0 { return double }
		if let int = value as? Int, int > 0 { return Double(int) }
		return defaultValue
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
		var obj = try readMergedConfigObject(from: url)
		obj["pet"] = petName
		try writeConfigObject(obj, to: url)
	}
}

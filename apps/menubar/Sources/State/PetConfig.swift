import Foundation

/// The compiled-in default pet name. Both loaders reference this constant;
/// `"maew"` does not appear as a literal anywhere else in Sources/.
let DEFAULT_PET_NAME = "maew"

/// Reads `~/.codogotchi/config.json` (or `$CODOGOTCHI_HOME/config.json`)
/// at call time and returns the `pet` key value. Falls back to `DEFAULT_PET_NAME`
/// on any read or parse failure — missing file, malformed JSON, or absent key.
enum PetConfig {
	/// Which floating pet(s) show the RPG HUD overlay (hearts/level/XP ring).
	/// Persisted as `features.rpg_hud_mode`, replacing the older boolean
	/// `features.rpg_hud_enabled` (still read for one-time migration).
	enum RPGHUDMode: String, Equatable, CaseIterable {
		case all
		case mostRecent = "most_recent"
		case hidden

		static let defaultMode: RPGHUDMode = .mostRecent
	}

	struct HealthLogicSettings: Equatable {
		/// Sickness trigger thresholds are stored in half-hearts; `0` means
		/// "Never". Severe must stay strictly below mild (a heart count can't be
		/// both mild-sick and severe-sick), so reads clamp severe to `mild - 1`
		/// when a stale config violates the invariant.
		static let sicknessTriggerMaxHalfHearts = 4

		var inactivityDecayHours: Double
		var inactivityDecayHalfHearts: Int
		var activityRegenMinutes: Int
		var activityRegenHalfHearts: Int
		var diseaseAnimationsEnabled: Bool
		var skipWeekends: Bool
		var mildSicknessHalfHearts: Int
		var severeSicknessHalfHearts: Int

		static let defaults = HealthLogicSettings(
			inactivityDecayHours: 8,
			inactivityDecayHalfHearts: 1,
			activityRegenMinutes: 60,
			activityRegenHalfHearts: 1,
			diseaseAnimationsEnabled: true,
			skipWeekends: true,
			mildSicknessHalfHearts: 2,
			severeSicknessHalfHearts: 1
		)
	}

	/// Resolves the active `RPGHUDMode`. Prefers `features.rpg_hud_mode` when
	/// present and valid; otherwise migrates the legacy `features.rpg_hud_enabled`
	/// boolean (`false` -> `.hidden`), and falls back to `.defaultMode`
	/// ("Show HUD on Most Recent Pet") when neither key is present.
	static func resolvedRPGHUDMode() -> RPGHUDMode {
		resolvedRPGHUDMode(from: configURL())
	}

	static func resolvedRPGHUDMode(from url: URL) -> RPGHUDMode {
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let features = obj["features"] as? [String: Any]
		else { return .defaultMode }
		if let modeRaw = features["rpg_hud_mode"] as? String, let mode = RPGHUDMode(rawValue: modeRaw) {
			return mode
		}
		if let legacyEnabled = features["rpg_hud_enabled"] as? Bool, legacyEnabled == false {
			return .hidden
		}
		return .defaultMode
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
		let mild = boundedInt(
			healthLogic["mild_sickness_half_hearts"],
			range: 0...HealthLogicSettings.sicknessTriggerMaxHalfHearts,
			default: defaults.mildSicknessHalfHearts
		)
		let severeRaw = boundedInt(
			healthLogic["severe_sickness_half_hearts"],
			range: 0...HealthLogicSettings.sicknessTriggerMaxHalfHearts,
			default: defaults.severeSicknessHalfHearts
		)
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
				?? defaults.diseaseAnimationsEnabled,
			skipWeekends: (healthLogic["skip_weekends"] as? Bool) ?? defaults.skipWeekends,
			mildSicknessHalfHearts: mild,
			severeSicknessHalfHearts: min(severeRaw, max(0, mild - 1))
		)
	}

	/// Whether the destructive "Prune Session" confirmation alert should be
	/// skipped, pruning immediately on click. Can be turned back on via a
	/// checkbox on the alert itself; defaults to `true` (skip the confirmation)
	/// when unset or on any read failure.
	static func resolvedSkipPruneConfirmation() -> Bool {
		resolvedSkipPruneConfirmation(from: configURL())
	}

	static func resolvedSkipPruneConfirmation(from url: URL) -> Bool {
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let features = obj["features"] as? [String: Any]
		else { return true }
		return (features["skip_prune_confirmation"] as? Bool) ?? true
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

	/// Updates `features.rpg_hud_mode` in `~/.codogotchi/config.json`,
	/// preserving every other field using a read-merge-write approach. Clears
	/// the legacy `features.rpg_hud_enabled` boolean so future reads are
	/// unambiguous once the user has touched the new control.
	static func write(rpgHUDMode: RPGHUDMode, to url: URL) throws {
		var obj = try readMergedConfigObject(from: url)
		var features = (obj["features"] as? [String: Any]) ?? ["rpg_enabled": false]
		features["rpg_hud_mode"] = rpgHUDMode.rawValue
		features.removeValue(forKey: "rpg_hud_enabled")
		obj["features"] = features
		try writeConfigObject(obj, to: url)
	}

	/// Persists the user's "Do not show this warning again." choice on the
	/// Prune Session alert. Only ever called with `true` — there's no UI path
	/// to re-enable the confirmation once skipped.
	static func write(skipPruneConfirmation: Bool, to url: URL) throws {
		var obj = try readMergedConfigObject(from: url)
		var features = (obj["features"] as? [String: Any]) ?? ["rpg_enabled": false]
		features["skip_prune_confirmation"] = skipPruneConfirmation
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
			"skip_weekends": settings.skipWeekends,
			"mild_sickness_half_hearts": settings.mildSicknessHalfHearts,
			"severe_sickness_half_hearts": settings.severeSicknessHalfHearts,
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

	private static func boundedInt(_ value: Any?, range: ClosedRange<Int>, default defaultValue: Int) -> Int {
		if let int = value as? Int, range.contains(int) { return int }
		if let double = value as? Double, double.rounded() == double, range.contains(Int(double)) {
			return Int(double)
		}
		return defaultValue
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

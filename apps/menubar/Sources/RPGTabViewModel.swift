import AppKit
import Foundation

/// View-model for the RPG settings tab.
///
/// Owns the `rpg_hud_mode` setting: reads the mode from config on init,
/// persists changes via `PetConfig.write(rpgHUDMode:to:)`, and exposes
/// static demo values for the showcase / demo-mode HUD render.
final class RPGTabViewModel {
	/// Which floating pet(s) currently show the RPG HUD. Defaults to
	/// `.mostRecent` when the config key is absent or the file does not exist.
	private(set) var hudMode: PetConfig.RPGHUDMode

	private(set) var healthLogic: PetConfig.HealthLogicSettings

	private(set) var snapshot: RpgSnapshot
	private(set) var petName: String
	private(set) var petImage: NSImage?

	var halfHearts: Int { max(0, min(MAX_HALF_HEARTS, snapshot.halfHearts)) }
	var hearts: [HeartState] { RPGHUDViewModel.hearts(from: halfHearts) }
	var level: Int { snapshot.level }
	var ringFraction: Double {
		guard snapshot.levelFraction.isFinite else { return 0 }
		return max(0, min(1, snapshot.levelFraction))
	}
	var xpPercentText: String { "\(Int((ringFraction * 100).rounded()))%" }
	var activeMinutesText: String {
		"\(snapshot.activeMinutes) / \(healthLogic.activityRegenMinutes) min"
	}
	var decaySummaryText: String {
		"Every \(formatHours(healthLogic.inactivityDecayHours)) inactive -> -\(formatHalfHearts(healthLogic.inactivityDecayHalfHearts))"
	}
	var regenSummaryText: String {
		"Every \(healthLogic.activityRegenMinutes) active min -> +\(formatHalfHearts(healthLogic.activityRegenHalfHearts))"
	}

	static let inactivityDecayHourOptions: [Double] = [4, 8, 12, 24, 48]
	static let activityRegenMinuteOptions = [15, 30, 60, 120]

	/// Sickness trigger options in half-hearts; `0` = Never, then 1/2-heart
	/// increments up to 2 hearts.
	static let sicknessTriggerOptions = Array(0...PetConfig.HealthLogicSettings.sicknessTriggerMaxHalfHearts)

	/// Severe options are exclusively capped by the mild trigger: "Never" is
	/// always valid; any other value must sit strictly below mild.
	static func severeSicknessOptions(mild: Int) -> [Int] {
		sicknessTriggerOptions.filter { $0 == 0 || $0 < mild }
	}

	var severeSicknessOptions: [Int] {
		Self.severeSicknessOptions(mild: healthLogic.mildSicknessHalfHearts)
	}

	private let configURL: URL
	private let rpgStatePath: String
	private let assignmentsURL: URL
	private let injectedPetImage: NSImage?

	init(
		configURL: URL = PetConfig.configURL(),
		rpgStatePath: String = CodogotchiFolders.rpgStatePath(),
		assignmentsURL: URL = URL(fileURLWithPath: CodogotchiFolders.assignmentsPath()),
		petImage: NSImage? = nil
	) {
		self.configURL = configURL
		self.rpgStatePath = rpgStatePath
		self.assignmentsURL = assignmentsURL
		self.injectedPetImage = petImage
		self.hudMode = .defaultMode
		self.healthLogic = .defaults
		self.snapshot = RpgStateReader.read(at: rpgStatePath)
		self.petName = DEFAULT_PET_NAME
		self.petImage = nil
		refresh()
	}

	func refresh() {
		hudMode = PetConfig.resolvedRPGHUDMode(from: configURL)
		healthLogic = PetConfig.resolvedHealthLogicSettings(from: configURL)
		snapshot = RpgStateReader.read(at: rpgStatePath)
		petName = AssignmentsJsonReader.read(at: assignmentsURL.path).default
		petImage = injectedPetImage ?? Self.loadPetImage(petId: petName)
	}

	/// Persists `rpg_hud_mode` to config and updates the local property.
	/// Reverts the in-memory value if the write fails so the UI stays
	/// consistent with what will survive a relaunch.
	func setHUDMode(_ mode: PetConfig.RPGHUDMode) {
		let previous = hudMode
		hudMode = mode
		do {
			try PetConfig.write(rpgHUDMode: mode, to: configURL)
		} catch {
			hudMode = previous
		}
	}

	func setInactivityDecayHours(_ hours: Double) {
		let selected = Self.inactivityDecayHourOptions.contains(hours) ? hours : PetConfig.HealthLogicSettings.defaults.inactivityDecayHours
		updateHealthLogic { $0.inactivityDecayHours = selected }
	}

	func setInactivityDecayHalfHearts(_ halfHearts: Int) {
		updateHealthLogic { $0.inactivityDecayHalfHearts = max(1, min(MAX_HALF_HEARTS, halfHearts)) }
	}

	func setActivityRegenMinutes(_ minutes: Int) {
		let selected = Self.activityRegenMinuteOptions.contains(minutes) ? minutes : PetConfig.HealthLogicSettings.defaults.activityRegenMinutes
		updateHealthLogic { $0.activityRegenMinutes = selected }
	}

	func setActivityRegenHalfHearts(_ halfHearts: Int) {
		updateHealthLogic { $0.activityRegenHalfHearts = max(1, min(MAX_HALF_HEARTS, halfHearts)) }
	}

	func setDiseaseAnimationsEnabled(_ enabled: Bool) {
		updateHealthLogic { $0.diseaseAnimationsEnabled = enabled }
	}

	func setSkipWeekends(_ enabled: Bool) {
		updateHealthLogic { $0.skipWeekends = enabled }
	}

	/// Setting mild re-validates severe: if the prior severe value is no longer
	/// strictly below the new mild, severe snaps to the maximal valid option
	/// (`mild - 1`, or Never when mild itself is Never).
	func setMildSicknessHalfHearts(_ value: Int) {
		guard Self.sicknessTriggerOptions.contains(value) else { return }
		updateHealthLogic {
			$0.mildSicknessHalfHearts = value
			if $0.severeSicknessHalfHearts >= value {
				$0.severeSicknessHalfHearts = max(0, value - 1)
			}
		}
	}

	func setSevereSicknessHalfHearts(_ value: Int) {
		guard severeSicknessOptions.contains(value) else { return }
		updateHealthLogic { $0.severeSicknessHalfHearts = value }
	}

	private func updateHealthLogic(_ mutate: (inout PetConfig.HealthLogicSettings) -> Void) {
		let previous = healthLogic
		mutate(&healthLogic)
		do {
			try PetConfig.write(healthLogic: healthLogic, to: configURL)
		} catch {
			healthLogic = previous
		}
	}

	private func formatHalfHearts(_ value: Int) -> String {
		value == 1 ? "1/2 heart" : "\(value) half-hearts"
	}

	private func formatHours(_ value: Double) -> String {
		value.rounded() == value ? "\(Int(value))h" : "\(value)h"
	}

	private static func loadPetImage(petId: String) -> NSImage? {
		let directory: URL
		if petId == DEFAULT_PET_NAME {
			directory = PetAssetResolver.defaultMaewFallbackURL()
		} else {
			directory = CodogotchiFolders.petFolderURL().appendingPathComponent(petId)
		}
		let manifestURL = directory.appendingPathComponent("pet.json")
		let sheetName: String
		if let data = try? Data(contentsOf: manifestURL),
			let manifest = try? JSONDecoder().decode(RPGPreviewPetManifest.self, from: data)
		{
			sheetName = manifest.spritesheetPath
		} else {
			sheetName = "spritesheet.webp"
		}
		return PetThumbnail.idleFirstFrame(
			spritesheetURL: directory.appendingPathComponent(sheetName),
			targetHeight: 280
		)
	}
}

private struct RPGPreviewPetManifest: Decodable {
	let spritesheetPath: String
}

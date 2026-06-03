import Foundation

/// View-model for the RPG settings tab.
///
/// Owns the `rpg_hud_enabled` toggle: reads the flag from config on init,
/// persists changes via `PetConfig.write(rpgHUDEnabled:to:)`, and exposes
/// static demo values for the showcase / demo-mode HUD render.
final class RPGTabViewModel {
	/// Whether the floating RPG HUD is currently enabled. Defaults to `true`
	/// when the config key is absent or the file does not exist.
	private(set) var rpgHUDEnabled: Bool

	/// Demo half-heart count for showcase rendering (full-ish: 5 of 6).
	let demoHalfHearts: Int = 5

	/// Demo level for showcase rendering (mid-level showcase).
	let demoLevel: Int = 42

	/// Demo ring fill fraction for showcase rendering (partially filled).
	let demoRingFraction: Double = 0.65

	private let configURL: URL

	init(configURL: URL = PetConfig.configURL()) {
		self.configURL = configURL
		self.rpgHUDEnabled = PetConfig.resolvedRPGHUDEnabled(from: configURL)
	}

	/// Persists `rpg_hud_enabled` to config and updates the local property.
	/// Reverts the in-memory value if the write fails so the UI stays
	/// consistent with what will survive a relaunch.
	func setRPGHUDEnabled(_ enabled: Bool) {
		rpgHUDEnabled = enabled
		do {
			try PetConfig.write(rpgHUDEnabled: enabled, to: configURL)
		} catch {
			rpgHUDEnabled = !enabled
		}
	}
}

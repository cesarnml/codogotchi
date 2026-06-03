import Foundation

/// View-model for the RPG settings tab.
///
/// Stub: all values are placeholder/wrong; all mutations are no-ops.
/// Tests written against this stub will fail — that is the Red state.
final class RPGTabViewModel {
	/// Whether the RPG HUD is currently enabled. Stub always returns `false`.
	private(set) var rpgHUDEnabled: Bool = false

	/// Demo half-heart count for showcase rendering. Stub: 0.
	let demoHalfHearts: Int = 0

	/// Demo level for showcase rendering. Stub: 1.
	let demoLevel: Int = 1

	/// Demo ring fill fraction for showcase rendering. Stub: 0.0.
	let demoRingFraction: Double = 0.0

	private let configURL: URL

	init(configURL: URL = PetConfig.configURL()) {
		self.configURL = configURL
	}

	/// Persists `rpg_hud_enabled` to config and updates the local property.
	/// Stub: no-op.
	func setRPGHUDEnabled(_ enabled: Bool) {
		// stub — does not write or update
	}
}

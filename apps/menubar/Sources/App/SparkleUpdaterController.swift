import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`.
///
/// `LSUIElement` menu-bar apps have no standard app menu for Sparkle to graft
/// its own "Check for Updates…" item onto, so `MenubarMenu` carries that item
/// itself and calls `checkForUpdates()` here.
final class SparkleUpdaterController {
	private let controller: SPUStandardUpdaterController

	init() {
		controller = SPUStandardUpdaterController(
			startingUpdater: true,
			updaterDelegate: nil,
			userDriverDelegate: nil
		)
	}

	func checkForUpdates() {
		controller.checkForUpdates(nil)
	}
}

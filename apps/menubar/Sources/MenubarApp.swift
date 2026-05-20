import AppKit

/// Menu-bar agent entry point.
///
/// Registers an `NSStatusItem` and, when the pet assets are present at
/// `~/.codex/pets/mali/`, hands the status item off to a `MenubarRenderer`
/// that animates the idle row on a 1-second-per-cycle continuous loop.
/// Later Phase 02 tickets (P2.06 demo driver, P2.07 live polling) call
/// `renderer.update(state:visualMode:)` to switch states.
///
/// The app is configured as a menu-bar agent via `LSUIElement = true` in
/// `Info.plist` so it has no Dock icon and no main window.
@main
final class MenubarApp: NSObject, NSApplicationDelegate {
	/// Held strongly so the status item is not deallocated.
	var statusItem: NSStatusItem?

	/// Held strongly so the renderer's timer survives past the lifecycle
	/// callback. Nil until pet assets are successfully loaded.
	var renderer: MenubarRenderer?

	static func main() {
		let app = NSApplication.shared
		let delegate = MenubarApp()
		app.delegate = delegate
		app.setActivationPolicy(.accessory)
		app.run()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = item.button {
			button.image = NSImage(
				systemSymbolName: "pawprint",
				accessibilityDescription: "Codogotchi"
			)
		}
		let menu = NSMenu()
		menu.addItem(
			NSMenuItem(
				title: "Quit Menubar",
				action: #selector(NSApplication.terminate(_:)),
				keyEquivalent: "q"
			)
		)
		item.menu = menu
		self.statusItem = item

		// Attempt to load Mali and wire the renderer. If pet assets are
		// missing (e.g. on a dev machine without `~/.codex/pets/mali/`
		// populated), keep the placeholder `pawprint` icon — the renderer
		// is optional Phase 02 scaffolding, not a hard launch requirement.
		do {
			let pet = try MaliPet()
			let renderer = MenubarRenderer(pet: pet) { [weak item] image in
				item?.button?.image = image
			}
			renderer.update(state: .idle, visualMode: .normal)
			self.renderer = renderer
		} catch {
			NSLog("MenubarApp: MaliPet load failed — keeping placeholder icon (\(error))")
		}
	}
}

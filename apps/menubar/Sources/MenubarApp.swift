import AppKit

/// Menu-bar agent entry point.
///
/// Registers an `NSStatusItem` with a placeholder system-symbol icon and a
/// single "Quit" menu item. Phase 02 later tickets replace the placeholder
/// icon with the Mali sprite and wire state-driven animation on top of this
/// scaffold.
///
/// The app is configured as a menu-bar agent via `LSUIElement = true` in
/// `Info.plist` so it has no Dock icon and no main window.
@main
final class MenubarApp: NSObject, NSApplicationDelegate {
	/// Held strongly so the status item is not deallocated.
	var statusItem: NSStatusItem?

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
	}
}

import AppKit

/// Constructs the menu attached to the menu-bar `NSStatusItem`.
///
/// The menu has four items, in this order:
///   1. **Show/Hide Pet** — toggles the desktop pet surface.
///   2. **Settings…** — opens the Settings window (⌘,).
///   3. **Quit Codogotchi** — terminates the app.
///   4. **⚠ Hooks not active — Retry install** — hidden until post-onboarding hooks are inactive.
///
/// Folder shortcuts moved out of this menu: "Open data folder" lives in
/// Settings → Developer and "Open pet folder" in Settings → Pet (both via
/// `CodogotchiFolders`).
///
/// `MenubarMenu` is itself the action target for all items, so the caller
/// must retain it for the lifetime of the menu. `NSMenuItem.target` is a
/// weak reference (a known AppKit pitfall: dropping the target makes the
/// items "do nothing"), so `MenubarApp` holds a strong reference.
final class MenubarMenu: NSObject {
	static let showFloatingPetTitle = "Show Pet"
	static let hideFloatingPetTitle = "Hide Pet"
	static let settingsTitle = "Settings…"
	static let quitTitle = "Quit Codogotchi"
	static let hooksNotActiveTitle = "⚠ Hooks not active — Retry install"

	private let terminate: () -> Void
	private let floatingPetController: FloatingPetVisibilityControlling?
	private let retryHooksInstall: (() -> Void)?
	private let openSettings: (() -> Void)?
	private weak var builtMenu: NSMenu?
	private weak var hooksNotActiveItem: NSMenuItem?

	init(
		terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
		floatingPetController: FloatingPetVisibilityControlling? = nil,
		retryHooksInstall: (() -> Void)? = nil,
		openSettings: (() -> Void)? = nil
	) {
		self.terminate = terminate
		self.floatingPetController = floatingPetController
		self.retryHooksInstall = retryHooksInstall
		self.openSettings = openSettings
		super.init()
	}

	@MainActor
	func build() -> NSMenu {
		let menu = NSMenu()
		builtMenu = menu

		let floatingItem = NSMenuItem(
			title: floatingPetToggleTitle(),
			action: #selector(toggleFloatingPet(_:)),
			keyEquivalent: ""
		)
		floatingItem.target = self
		floatingItem.isEnabled = floatingPetController != nil
		menu.addItem(floatingItem)

		let settingsItem = NSMenuItem(
			title: Self.settingsTitle,
			action: #selector(openSettingsAction(_:)),
			keyEquivalent: ","
		)
		settingsItem.target = self
		settingsItem.isEnabled = openSettings != nil
		menu.addItem(settingsItem)

		let quitItem = NSMenuItem(
			title: Self.quitTitle,
			action: #selector(quitMenubar(_:)),
			keyEquivalent: "q"
		)
		quitItem.target = self
		menu.addItem(quitItem)

		let hooksItem = NSMenuItem(
			title: Self.hooksNotActiveTitle,
			action: #selector(retryHooksInstallAction(_:)),
			keyEquivalent: ""
		)
		hooksItem.target = self
		hooksItem.isHidden = true
		menu.addItem(hooksItem)
		hooksNotActiveItem = hooksItem

		return menu
	}

	/// Toggles the "Hooks not active" menu item.
	/// Called after hook status refresh: visible when onboarding is done but hooks aren't firing.
	@MainActor
	func refreshHooksNotActive(isActive: Bool) {
		hooksNotActiveItem?.isHidden = isActive
	}

	@MainActor
	@objc func toggleFloatingPet(_ sender: Any?) {
		guard let floatingPetController else { return }
		floatingPetController.setFloatingPetVisible(!floatingPetController.isFloatingPetVisible)
		(sender as? NSMenuItem)?.title = floatingPetToggleTitle()
	}

	@objc func quitMenubar(_ sender: Any?) {
		terminate()
	}

	@objc func retryHooksInstallAction(_ sender: Any?) {
		retryHooksInstall?()
	}

	@objc func openSettingsAction(_ sender: Any?) {
		openSettings?()
	}

	/// Keeps the status-item menu toggle label in sync after hiding from the
	/// floating pet surface (right-click pill or other non-menu paths). The
	/// toggle is the first menu item.
	@MainActor
	func refreshFloatingPetMenuItemTitle() {
		guard let first = builtMenu?.items.first else { return }
		first.title = floatingPetToggleTitle()
	}

	@MainActor
	private func floatingPetToggleTitle() -> String {
		guard let floatingPetController else { return Self.showFloatingPetTitle }
		return floatingPetController.isFloatingPetVisible
			? Self.hideFloatingPetTitle
			: Self.showFloatingPetTitle
	}
}

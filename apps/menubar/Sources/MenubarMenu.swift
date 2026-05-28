import AppKit

/// Narrow seam over `NSWorkspace.open(_:)` so menu-item action tests can
/// observe what URL would be opened without actually invoking Finder.
///
/// `NSWorkspace` conforms to this protocol via its built-in
/// `open(_:) -> Bool` selector, so production callers can pass
/// `NSWorkspace.shared` directly.
protocol MenuWorkspaceOpening: AnyObject {
	@discardableResult
	func open(_ url: URL) -> Bool
}

extension NSWorkspace: MenuWorkspaceOpening {}

/// Constructs the menu attached to the menu-bar `NSStatusItem`.
///
/// The menu has four items, in this order:
///   1. **Open log folder** — opens `~/.codogotchi/` via `NSWorkspace.open(_:)`.
///   2. **Reveal pet folder** — opens `~/.codogotchi/pets/` via `NSWorkspace.open(_:)`.
///   3. **Show/Hide Floating Pet** — toggles the desktop pet surface.
///   4. **Quit Codogotchi** — terminates the app.
///
/// `MenubarMenu` is itself the action target for all items, so the caller
/// must retain it for the lifetime of the menu. `NSMenuItem.target` is a
/// weak reference (a known AppKit pitfall: dropping the target makes the
/// items "do nothing"), so `MenubarApp` holds a strong reference.
final class MenubarMenu: NSObject {
	static let openLogFolderTitle = "Open log folder"
	static let revealPetFolderTitle = "Reveal pet folder"
	static let showFloatingPetTitle = "Show Floating Pet"
	static let hideFloatingPetTitle = "Hide Floating Pet"
	static let settingsTitle = "Settings…"
	static let quitTitle = "Quit Codogotchi"
	static let hooksNotActiveTitle = "⚠ Hooks not active — Retry install"

	private let workspace: MenuWorkspaceOpening
	private let terminate: () -> Void
	private let logFolderURL: URL
	private let petFolderURL: URL
	private let fileManager: FileManager
	private let floatingPetController: FloatingPetVisibilityControlling?
	private let retryHooksInstall: (() -> Void)?
	private let openSettings: (() -> Void)?
	private weak var builtMenu: NSMenu?
	private weak var hooksNotActiveItem: NSMenuItem?

	init(
		workspace: MenuWorkspaceOpening = NSWorkspace.shared,
		terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
		logFolderURL: URL = MenubarMenu.defaultLogFolderURL(),
		petFolderURL: URL = MenubarMenu.defaultPetFolderURL(),
		fileManager: FileManager = .default,
		floatingPetController: FloatingPetVisibilityControlling? = nil,
		retryHooksInstall: (() -> Void)? = nil,
		openSettings: (() -> Void)? = nil
	) {
		self.workspace = workspace
		self.terminate = terminate
		self.logFolderURL = logFolderURL
		self.petFolderURL = petFolderURL
		self.fileManager = fileManager
		self.floatingPetController = floatingPetController
		self.retryHooksInstall = retryHooksInstall
		self.openSettings = openSettings
		super.init()
	}

	/// `~/.codogotchi/` — the canonical log folder used by `TransitionLog`
	/// and the live polling driver. Respects `CODOGOTCHI_HOME` when set.
	static func defaultLogFolderURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"),
			let home = String(validatingUTF8: cStr),
			!home.isEmpty
		{
			return URL(fileURLWithPath: home, isDirectory: true)
		}
		return FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi", isDirectory: true)
	}

	/// `~/.codogotchi/pets/` — the canonical pet store directory, surfaced via
	/// the "Reveal pet folder" menu item. Respects `CODOGOTCHI_HOME` when set.
	static func defaultPetFolderURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"),
			let home = String(validatingUTF8: cStr),
			!home.isEmpty
		{
			return URL(fileURLWithPath: home, isDirectory: true)
				.appendingPathComponent("pets", isDirectory: true)
		}
		return FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi", isDirectory: true)
			.appendingPathComponent("pets", isDirectory: true)
	}

	@MainActor
	func build() -> NSMenu {
		let menu = NSMenu()
		builtMenu = menu

		let openItem = NSMenuItem(
			title: Self.openLogFolderTitle,
			action: #selector(openLogFolder(_:)),
			keyEquivalent: ""
		)
		openItem.target = self
		menu.addItem(openItem)

		let revealItem = NSMenuItem(
			title: Self.revealPetFolderTitle,
			action: #selector(revealPetFolder(_:)),
			keyEquivalent: ""
		)
		revealItem.target = self
		menu.addItem(revealItem)

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

	@objc func openLogFolder(_ sender: Any?) {
		// Ensure the folder exists before opening so first-launch (no live
		// poll yet, no transition log yet) does not silently no-op the menu
		// action. `createDirectory` with `withIntermediateDirectories: true`
		// is idempotent — it does not error if the folder already exists.
		try? fileManager.createDirectory(
			at: logFolderURL,
			withIntermediateDirectories: true
		)
		workspace.open(logFolderURL)
	}

	@objc func revealPetFolder(_ sender: Any?) {
		workspace.open(petFolderURL)
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
	/// floating pet surface (right-click pill or other non-menu paths).
	@MainActor
	func refreshFloatingPetMenuItemTitle() {
		guard let builtMenu, builtMenu.items.count > 2 else { return }
		builtMenu.items[2].title = floatingPetToggleTitle()
	}

	@MainActor
	private func floatingPetToggleTitle() -> String {
		guard let floatingPetController else { return Self.showFloatingPetTitle }
		return floatingPetController.isFloatingPetVisible
			? Self.hideFloatingPetTitle
			: Self.showFloatingPetTitle
	}
}

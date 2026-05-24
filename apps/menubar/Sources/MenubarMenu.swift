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
/// The menu has exactly three items, in this order:
///   1. **Open log folder** — opens `~/.codogotchi/` via `NSWorkspace.open(_:)`.
///   2. **Reveal pet folder** — opens `~/.codex/pets/` via `NSWorkspace.open(_:)`.
///   3. **Quit Menubar** — terminates the app.
///
/// `MenubarMenu` is itself the action target for all items, so the caller
/// must retain it for the lifetime of the menu. `NSMenuItem.target` is a
/// weak reference (a known AppKit pitfall: dropping the target makes the
/// items "do nothing"), so `MenubarApp` holds a strong reference.
final class MenubarMenu: NSObject {
	static let openLogFolderTitle = "Open log folder"
	static let revealPetFolderTitle = "Reveal pet folder"
	static let quitTitle = "Quit Menubar"

	private let workspace: MenuWorkspaceOpening
	private let terminate: () -> Void
	private let logFolderURL: URL
	private let petFolderURL: URL
	private let fileManager: FileManager

	init(
		workspace: MenuWorkspaceOpening = NSWorkspace.shared,
		terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
		logFolderURL: URL = MenubarMenu.defaultLogFolderURL(),
		petFolderURL: URL = MenubarMenu.defaultPetFolderURL(),
		fileManager: FileManager = .default
	) {
		self.workspace = workspace
		self.terminate = terminate
		self.logFolderURL = logFolderURL
		self.petFolderURL = petFolderURL
		self.fileManager = fileManager
		super.init()
	}

	/// `~/.codogotchi/` — the canonical log folder used by `TransitionLog`
	/// and the live polling driver.
	static func defaultLogFolderURL() -> URL {
		FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi", isDirectory: true)
	}

	/// `~/.codex/pets/` — the Codex pets directory, surfaced via the
	/// "Reveal pet folder" menu item. The codogotchi sheet's directory
	/// (`~/.codogotchi/pets/`) is a supplemental asset path not shown here.
	static func defaultPetFolderURL() -> URL {
		FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codex", isDirectory: true)
			.appendingPathComponent("pets", isDirectory: true)
	}

	func build() -> NSMenu {
		let menu = NSMenu()

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

		let quitItem = NSMenuItem(
			title: Self.quitTitle,
			action: #selector(quitMenubar(_:)),
			keyEquivalent: "q"
		)
		quitItem.target = self
		menu.addItem(quitItem)

		return menu
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

	@objc func quitMenubar(_ sender: Any?) {
		terminate()
	}
}

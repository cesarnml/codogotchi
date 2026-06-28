import AppKit

/// Constructs the menu attached to the menu-bar `NSStatusItem`.
///
/// The pet section is dynamic: when `FloatingPetWindowPool` has a single active
/// origin it collapses to a single "Show/Hide Pet" toggle; with two or more
/// origins it expands to one "Hide <Platform> Pet" item per active origin.
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
	private weak var floatingPetPool: FloatingPetWindowPool?
	private let retryHooksInstall: (() -> Void)?
	private let openSettings: (() -> Void)?
	private weak var builtMenu: NSMenu?
	private weak var hooksNotActiveItem: NSMenuItem?
	/// Number of pet-section items currently at the top of `builtMenu`.
	private var petItemCount: Int = 0

	init(
		terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
		floatingPetPool: FloatingPetWindowPool? = nil,
		retryHooksInstall: (() -> Void)? = nil,
		openSettings: (() -> Void)? = nil
	) {
		self.terminate = terminate
		self.floatingPetPool = floatingPetPool
		self.retryHooksInstall = retryHooksInstall
		self.openSettings = openSettings
		super.init()
	}

	@MainActor
	func build() -> NSMenu {
		let menu = NSMenu()
		builtMenu = menu

		buildPetSection(in: menu)

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

	/// Rebuilds the pet section to reflect the current pool state.
	/// Called after any visibility change (panel hide button, menu action, pool TTL).
	@MainActor
	func refreshFloatingPetMenuItemTitle() {
		guard let menu = builtMenu else { return }
		// Remove current pet items (always at the front of the menu)
		for _ in 0..<petItemCount {
			menu.removeItem(at: 0)
		}
		petItemCount = 0
		buildPetSection(in: menu, insertAt: 0)
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

	// MARK: - Pet section

	@MainActor
	private func buildPetSection(in menu: NSMenu, insertAt index: Int? = nil) {
		let origins = floatingPetPool?.activeOrigins ?? []
		let items: [NSMenuItem]
		if origins.count > 1 {
			items = origins.map { origin in
				let item = NSMenuItem(
					title: "Hide \(displayName(for: origin)) Pet",
					action: #selector(hideFloatingPetForOrigin(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = origin
				return item
			}
		} else {
			let title: String
			let action: Selector?
			if origins.isEmpty {
				title = Self.showFloatingPetTitle
				action = nil
			} else {
				title = Self.hideFloatingPetTitle
				action = #selector(toggleSingleFloatingPet(_:))
			}
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.isEnabled = !origins.isEmpty
			items = [item]
		}

		if let index {
			for (offset, item) in items.enumerated() {
				menu.insertItem(item, at: index + offset)
			}
		} else {
			items.forEach { menu.addItem($0) }
		}
		petItemCount = items.count
	}

	@MainActor
	@objc private func toggleSingleFloatingPet(_ sender: Any?) {
		guard let pool = floatingPetPool, let origin = pool.activeOrigins.first else { return }
		pool.setVisible(false, for: origin)
		refreshFloatingPetMenuItemTitle()
	}

	@MainActor
	@objc private func hideFloatingPetForOrigin(_ sender: Any?) {
		guard let pool = floatingPetPool,
			let item = sender as? NSMenuItem,
			let origin = item.representedObject as? String
		else { return }
		pool.setVisible(false, for: origin)
		refreshFloatingPetMenuItemTitle()
	}

	private func displayName(for origin: String) -> String {
		switch origin {
		case "claude_code": return "Claude Code"
		case "cursor": return "Cursor"
		case "vscode": return "VS Code"
		case "codex": return "Codex"
		case "windsurf": return "Windsurf"
		case "antigravity": return "Antigravity"
		default: return origin.replacingOccurrences(of: "_", with: " ").capitalized
		}
	}
}

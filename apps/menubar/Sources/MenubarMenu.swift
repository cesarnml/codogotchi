import AppKit

/// Constructs the menu attached to the menu-bar `NSStatusItem`.
///
/// Layout: a disabled "Codogotchi" header, a separator, the dynamic pet
/// section, "Show/Hide All Pets", "Pets" (jumps to Settings > Pet),
/// "Customization" (jumps to Settings > Customization), "Settings", and
/// "Quit Codogotchi".
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
	static let headerTitle = "Codogotchi"
	static let showFloatingPetTitle = "Show Pet"
	static let hideFloatingPetTitle = "Hide Pet"
	static let showAllPetsTitle = "Show All Pets"
	static let hideAllPetsTitle = "Hide All Pets"
	static let petsTitle = "Pets"
	static let customizationTitle = "Customization"
	static let settingsTitle = "Settings"
	static let quitTitle = "Quit Codogotchi"
	static let hooksNotActiveTitle = "⚠ Hooks not active — Retry install"

	private let terminate: () -> Void
	private weak var floatingPetPool: FloatingPetWindowPool?
	private let retryHooksInstall: (() -> Void)?
	private let openSettings: ((SettingsTab?) -> Void)?
	private weak var builtMenu: NSMenu?
	private weak var hooksNotActiveItem: NSMenuItem?
	/// Index of the first pet-section item within `builtMenu` (after the header
	/// and separator).
	private var petSectionStartIndex: Int = 0
	/// Number of pet-section items currently at `petSectionStartIndex`.
	private var petItemCount: Int = 0

	init(
		terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
		floatingPetPool: FloatingPetWindowPool? = nil,
		retryHooksInstall: (() -> Void)? = nil,
		openSettings: ((SettingsTab?) -> Void)? = nil
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

		let header = NSMenuItem(title: Self.headerTitle, action: nil, keyEquivalent: "")
		header.isEnabled = false
		menu.addItem(header)
		menu.addItem(.separator())

		petSectionStartIndex = menu.numberOfItems
		buildPetSection(in: menu)

		menu.addItem(.separator())

		let showAllItem = NSMenuItem(
			title: Self.showAllPetsTitle,
			action: #selector(showAllPets(_:)),
			keyEquivalent: ""
		)
		showAllItem.target = self
		menu.addItem(showAllItem)

		let hideAllItem = NSMenuItem(
			title: Self.hideAllPetsTitle,
			action: #selector(hideAllPets(_:)),
			keyEquivalent: ""
		)
		hideAllItem.target = self
		menu.addItem(hideAllItem)

		menu.addItem(.separator())

		let petsItem = NSMenuItem(
			title: Self.petsTitle,
			action: #selector(openPetSettingsAction(_:)),
			keyEquivalent: ""
		)
		petsItem.target = self
		petsItem.isEnabled = openSettings != nil
		menu.addItem(petsItem)

		let customizationItem = NSMenuItem(
			title: Self.customizationTitle,
			action: #selector(openCustomizationSettingsAction(_:)),
			keyEquivalent: ""
		)
		customizationItem.target = self
		customizationItem.isEnabled = openSettings != nil
		menu.addItem(customizationItem)

		let settingsItem = NSMenuItem(
			title: Self.settingsTitle,
			action: #selector(openSettingsAction(_:)),
			keyEquivalent: ","
		)
		settingsItem.target = self
		settingsItem.isEnabled = openSettings != nil
		menu.addItem(settingsItem)

		menu.addItem(.separator())

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

	/// Rebuilds the pet section to reflect the current pool state. Called after
	/// any visibility change (panel hide button, menu action, pool TTL) or pet
	/// reassignment.
	@MainActor
	func refreshFloatingPetMenuItemTitle() {
		guard let menu = builtMenu else { return }
		for _ in 0..<petItemCount {
			menu.removeItem(at: petSectionStartIndex)
		}
		petItemCount = 0
		buildPetSection(in: menu, insertAt: petSectionStartIndex)
	}

	@objc func quitMenubar(_ sender: Any?) {
		terminate()
	}

	@objc func retryHooksInstallAction(_ sender: Any?) {
		retryHooksInstall?()
	}

	@objc func openSettingsAction(_ sender: Any?) {
		openSettings?(nil)
	}

	@objc func openPetSettingsAction(_ sender: Any?) {
		openSettings?(.pet)
	}

	@objc func openCustomizationSettingsAction(_ sender: Any?) {
		openSettings?(.customization)
	}

	@MainActor
	@objc func showAllPets(_ sender: Any?) {
		guard let pool = floatingPetPool else { return }
		for key in pool.hiddenWindowKeys {
			pool.setVisible(true, for: key)
		}
		refreshFloatingPetMenuItemTitle()
	}

	@MainActor
	@objc func hideAllPets(_ sender: Any?) {
		guard let pool = floatingPetPool else { return }
		for origin in pool.activeOrigins {
			pool.setVisible(false, for: origin)
		}
		refreshFloatingPetMenuItemTitle()
	}

	// MARK: - Pet section

	@MainActor
	private func buildPetSection(in menu: NSMenu, insertAt index: Int? = nil) {
		let active = floatingPetPool?.activeOrigins ?? []
		let hidden = floatingPetPool?.hiddenWindowKeys ?? []
		let items: [NSMenuItem]

		if active.count == 1 && hidden.isEmpty {
			// Single visible pet, nothing hidden: one "Hide Pet" toggle.
			let item = NSMenuItem(
				title: Self.hideFloatingPetTitle,
				action: #selector(toggleSingleFloatingPet(_:)),
				keyEquivalent: ""
			)
			item.target = self
			items = [item]
		} else if active.isEmpty && hidden.count == 1 {
			// Nothing visible, one hidden pet: single enabled "Show Pet".
			let item = NSMenuItem(
				title: Self.showFloatingPetTitle,
				action: #selector(showFloatingPetForKey(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = hidden[0]
			items = [item]
		} else if active.isEmpty && hidden.isEmpty {
			// No pool or no windows at all: disabled "Show Pet" placeholder.
			let item = NSMenuItem(title: Self.showFloatingPetTitle, action: nil, keyEquivalent: "")
			item.isEnabled = false
			items = [item]
		} else {
			// Multiple active and/or hidden: one item per window key.
			var all: [NSMenuItem] = []
			for origin in active {
				let item = NSMenuItem(
					title: "Hide \(displayName(for: origin)) Pet",
					action: #selector(hideFloatingPetForOrigin(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = origin
				all.append(item)
			}
			for key in hidden {
				let item = NSMenuItem(
					title: "Show \(displayName(for: key)) Pet",
					action: #selector(showFloatingPetForKey(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.representedObject = key
				all.append(item)
			}
			items = all
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

	@MainActor
	@objc private func showFloatingPetForKey(_ sender: Any?) {
		guard let pool = floatingPetPool,
			let item = sender as? NSMenuItem,
			let key = item.representedObject as? String
		else { return }
		pool.setVisible(true, for: key)
		refreshFloatingPetMenuItemTitle()
	}

	/// Display name for a pet-section window key. Session-keyed keys
	/// (`origin:session_id`) keep the platform prefix but replace the raw
	/// session UUID with the user's custom `SessionLabelStore` rename, or
	/// "Session N" from `SessionNumberAllocator` when no rename is set.
	/// Plain-origin keys (session pets off for that platform) are unaffected.
	@MainActor
	private func displayName(for key: String) -> String {
		let origin = FloatingPetWindowPool.origin(forWindowKey: key)
		let platformName = platformDisplayName(for: origin)
		guard let pool = floatingPetPool else { return platformName }
		if let label = pool.sessionLabel(forWindowKey: key), !label.isEmpty {
			return "\(platformName) - \(label)"
		}
		if let number = pool.sessionNumber(forWindowKey: key) {
			return "\(platformName) - Session \(number)"
		}
		return platformName
	}

	private func platformDisplayName(for origin: String) -> String {
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

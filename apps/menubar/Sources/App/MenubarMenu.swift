import AppKit

/// Constructs the menu attached to the menu-bar `NSStatusItem`.
///
/// Layout: a disabled "Codogotchi" header, a separator, the dynamic pet
/// section, "Show/Hide All Pets", "Pets" (jumps to Settings > Pet),
/// "Customization" (jumps to Settings > Customization), "Sessions" (jumps to
/// Settings > Sessions), "RPG" (jumps to Settings > RPG), "Settings", and
/// "Quit Codogotchi".
///
/// The pet section mirrors the Settings > Sessions lifecycle tiers (same
/// shared `SessionsTabViewModel`) instead of the pool's raw 24h hidden-key
/// horizon, so the two surfaces can never disagree about what counts as a
/// showable pet:
///
/// - A disabled **"Active Pets"** header, then one Show/Hide item per
///   `.active` row — rendered right now, or hidden (by the user or by the
///   "Hide Idle Pet After" idle-dismiss TTL) with a slice still inside the
///   reader's 2h fresh window. A single row collapses to a plain
///   "Show Pet"/"Hide Pet" title; multiple rows carry per-pet names.
/// - **"Live Pets ▸"**: `.live` rows minus cap-pending keys — fresh but
///   unrendered and not merely concealed (platform mode off, or folded into
///   Combined). Real per-row "Show" actions.
/// - **"Capped Sessions ▸"**: `.live` rows held back by the per-origin
///   session cap (`FloatingPetWindowPool.pendingSessionKeys`). Status-only
///   rows (a "Show" would be a silent no-op — the cap partition ignores the
///   hidden flag) plus an "Open Customization…" jump to raise the cap.
///
/// Archived slices (2h–24h) are deliberately absent here; Settings > Sessions
/// owns that bucket, including bulk Prune.
///
/// `MenubarMenu` is itself the action target for all items, so the caller
/// must retain it for the lifetime of the menu. `NSMenuItem.target` is a
/// weak reference (a known AppKit pitfall: dropping the target makes the
/// items "do nothing"), so `MenubarApp` holds a strong reference.
final class MenubarMenu: NSObject {
	static let headerTitle = "Codogotchi"
	static let activePetsSectionTitle = "Active Pets"
	static let showFloatingPetTitle = "Show Pet"
	static let hideFloatingPetTitle = "Hide Pet"
	static let livePetsTitle = "Live Pets"
	static let noLivePetsTitle = "No Live Sessions"
	static let cappedSessionsTitle = "Capped Sessions"
	static let noCappedSessionsTitle = "No Capped Sessions"
	static let openCustomizationTitle = "Open Customization…"
	static let showAllPetsTitle = "Show All Pets"
	static let hideAllPetsTitle = "Hide All Pets"
	static let petsTitle = "Pets"
	static let customizationTitle = "Customization"
	static let sessionsTitle = "Sessions"
	static let rpgTitle = "RPG"
	static let settingsTitle = "Settings"
	static let quitTitle = "Quit Codogotchi"
	static let hooksNotActiveTitle = "⚠ Hooks not active — Retry install"

	private let terminate: () -> Void
	private weak var floatingPetPool: FloatingPetWindowPool?
	/// Same `state.d/`-scan tier engine backing Settings → Sessions (shared
	/// instance, injected by `MenubarApp`): its `.active` rows (rendered or
	/// hidden-but-<2h) drive the top pet-section list, and its `.live` rows
	/// (fresh but unrendered — mode-off, combined-folded, or cap-pending)
	/// drive the "Live Pets"/"Capped Sessions" submenus. `nil` in tests that
	/// don't need the new tiering falls back to the pool's raw (unfiltered)
	/// active/hidden sets, matching pre-tiering behavior.
	private weak var sessionsTabViewModel: SessionsTabViewModel?
	private let retryHooksInstall: (() -> Void)?
	private let openSettings: ((SettingsTab?) -> Void)?
	/// Called with the window key just before an explicit "Show … Pet" /
	/// "Show All Pets" un-hide. Wired by `MenubarApp` to
	/// `StateJsonWriter.refreshForShow`, which restarts the dismiss-TTL clock
	/// on the backing slice(s) — without it, showing a pet whose slice has
	/// aged past the TTL while hidden is a silent no-op (the pool suppresses
	/// re-spawn of expired keys, so nothing appears).
	private let refreshTtlForShow: ((WindowKey) -> Void)?
	/// Called just before the menu opens. Wired by `MenubarApp` to the pool's
	/// `pruneHiddenKeysWithoutBackingSlice`, which drops hidden keys whose
	/// slice `SlicePruner` has already deleted from disk (24h horizon) —
	/// past that point there is genuinely nothing to show, so keeping the
	/// "Show … Pet" entry would be a misleading no-op button.
	private let pruneOrphanHiddenKeys: (() -> Void)?
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
		sessionsTabViewModel: SessionsTabViewModel? = nil,
		retryHooksInstall: (() -> Void)? = nil,
		openSettings: ((SettingsTab?) -> Void)? = nil,
		refreshTtlForShow: ((WindowKey) -> Void)? = nil,
		pruneOrphanHiddenKeys: (() -> Void)? = nil
	) {
		self.terminate = terminate
		self.floatingPetPool = floatingPetPool
		self.sessionsTabViewModel = sessionsTabViewModel
		self.retryHooksInstall = retryHooksInstall
		self.openSettings = openSettings
		self.refreshTtlForShow = refreshTtlForShow
		self.pruneOrphanHiddenKeys = pruneOrphanHiddenKeys
		super.init()
	}

	@MainActor
	func build() -> NSMenu {
		let menu = NSMenu()
		menu.delegate = self
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

		let sessionsItem = NSMenuItem(
			title: Self.sessionsTitle,
			action: #selector(openSessionsSettingsAction(_:)),
			keyEquivalent: ""
		)
		sessionsItem.target = self
		sessionsItem.isEnabled = openSettings != nil
		menu.addItem(sessionsItem)

		let rpgItem = NSMenuItem(
			title: Self.rpgTitle,
			action: #selector(openRPGSettingsAction(_:)),
			keyEquivalent: ""
		)
		rpgItem.target = self
		rpgItem.isEnabled = openSettings != nil
		menu.addItem(rpgItem)

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
		openSettings?(.general)
	}

	@objc func openPetSettingsAction(_ sender: Any?) {
		openSettings?(.pet)
	}

	@objc func openCustomizationSettingsAction(_ sender: Any?) {
		openSettings?(.customization)
	}

	@objc func openSessionsSettingsAction(_ sender: Any?) {
		openSettings?(.sessions)
	}

	@objc func openRPGSettingsAction(_ sender: Any?) {
		openSettings?(.rpg)
	}

	@MainActor
	@objc func showAllPets(_ sender: Any?) {
		guard let pool = floatingPetPool else { return }
		// Scoped to fresh rows the menu represents (Active + Live) when a view
		// model is wired, not every raw hidden key. Resolve source session rows
		// to their actual folded targets before intersecting hidden windows.
		let keys: Set<WindowKey>
		if let viewModel = sessionsTabViewModel {
			viewModel.refresh()
			let representedTargets = Set(
				(viewModel.activeRows.filter { !$0.isShown } + viewModel.liveRows)
					.map { pool.renderedWindowKey(for: $0.id) })
			keys = representedTargets.intersection(pool.hiddenWindowKeys)
		} else {
			keys = Set(pool.hiddenWindowKeys)
		}
		for key in keys {
			// Restart each key's dismiss-TTL clock before un-hiding, or a key
			// that expired while hidden would stay suppressed and never re-spawn.
			refreshTtlForShow?(key)
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

	/// Builds the "Active Pets" header + list, plus the "Live Pets" and
	/// "Capped Sessions" submenus. Active rows come from the shared
	/// `SessionsTabViewModel` when one is wired (its `.active` tier already
	/// implements the "rendered, or hidden but <2h old" contract agreed for
	/// the menu bar — see the file-level doc comment); with no view model
	/// (older call sites, most unit tests) this falls back to the pool's raw
	/// active/hidden sets, matching the pre-tiering behavior exactly.
	@MainActor
	private func buildPetSection(in menu: NSMenu, insertAt index: Int? = nil) {
		sessionsTabViewModel?.refresh()
		let activeRows: [SessionRow] = sessionsTabViewModel?.activeRows ?? fallbackActiveRows()
		let liveRows: [SessionRow] = sessionsTabViewModel?.liveRows ?? []
		let pendingKeys = floatingPetPool?.pendingSessionKeys ?? []
		let liveOnly = liveRows.filter { !pendingKeys.contains($0.id) }
		let cappedOnly = liveRows.filter { pendingKeys.contains($0.id) }

		var items: [NSMenuItem] = []

		let header = NSMenuItem(title: Self.activePetsSectionTitle, action: nil, keyEquivalent: "")
		header.isEnabled = false
		items.append(header)

		if activeRows.isEmpty {
			// No pool, or no windows/hidden keys at all: disabled placeholder.
			let item = NSMenuItem(title: Self.showFloatingPetTitle, action: nil, keyEquivalent: "")
			item.isEnabled = false
			items.append(item)
		} else if activeRows.count == 1 {
			items.append(activePetMenuItem(for: activeRows[0], titlePrefix: activeRows[0].sessionId != nil))
		} else {
			for row in activeRows {
				items.append(activePetMenuItem(for: row, titlePrefix: true))
			}
		}

		items.append(makeLivePetsItem(rows: liveOnly))
		items.append(makeCappedSessionsItem(rows: cappedOnly))

		if let index {
			for (offset, item) in items.enumerated() {
				menu.insertItem(item, at: index + offset)
			}
		} else {
			items.forEach { menu.addItem($0) }
		}
		petItemCount = items.count
	}

	/// Reconstructs the old pool-only (no view model) active/hidden row set,
	/// so call sites that never wire a `SessionsTabViewModel` — most existing
	/// unit tests — keep seeing every hidden key regardless of age, exactly
	/// as before this change.
	@MainActor
	private func fallbackActiveRows() -> [SessionRow] {
		guard let pool = floatingPetPool else { return [] }
		let active = pool.activeOrigins.map {
			SessionRow(
				id: $0, origin: $0.origin, sessionId: nil,
				displayLabel: $0.rawValue, tier: .active, isShown: true, ageSeconds: 0)
		}
		let hidden = pool.hiddenWindowKeys.map {
			SessionRow(
				id: $0, origin: $0.origin, sessionId: nil,
				displayLabel: $0.rawValue, tier: .active, isShown: false, ageSeconds: 0)
		}
		return active + hidden
	}

	@MainActor
	private func activePetMenuItem(for row: SessionRow, titlePrefix: Bool) -> NSMenuItem {
		let item: NSMenuItem
		if row.isShown {
			let title = titlePrefix ? "Hide \(displayName(for: row)) Pet" : Self.hideFloatingPetTitle
			item = NSMenuItem(title: title, action: #selector(hideFloatingPetForOrigin(_:)), keyEquivalent: "")
		} else {
			let title = titlePrefix ? "Show \(displayName(for: row)) Pet" : Self.showFloatingPetTitle
			item = NSMenuItem(title: title, action: #selector(showFloatingPetForKey(_:)), keyEquivalent: "")
		}
		item.target = self
		item.representedObject = row.id
		return item
	}

	/// Sessions fresh within the reader's 2h window but not rendered — mode
	/// disabled or folded into Combined. Each row offers a real "Show":
	/// unlike a capped session, nothing here is blocked by rank/cap
	/// contention, so un-hiding actually resurrects it.
	@MainActor
	private func makeLivePetsItem(rows: [SessionRow]) -> NSMenuItem {
		let item = NSMenuItem(title: Self.livePetsTitle, action: nil, keyEquivalent: "")
		let submenu = NSMenu()
		if rows.isEmpty {
			let empty = NSMenuItem(title: Self.noLivePetsTitle, action: nil, keyEquivalent: "")
			empty.isEnabled = false
			submenu.addItem(empty)
		} else {
			for row in rows.sorted(by: { $0.displayLabel < $1.displayLabel }) {
				let rowItem = NSMenuItem(
					title: "Show \(displayName(for: row)) Pet",
					action: #selector(showFloatingPetForKey(_:)),
					keyEquivalent: ""
				)
				rowItem.target = self
				rowItem.representedObject = row.id
				submenu.addItem(rowItem)
			}
		}
		item.submenu = submenu
		item.isEnabled = !rows.isEmpty
		return item
	}

	/// Sessions blocked from rendering by the per-origin session cap
	/// (`FloatingPetWindowPool.pendingSessionKeys`). Deliberately status-only:
	/// cap partitioning is re-ranked every tick independent of the hidden
	/// flag, so a "Show" button here would silently do nothing until the
	/// session wins the rank fight on its own. The way out is raising the
	/// cap, so the only action offered jumps straight to Customization.
	@MainActor
	private func makeCappedSessionsItem(rows: [SessionRow]) -> NSMenuItem {
		let item = NSMenuItem(title: Self.cappedSessionsTitle, action: nil, keyEquivalent: "")
		let submenu = NSMenu()
		if rows.isEmpty {
			let empty = NSMenuItem(title: Self.noCappedSessionsTitle, action: nil, keyEquivalent: "")
			empty.isEnabled = false
			submenu.addItem(empty)
		} else {
			for row in rows.sorted(by: { $0.displayLabel < $1.displayLabel }) {
				let status = NSMenuItem(
					title: "\(displayName(for: row)) — session cap reached",
					action: nil, keyEquivalent: ""
				)
				status.isEnabled = false
				submenu.addItem(status)
			}
			submenu.addItem(.separator())
			let openItem = NSMenuItem(
				title: Self.openCustomizationTitle,
				action: #selector(openCustomizationSettingsAction(_:)),
				keyEquivalent: ""
			)
			openItem.target = self
			openItem.isEnabled = openSettings != nil
			submenu.addItem(openItem)
		}
		item.submenu = submenu
		item.isEnabled = !rows.isEmpty
		return item
	}

	@MainActor
	@objc private func hideFloatingPetForOrigin(_ sender: Any?) {
		guard let pool = floatingPetPool,
			let item = sender as? NSMenuItem,
			let origin = item.representedObject as? WindowKey
		else { return }
		pool.setVisible(false, for: pool.renderedWindowKey(for: origin))
		refreshFloatingPetMenuItemTitle()
	}

	@MainActor
	@objc private func showFloatingPetForKey(_ sender: Any?) {
		guard let pool = floatingPetPool,
			let item = sender as? NSMenuItem,
			let key = item.representedObject as? WindowKey
		else { return }
		// A state.d row may fold into a plain-origin or Combined window. Show
		// the rendered target rather than clearing the source row's hidden flag.
		let renderedKey = pool.renderedWindowKey(for: key)
		// Restart the dismiss-TTL clock before un-hiding — see showAllPets.
		refreshTtlForShow?(renderedKey)
		pool.setVisible(true, for: renderedKey)
		refreshFloatingPetMenuItemTitle()
	}

	/// Display name for a pet-section window key. Session-keyed keys
	/// (`origin:session_id`) keep the platform prefix but replace the raw
	/// session UUID with the user's custom `SessionLabelStore` rename, the
	/// retrieved platform title, or "Session N" from `SessionNumberAllocator`.
	/// Plain-origin keys (session pets off for that platform) are unaffected.
	@MainActor
	private func displayName(for key: WindowKey) -> String {
		let origin = key.origin
		let platformName = platformDisplayName(for: origin)
		guard let pool = floatingPetPool else { return platformName }
		if key.sessionIdentity != nil,
			let label = pool.sessionDisplayLabel(forWindowKey: key, origin: origin),
			!label.isEmpty
		{
			return "\(platformName) - \(label)"
		}
		if let label = pool.sessionLabel(forWindowKey: key), !label.isEmpty {
			return "\(platformName) - \(label)"
		}
		return platformName
	}

	@MainActor
	private func displayName(for row: SessionRow) -> String {
		guard sessionsTabViewModel != nil else { return displayName(for: row.id) }
		let platformName = platformDisplayName(for: row.origin)
		guard !row.displayLabel.isEmpty, row.displayLabel != platformName else { return platformName }
		return "\(platformName) - \(row.displayLabel)"
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

extension MenubarMenu: NSMenuDelegate {
	/// Refresh the pet section at the moment the dropdown is about to
	/// display: first cull hidden keys whose backing slice is gone from disk
	/// (their "Show" entries would be misleading no-op buttons), then rebuild
	/// the section so it reflects the pool's current state — visibility can
	/// have changed since the last explicit refresh (TTL dismissals, slice
	/// pruning) without any menu action having run.
	func menuWillOpen(_ menu: NSMenu) {
		guard menu === builtMenu else { return }
		pruneOrphanHiddenKeys?()
		refreshFloatingPetMenuItemTitle()
	}
}

import AppKit

/// Shows the Settings window — a standard macOS window (not an `NSPanel`) with
/// seven selectable tabs:
/// - **General**: per-platform hook install/uninstall/status; Cursor native-hook note.
/// - **Pet**: list + select pets from `~/.codogotchi/pets/`; import from `~/.codex/pets/`.
/// - **Customization**: per-platform mode pickers and idle-dismiss TTL.
/// - **Sessions**: `state.d/` slices bucketed into Active/Live/Archived lifecycle tiers.
/// - **RPG**: HUD opt-out toggle.
/// - **Developer**: read-only observability.
/// - **About**: app version, bundled hook-binary version, and product links.
///
/// Tab order and selection state live in the AppKit-free `SettingsTabModel` so
/// they are unit-testable; this controller owns the `NSTabView` chrome and keeps
/// the model in sync with user selection.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTabViewDelegate {
	static let windowTitle = "Codogotchi Settings"

	private var window: NSWindow?
	private var generalTab: GeneralTabView?
	private var petTab: PetTabView?
	private weak var tabView: NSTabView?
	private weak var tabStripView: TabStripView?
	private let tabModel = SettingsTabModel()
	private let generalViewModel: GeneralTabViewModel
	private let petTabViewModel: PetTabViewModel
	private let rpgTabViewModel: RPGTabViewModel
	private let customizationTabViewModel: CustomizationTabViewModel
	private let sessionsTabViewModel: SessionsTabViewModel
	private weak var sessionsTab: SessionsTabView?

	private let settingsController: SettingsController
	private let petImportHelper: PetImportHelper
	private let aboutViewModel: AboutViewModel
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void

	/// Called when the user activates a pet in the Pet tab. Receives the new pet ID.
	/// Wire this in `MenubarApp` to reload pet loaders and push a fresh frame.
	var onPetActivated: ((String) -> Void)?

	/// Called when the user changes the RPG HUD mode picker. Receives the
	/// persisted mode. Wire this in `MenubarApp` to push HUD visibility to the
	/// floating pet(s) live, so the change takes effect without an app restart.
	var onRPGHUDModeChanged: ((PetConfig.RPGHUDMode) -> Void)?

	/// Called when the user toggles "Monochrome menu bar icon". Receives the new
	/// state. Wire this in `MenubarApp` to toggle `image.isTemplate` on the status item.
	var onMonochromeChanged: ((Bool) -> Void)?

	init(
		settingsController: SettingsController = SettingsController(),
		petImportHelper: PetImportHelper = PetImportHelper(),
		petTabViewModel: PetTabViewModel = PetTabViewModel(),
		rpgTabViewModel: RPGTabViewModel = RPGTabViewModel(),
		customizationTabViewModel: CustomizationTabViewModel = CustomizationTabViewModel(),
		sessionsTabViewModel: SessionsTabViewModel = SessionsTabViewModel(),
		aboutViewModel: AboutViewModel = AboutViewModel(),
		generalViewModel: GeneralTabViewModel = GeneralTabViewModel(),
		appStateLoader: @escaping () -> FloatingAppState = {
			AppStateStore.load(visibleFrame: NSScreen.main?.visibleFrame ?? .zero)
		},
		appStateSaver: @escaping (FloatingAppState) throws -> Void = AppStateStore.save
	) {
		self.settingsController = settingsController
		self.petImportHelper = petImportHelper
		self.petTabViewModel = petTabViewModel
		self.rpgTabViewModel = rpgTabViewModel
		self.customizationTabViewModel = customizationTabViewModel
		self.sessionsTabViewModel = sessionsTabViewModel
		self.aboutViewModel = aboutViewModel
		self.generalViewModel = generalViewModel
		self.appStateLoader = appStateLoader
		self.appStateSaver = appStateSaver
	}

	/// Opens (or brings to front) the settings window. Pass `tab` to land on a
	/// specific tab (e.g. the menu-bar "Pets" item jumps to `.pet`).
	func show(tab: SettingsTab? = nil) {
		// Mirror Tailscale's Settings window: the app runs as `.accessory` (no
		// Dock icon, absent from Cmd+Tab) while only the menu-bar item is up,
		// but gains a normal app presence — Dock icon + Cmd+Tab entry — for as
		// long as this window is open, reverting in `windowWillClose`.
		NSApp.setActivationPolicy(.regular)
		if let tab {
			tabModel.select(tab)
		}
		if let existing = window {
			existing.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			if let tab {
				tabView?.selectTabViewItem(at: tab.rawValue)
			}
			return
		}
		openWindow()
	}

	/// Refreshes the General tab with a fresh hook-status snapshot.
	func updateHookStatus(_ snapshot: HooksStatusSnapshot) {
		generalViewModel.applySnapshot(snapshot)
		generalTab?.applyViewModel(generalViewModel)
	}

	// MARK: - NSWindowDelegate

	func windowWillClose(_ notification: Notification) {
		window = nil
		generalTab = nil
		petTab = nil
		tabView = nil
		tabStripView = nil
		sessionsTab = nil
		// Drop back to a menu-bar-only presence — no Dock icon, no Cmd+Tab entry —
		// now that Settings is gone. Any other visible window (onboarding, floating
		// pet panels) does not require `.regular`, so this always reverts cleanly.
		NSApp.setActivationPolicy(.accessory)
	}

	// MARK: - NSTabViewDelegate

	func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
		guard
			let identifier = tabViewItem?.identifier as? Int,
			let tab = SettingsTab(rawValue: identifier)
		else { return }
		tabModel.select(tab)
		tabStripView?.setSelected(tab)
	}

	// MARK: - Private

	private func openWindow() {
		// Fixed window size: width shows three Pet-grid columns by default
		// (each card needs ~300pt; see PetTabView.minCardWidth/maxColumns) with
		// headroom for the Customization tab's two-column layout; height fits
		// the Customization tab's bottom row of idle/eviction cards. The
		// window is not resizable — every tab is designed against this size.
		let frame = CGRect(x: 0, y: 0, width: 1120, height: 770)
		let w = NSWindow(
			contentRect: frame,
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		w.title = Self.windowTitle
		// The Settings design is a fixed dark-navy theme (mockup-approved), not a
		// light/dark adaptive one — force dark appearance so semantic colors
		// resolve correctly on the navy background in either system mode.
		w.appearance = NSAppearance(named: .darkAqua)
		w.backgroundColor = SettingsTheme.windowBackground
		// Blend the title bar into the navy theme: a transparent titlebar draws
		// the window background color behind the traffic lights and title text
		// instead of the system's opaque gray chrome.
		w.titlebarAppearsTransparent = true
		w.isReleasedWhenClosed = false
		w.delegate = self
		w.center()

		let savedState = appStateLoader()
		generalViewModel.installedHookVersion = savedState.installedHookVersion
		if let snap = savedState.hooksStatus {
			generalViewModel.applySnapshot(snap)
		} else {
			generalViewModel.refresh()
		}

		let general = GeneralTabView(
			viewModel: generalViewModel,
			onInstallHooks: { [weak self] in self?.handleInstallHooks() },
			onUpdateHooks: { [weak self] in self?.handleUpdateHooks() },
			onUninstallHooks: { [weak self] in self?.handleUninstallHooks() }
		)
		general.onMonochromeToggled = { [weak self] isMonochrome in
			let persisted = self?.generalViewModel.setMonochromeMenubarIcon(isMonochrome) ?? false
			if persisted { self?.onMonochromeChanged?(isMonochrome) }
		}
		general.onRequirePruneConfirmationToggled = { [weak self] requireConfirmation in
			self?.generalViewModel.setRequirePruneConfirmation(requireConfirmation)
		}
		let pet = PetTabView(
			viewModel: petTabViewModel,
			onImportPet: { [weak self] petId in self?.handleImportPet(id: petId) }
		)
		let customization = CustomizationTabView(viewModel: customizationTabViewModel)
		sessionsTabViewModel.refresh()
		let sessions = SessionsTabView(
			viewModel: sessionsTabViewModel, customizationTabViewModel: customizationTabViewModel)
		let rpg = RPGTabView(
			viewModel: rpgTabViewModel,
			onHUDModeChanged: { [weak self] mode in
				guard let self else { return }
				self.rpgTabViewModel.setHUDMode(mode)
				// Fire with the *persisted* value: `setHUDMode` reverts on a failed
				// write, so the live HUD must track what survives a relaunch.
				self.onRPGHUDModeChanged?(self.rpgTabViewModel.hudMode)
			}
		)
		petTabViewModel.onAssignmentsChanged = { [weak self, weak rpg] in
			guard let self else { return }
			self.rpgTabViewModel.refresh()
			rpg?.reload(viewModel: self.rpgTabViewModel)
			self.onPetActivated?(self.petTabViewModel.assignmentsSnapshot.default)
		}
		let developerViewModel = makeDeveloperTabViewModel()
		let developer = DeveloperTabView(viewModel: developerViewModel)
		let about = AboutTabView(viewModel: aboutViewModel)

		let tabView = NSTabView()
		// Native tab chrome is replaced by `TabStripView` below — `.topTabsBezelBorder`
		// only offers plain-label tabs (`NSTabViewItem.image` doesn't render in that
		// style), so the mockup's icon + colored-pill tab strip needs a custom control
		// driving `NSTabView` selection programmatically instead.
		tabView.tabViewType = .noTabsNoBorder
		tabView.translatesAutoresizingMaskIntoConstraints = false

		for (tab, view): (SettingsTab, NSView) in [
			(.general, general),
			(.pet, pet),
			(.customization, customization),
			(.sessions, sessions),
			(.rpg, rpg),
			(.developer, developer),
			(.about, about),
		] {
			let item = NSTabViewItem(identifier: tab.rawValue)
			item.label = tab.title
			item.view = view
			tabView.addTabViewItem(item)
		}

		let tabStrip = TabStripView(tabs: SettingsTab.allCases)
		tabStrip.translatesAutoresizingMaskIntoConstraints = false
		tabStrip.onSelect = { [weak self, weak tabView, weak rpg, weak sessions] tab in
			if tab == .rpg {
				self?.rpgTabViewModel.refresh()
				if let viewModel = self?.rpgTabViewModel {
					rpg?.reload(viewModel: viewModel)
				}
			}
			if tab == .sessions {
				// Disk state (and the pool's active/hidden window keys) can have
				// changed since the tab was last built — re-scan on every visit
				// rather than only once at window-open time.
				self?.sessionsTabViewModel.refresh()
				if let viewModel = self?.sessionsTabViewModel {
					sessions?.reload(viewModel: viewModel)
				}
			}
			tabView?.selectTabViewItem(at: tab.rawValue)
		}

		let container = NSView(frame: frame)
		container.wantsLayer = true
		container.layer?.backgroundColor = SettingsTheme.windowBackground.cgColor
		container.addSubview(tabStrip)
		container.addSubview(tabView)
		NSLayoutConstraint.activate([
			tabStrip.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
			tabStrip.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			tabStrip.leadingAnchor.constraint(
				greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
			tabStrip.trailingAnchor.constraint(
				lessThanOrEqualTo: container.trailingAnchor, constant: -12),
			tabView.topAnchor.constraint(equalTo: tabStrip.bottomAnchor, constant: 12),
			tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
			tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
			tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
		])
		w.contentView = container
		// Adding tab view items above auto-selects the first one, which would fire
		// the delegate and reset `tabModel.selected` back to `.general` if the
		// delegate were already wired. Select the real target, then attach the
		// delegate so subsequent user-driven tab clicks are tracked correctly.
		tabView.selectTabViewItem(at: tabModel.selected.rawValue)
		tabStrip.setSelected(tabModel.selected)
		tabView.delegate = self

		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.window = w
		self.generalTab = general
		self.petTab = pet
		self.tabView = tabView
		self.tabStripView = tabStrip
		self.sessionsTab = sessions
	}

	private func handleInstallHooks() {
		generalTab?.setHooksWorking(message: "Installing…")
		let controller = settingsController
		let vm = generalViewModel
		let hookVersion = aboutViewModel.hookVersion
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksInstall()
			vm.refresh()
			if error == nil {
				self?.recordInstalledHookVersion(hookVersion, into: vm)
			}
			DispatchQueue.main.async {
				guard let self else { return }
				self.generalTab?.applyViewModel(vm)
				if let msg = error {
					self.generalTab?.setHooksError(msg)
				} else {
					self.generalTab?.setHooksSuccess(message: "Installed.")
				}
			}
		}
	}

	private func handleUpdateHooks() {
		generalTab?.setHooksWorking(message: "Updating…")
		let controller = settingsController
		let vm = generalViewModel
		let hookVersion = aboutViewModel.hookVersion
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksUpdate()
			vm.refresh()
			if error == nil {
				self?.recordInstalledHookVersion(hookVersion, into: vm)
			}
			DispatchQueue.main.async {
				guard let self else { return }
				self.generalTab?.applyViewModel(vm)
				if let msg = error {
					self.generalTab?.setHooksError(msg)
				} else {
					self.generalTab?.setHooksSuccess(message: "Updated.")
				}
			}
		}
	}

	private func recordInstalledHookVersion(_ version: String, into vm: GeneralTabViewModel) {
		guard version != "unknown" else { return }
		let current = appStateLoader()
		let updated = FloatingAppState(
			isFloatingPetVisible: current.isFloatingPetVisible,
			frame: current.frame,
			onboardingCompletedAt: current.onboardingCompletedAt,
			lastHookActivityAt: current.lastHookActivityAt,
			hooksStatus: current.hooksStatus,
			installedHookVersion: version
		)
		do {
			try appStateSaver(updated)
			vm.installedHookVersion = version
		} catch {
			NSLog("SettingsWindowController: failed to persist installedHookVersion — %@", error.localizedDescription)
		}
	}

	private func handleUninstallHooks() {
		generalTab?.setHooksWorking(message: "Uninstalling…")
		let controller = settingsController
		let vm = generalViewModel
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksUninstall()
			vm.refresh()
			DispatchQueue.main.async {
				guard let self else { return }
				self.generalTab?.applyViewModel(vm)
				if let msg = error {
					self.generalTab?.setHooksError(msg)
				} else {
					self.generalTab?.setHooksSuccess(message: "Uninstalled.")
				}
			}
		}
	}

	private func handleImportPet(id: String) {
		do {
			try petTabViewModel.importPet(id: id)
			petTab?.setPetImportSuccess(petId: id)
			petTab?.refreshPetList(viewModel: petTabViewModel)
		} catch {
			petTab?.setPetImportError(String(describing: error))
		}
	}

	private func makeDeveloperTabViewModel() -> DeveloperTabViewModel {
		let home = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
		let stateDirPath = home.appendingPathComponent("state.d").path
		let gateJsonPath = home.appendingPathComponent("gate.json").path
		let deliveryContextPath = home.appendingPathComponent("delivery-context.json").path
		let logPath = TransitionLog.defaultPath().path
		let snapshot = appStateLoader().hooksStatus
		return DeveloperTabViewModel(
			stateDirPath: stateDirPath,
			gateJsonPath: gateJsonPath,
			deliveryContextPath: deliveryContextPath,
			transitionLogPath: logPath,
			hooksSnapshot: snapshot
		)
	}
}

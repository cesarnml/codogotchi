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

// MARK: - SettingsTheme

/// Fixed dark-navy palette for the Settings window, matching the approved
/// mockup. Applied window-wide (all six tabs) via the window's forced
/// `.darkAqua` appearance + these background layers; system semantic colors
/// (`labelColor` etc.) resolve against the dark appearance on top of it.
private enum SettingsTheme {
	static let windowBackground = NSColor(srgbRed: 0.043, green: 0.063, blue: 0.102, alpha: 1)  // #0B101A
	static let cardBackground = NSColor(srgbRed: 0.071, green: 0.098, blue: 0.153, alpha: 1)  // #121927
	static let tableBackground = NSColor(srgbRed: 0.055, green: 0.078, blue: 0.125, alpha: 1)  // #0E1420
	static let buttonBackground = NSColor(srgbRed: 0.098, green: 0.133, blue: 0.204, alpha: 1)  // #192234
	static let cardBorder = NSColor.white.withAlphaComponent(0.08)
	static let rowDivider = NSColor.white.withAlphaComponent(0.06)
}

// MARK: - TabStripView

/// Custom icon + label tab strip replacing native `NSTabViewItem` tabs, which
/// only render plain labels in `.topTabsBezelBorder` style (`.image` is a
/// segmented/toolbar-tab-only behavior). Drives `NSTabView` selection via
/// `onSelect`; the owning controller keeps `setSelected` in sync with
/// programmatic and delegate-driven selection changes.
private final class TabStripView: NSView {
	private var buttons: [SettingsTab: NSButton] = [:]
	private var pills: [SettingsTab: NSView] = [:]
	var onSelect: ((SettingsTab) -> Void)?

	init(tabs: [SettingsTab]) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false

		let stack = NSStackView()
		stack.orientation = .horizontal
		stack.spacing = 4
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		for tab in tabs {
			let button = NSButton(
				title: tab.title, target: self, action: #selector(tabTapped(_:)))
			button.tag = tab.rawValue
			button.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
			button.imagePosition = .imageLeading
			button.isBordered = false
			button.font = .systemFont(ofSize: 13, weight: .medium)

			// The pill background lives on a wrapper view, not the button itself,
			// so horizontal padding is real layout (leading/trailing constraints)
			// rather than literal spaces baked into the title string.
			let pill = NSView()
			pill.translatesAutoresizingMaskIntoConstraints = false
			pill.wantsLayer = true
			pill.layer?.cornerRadius = 6
			button.translatesAutoresizingMaskIntoConstraints = false
			pill.addSubview(button)
			NSLayoutConstraint.activate([
				pill.heightAnchor.constraint(equalToConstant: 32),
				button.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
				button.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
				button.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
				button.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
			])
			stack.addArrangedSubview(pill)
			buttons[tab] = button
			pills[tab] = pill
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	@objc private func tabTapped(_ sender: NSButton) {
		guard let tab = SettingsTab(rawValue: sender.tag) else { return }
		onSelect?(tab)
		setSelected(tab)
	}

	func setSelected(_ tab: SettingsTab) {
		for (t, pill) in pills {
			let isSelected = t == tab
			pill.layer?.backgroundColor =
				isSelected ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
			buttons[t]?.contentTintColor = isSelected ? .white : .secondaryLabelColor
		}
	}
}

// MARK: - Shared helpers

private func settingsSectionTitle(_ text: String) -> NSTextField {
	let label = NSTextField(labelWithString: text)
	label.font = .systemFont(ofSize: 13, weight: .semibold)
	label.textColor = .labelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	return label
}

private func settingsBodyLabel(_ text: String) -> NSTextField {
	let label = NSTextField(wrappingLabelWithString: text)
	label.isEditable = false
	label.isBordered = false
	label.backgroundColor = .clear
	label.font = .systemFont(ofSize: 12)
	label.textColor = .secondaryLabelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	return label
}

/// Rounded square icon badge used in section headers (the Hooks card treatment,
/// reused by every tab's wrapper card and inner panels to unify the design
/// language). `side` 32 for tab-level headers, 24 for inner panel titles.
private func settingsHeaderIconBadge(
	symbolName: String, color: NSColor, side: CGFloat = 32
) -> NSView {
	let badge = NSView()
	badge.translatesAutoresizingMaskIntoConstraints = false
	badge.wantsLayer = true
	badge.layer?.cornerRadius = side / 4
	badge.layer?.backgroundColor = color.cgColor

	let glyph = NSImageView()
	glyph.translatesAutoresizingMaskIntoConstraints = false
	glyph.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
	glyph.contentTintColor = .white
	glyph.imageScaling = .scaleProportionallyUpOrDown
	badge.addSubview(glyph)

	NSLayoutConstraint.activate([
		badge.widthAnchor.constraint(equalToConstant: side),
		badge.heightAnchor.constraint(equalToConstant: side),
		glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
		glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
		glyph.widthAnchor.constraint(equalToConstant: side / 2),
		glyph.heightAnchor.constraint(equalToConstant: side / 2),
	])
	return badge
}

/// Themed card container matching the General tab's Hooks card, so every
/// tab's content sits in the same navy panel treatment.
private func settingsThemedCard() -> NSView {
	let card = NSView()
	card.translatesAutoresizingMaskIntoConstraints = false
	card.wantsLayer = true
	card.layer?.cornerRadius = 10
	card.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
	card.layer?.borderWidth = 1
	card.layer?.borderColor = SettingsTheme.cardBorder.cgColor
	return card
}

/// Small caps-style column header, used above per-platform table rows
/// (Platform Settings card).
private func settingsColumnHeader(_ text: String) -> NSTextField {
	let label = NSTextField(labelWithString: text)
	label.font = .systemFont(ofSize: 11, weight: .semibold)
	label.textColor = .secondaryLabelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	// Callers that pass an embedded "\n" (e.g. a two-line "Enable\nSessions"
	// header squeezed into a narrow column) need actual line breaks, not a
	// single-line label that ignores them.
	label.maximumNumberOfLines = 0
	label.lineBreakMode = .byWordWrapping
	return label
}

// MARK: - GeneralTabView (Hooks)

/// General tab — per-platform hook status table, Install/Update/Remove/Copy
/// diagnostics strip directly beneath it, then a single dynamic status panel
/// (idle/stale/new-tool-detected, or in-flight action feedback), then the
/// menu-bar-icon toggle row, all inside one themed card.
private final class GeneralTabView: NSView {
	private var hookRows: [HookRowView] = []
	private let hookRowsStack = NSStackView()
	private let installButton = NSButton(title: "Install hooks", target: nil, action: nil)
	private let updateButton = NSButton(title: "Update hooks", target: nil, action: nil)
	private let removeButton = NSButton(title: "Remove hooks", target: nil, action: nil)
	private let copyDiagnosticsButton = NSButton(
		title: "Copy diagnostics", target: nil, action: nil
	)
	private let statusPanel = DynamicStatusPanelView()
	private let hookTableContainer = NSView()
	private let monochromeSwitch = NSSwitch()
	private let requirePruneConfirmationSwitch = NSSwitch()

	private let onInstallHooks: () -> Void
	private let onUpdateHooks: () -> Void
	private let onUninstallHooks: () -> Void
	var onMonochromeToggled: ((Bool) -> Void)?
	var onRequirePruneConfirmationToggled: ((Bool) -> Void)?
	private var viewModel: GeneralTabViewModel

	init(
		viewModel: GeneralTabViewModel,
		onInstallHooks: @escaping () -> Void,
		onUpdateHooks: @escaping () -> Void,
		onUninstallHooks: @escaping () -> Void
	) {
		self.viewModel = viewModel
		self.onInstallHooks = onInstallHooks
		self.onUpdateHooks = onUpdateHooks
		self.onUninstallHooks = onUninstallHooks
		super.init(frame: .zero)
		setupViews()
		applyViewModel(viewModel)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func applyViewModel(_ vm: GeneralTabViewModel) {
		viewModel = vm
		rebuildHookRows(vm.rows)
		statusPanel.state = vm.shouldShowUpdateBanner
			? .attention(vm.updateBannerMessage)
			: .upToDate
		monochromeSwitch.state = vm.menubarIconMonochrome ? .on : .off
		requirePruneConfirmationSwitch.state = vm.requirePruneConfirmation ? .on : .off
	}

	func setHooksWorking(message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = false }
		statusPanel.state = .working(message)
	}

	func setHooksSuccess(message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = true }
		statusPanel.state = .success(message)
	}

	func setHooksError(_ message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = true }
		statusPanel.state = .error(message)
	}

	private func setupViews() {
		// Prevent unsatisfiable-constraint log when the view is constructed at
		// .zero before joining the window hierarchy. The real fixed window width
		// (1120pt) wins once the view is in the superview chain.
		let floor = widthAnchor.constraint(greaterThanOrEqualToConstant: 460)
		floor.priority = .defaultHigh
		floor.isActive = true

		// Card groups the Hooks section as one unit on the navy window background
		// (see `SettingsTheme` for the mockup palette).
		let card = NSView()
		card.translatesAutoresizingMaskIntoConstraints = false
		card.wantsLayer = true
		card.layer?.cornerRadius = 10
		card.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
		card.layer?.borderWidth = 1
		card.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		addSubview(card)

		let iconBadge = NSView()
		iconBadge.translatesAutoresizingMaskIntoConstraints = false
		iconBadge.wantsLayer = true
		iconBadge.layer?.cornerRadius = 8
		iconBadge.layer?.backgroundColor = NSColor.systemIndigo.cgColor
		card.addSubview(iconBadge)

		let iconGlyph = NSImageView()
		iconGlyph.translatesAutoresizingMaskIntoConstraints = false
		iconGlyph.image = NSImage(
			systemSymbolName: "puzzlepiece.fill", accessibilityDescription: nil)
		iconGlyph.contentTintColor = .white
		iconGlyph.imageScaling = .scaleProportionallyUpOrDown
		iconBadge.addSubview(iconGlyph)

		let title = settingsSectionTitle("Hooks")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		let subtitleNote = settingsBodyLabel(
			"Connects Codogotchi to your coding tools so it can react to what you're doing."
		)
		card.addSubview(subtitleNote)

		// Rows live in a shaded, bordered strip (mockup's table treatment);
		// hairline dividers are drawn per-row in `HookRowView`.
		hookTableContainer.translatesAutoresizingMaskIntoConstraints = false
		hookTableContainer.wantsLayer = true
		hookTableContainer.layer?.cornerRadius = 8
		hookTableContainer.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		hookTableContainer.layer?.borderWidth = 1
		hookTableContainer.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		card.addSubview(hookTableContainer)

		hookRowsStack.orientation = .vertical
		hookRowsStack.spacing = 0
		// NSStackView has no `.fill` alignment for a vertical stack — `.leading`
		// plus an explicit width constraint per arranged row (in
		// `rebuildHookRows`) is what actually stretches each row to the stack's
		// width.
		hookRowsStack.alignment = .leading
		hookRowsStack.translatesAutoresizingMaskIntoConstraints = false
		hookTableContainer.addSubview(hookRowsStack)

		let buttonSpecs: [(NSButton, String, String, NSColor)] = [
			(installButton, "Install hooks", "square.and.arrow.down", .systemBlue),
			(updateButton, "Update hooks", "arrow.triangle.2.circlepath", .systemBlue),
			(removeButton, "Remove hooks", "trash", .systemRed),
			(copyDiagnosticsButton, "Copy diagnostics", "doc.on.clipboard", .systemPurple),
		]
		for (btn, buttonTitle, symbol, tint) in buttonSpecs {
			// Borderless custom-drawn buttons: the standard `.rounded` bezel caps
			// out visually short and can't take the mockup's dark fill. Content
			// (icon + label) centers within each equal-width button.
			btn.isBordered = false
			btn.wantsLayer = true
			btn.layer?.backgroundColor = SettingsTheme.buttonBackground.cgColor
			btn.layer?.cornerRadius = 8
			btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
				.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
			btn.imagePosition = .imageLeading
			// Without this, a wide borderless button pins the image to its leading
			// edge and centers only the title; hugging keeps icon+label together
			// as one centered cluster.
			btn.imageHugsTitle = true
			btn.contentTintColor = tint
			btn.attributedTitle = NSAttributedString(
				string: " " + buttonTitle,
				attributes: [
					.foregroundColor: NSColor.labelColor,
					.font: NSFont.systemFont(ofSize: 13, weight: .medium),
				])
			btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
		}
		installButton.target = self
		installButton.action = #selector(installTapped)
		updateButton.target = self
		updateButton.action = #selector(updateTapped)
		removeButton.target = self
		removeButton.action = #selector(removeTapped)
		copyDiagnosticsButton.target = self
		copyDiagnosticsButton.action = #selector(copyDiagnosticsTapped)

		// Single strip: Install / Update / Remove / Copy diagnostics together,
		// directly beneath the table — the controls that act on it live right
		// next to what they act on, instead of below a wall of text.
		let actionRow = NSStackView(views: [
			installButton, updateButton, removeButton, copyDiagnosticsButton,
		])
		actionRow.orientation = .horizontal
		actionRow.spacing = 8
		actionRow.distribution = .fillEqually
		actionRow.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(actionRow)

		statusPanel.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(statusPanel)

		monochromeSwitch.target = self
		monochromeSwitch.action = #selector(monochromeToggleChanged)
		monochromeSwitch.translatesAutoresizingMaskIntoConstraints = false

		// Monochrome row per the mockup: icon badge + title/subtitle on the left,
		// a switch on the right, in its own shaded strip at the card's bottom.
		let monoRow = NSView()
		monoRow.translatesAutoresizingMaskIntoConstraints = false
		monoRow.wantsLayer = true
		monoRow.layer?.cornerRadius = 8
		monoRow.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		card.addSubview(monoRow)

		let monoBadge = NSView()
		monoBadge.translatesAutoresizingMaskIntoConstraints = false
		monoBadge.wantsLayer = true
		monoBadge.layer?.cornerRadius = 6
		monoBadge.layer?.backgroundColor = SettingsTheme.buttonBackground.cgColor
		monoRow.addSubview(monoBadge)

		let monoGlyph = NSImageView()
		monoGlyph.translatesAutoresizingMaskIntoConstraints = false
		monoGlyph.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
		monoGlyph.contentTintColor = .secondaryLabelColor
		monoGlyph.imageScaling = .scaleProportionallyUpOrDown
		monoBadge.addSubview(monoGlyph)

		let monoTitle = NSTextField(labelWithString: "Monochrome menu bar icon")
		monoTitle.font = .systemFont(ofSize: 13, weight: .medium)
		monoTitle.translatesAutoresizingMaskIntoConstraints = false
		monoRow.addSubview(monoTitle)

		let monoSubtitle = NSTextField(
			labelWithString: "Use a monochrome icon in the macOS menu bar.")
		monoSubtitle.font = .systemFont(ofSize: 11)
		monoSubtitle.textColor = .secondaryLabelColor
		monoSubtitle.translatesAutoresizingMaskIntoConstraints = false
		monoRow.addSubview(monoSubtitle)

		monoRow.addSubview(monochromeSwitch)

		NSLayoutConstraint.activate([
			monoBadge.leadingAnchor.constraint(equalTo: monoRow.leadingAnchor, constant: 14),
			monoBadge.centerYAnchor.constraint(equalTo: monoRow.centerYAnchor),
			monoBadge.widthAnchor.constraint(equalToConstant: 28),
			monoBadge.heightAnchor.constraint(equalToConstant: 28),

			monoGlyph.centerXAnchor.constraint(equalTo: monoBadge.centerXAnchor),
			monoGlyph.centerYAnchor.constraint(equalTo: monoBadge.centerYAnchor),
			monoGlyph.widthAnchor.constraint(equalToConstant: 14),
			monoGlyph.heightAnchor.constraint(equalToConstant: 14),

			monoTitle.leadingAnchor.constraint(equalTo: monoBadge.trailingAnchor, constant: 12),
			monoTitle.topAnchor.constraint(equalTo: monoRow.topAnchor, constant: 10),

			monoSubtitle.leadingAnchor.constraint(equalTo: monoTitle.leadingAnchor),
			monoSubtitle.topAnchor.constraint(equalTo: monoTitle.bottomAnchor, constant: 2),

			monochromeSwitch.trailingAnchor.constraint(
				equalTo: monoRow.trailingAnchor, constant: -14),
			monochromeSwitch.centerYAnchor.constraint(equalTo: monoRow.centerYAnchor),
		])

		requirePruneConfirmationSwitch.target = self
		requirePruneConfirmationSwitch.action = #selector(requirePruneConfirmationToggleChanged)
		requirePruneConfirmationSwitch.translatesAutoresizingMaskIntoConstraints = false

		// "Require Prune Session confirmation" row: same treatment as the
		// monochrome row, stacked directly beneath it.
		let pruneRow = NSView()
		pruneRow.translatesAutoresizingMaskIntoConstraints = false
		pruneRow.wantsLayer = true
		pruneRow.layer?.cornerRadius = 8
		pruneRow.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		card.addSubview(pruneRow)

		let pruneBadge = NSView()
		pruneBadge.translatesAutoresizingMaskIntoConstraints = false
		pruneBadge.wantsLayer = true
		pruneBadge.layer?.cornerRadius = 6
		pruneBadge.layer?.backgroundColor = SettingsTheme.buttonBackground.cgColor
		pruneRow.addSubview(pruneBadge)

		let pruneGlyph = NSImageView()
		pruneGlyph.translatesAutoresizingMaskIntoConstraints = false
		pruneGlyph.image = NSImage(systemSymbolName: "shield", accessibilityDescription: nil)
		pruneGlyph.contentTintColor = .secondaryLabelColor
		pruneGlyph.imageScaling = .scaleProportionallyUpOrDown
		pruneBadge.addSubview(pruneGlyph)

		let pruneTitle = NSTextField(labelWithString: "Require Prune Session confirmation")
		pruneTitle.font = .systemFont(ofSize: 13, weight: .medium)
		pruneTitle.translatesAutoresizingMaskIntoConstraints = false
		pruneRow.addSubview(pruneTitle)

		let pruneSubtitle = NSTextField(
			wrappingLabelWithString:
				"Show a confirmation dialog before pruning session data. When off, pruning will happen immediately."
		)
		pruneSubtitle.font = .systemFont(ofSize: 11)
		pruneSubtitle.textColor = .secondaryLabelColor
		pruneSubtitle.translatesAutoresizingMaskIntoConstraints = false
		pruneRow.addSubview(pruneSubtitle)

		pruneRow.addSubview(requirePruneConfirmationSwitch)

		NSLayoutConstraint.activate([
			pruneBadge.leadingAnchor.constraint(equalTo: pruneRow.leadingAnchor, constant: 14),
			pruneBadge.centerYAnchor.constraint(equalTo: pruneRow.centerYAnchor),
			pruneBadge.widthAnchor.constraint(equalToConstant: 28),
			pruneBadge.heightAnchor.constraint(equalToConstant: 28),

			pruneGlyph.centerXAnchor.constraint(equalTo: pruneBadge.centerXAnchor),
			pruneGlyph.centerYAnchor.constraint(equalTo: pruneBadge.centerYAnchor),
			pruneGlyph.widthAnchor.constraint(equalToConstant: 14),
			pruneGlyph.heightAnchor.constraint(equalToConstant: 14),

			pruneTitle.leadingAnchor.constraint(equalTo: pruneBadge.trailingAnchor, constant: 12),
			pruneTitle.topAnchor.constraint(equalTo: pruneRow.topAnchor, constant: 10),

			pruneSubtitle.leadingAnchor.constraint(equalTo: pruneTitle.leadingAnchor),
			pruneSubtitle.topAnchor.constraint(equalTo: pruneTitle.bottomAnchor, constant: 2),
			pruneSubtitle.trailingAnchor.constraint(
				lessThanOrEqualTo: requirePruneConfirmationSwitch.leadingAnchor, constant: -12),
			pruneSubtitle.bottomAnchor.constraint(
				lessThanOrEqualTo: pruneRow.bottomAnchor, constant: -10),

			requirePruneConfirmationSwitch.trailingAnchor.constraint(
				equalTo: pruneRow.trailingAnchor, constant: -14),
			requirePruneConfirmationSwitch.centerYAnchor.constraint(
				equalTo: pruneRow.centerYAnchor),
		])

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			iconBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
			iconBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			iconBadge.widthAnchor.constraint(equalToConstant: 32),
			iconBadge.heightAnchor.constraint(equalToConstant: 32),

			iconGlyph.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
			iconGlyph.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
			iconGlyph.widthAnchor.constraint(equalToConstant: 16),
			iconGlyph.heightAnchor.constraint(equalToConstant: 16),

			// Title + subtitle stack to the right of the icon badge (mockup header).
			title.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 12),
			title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),

			subtitleNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			subtitleNote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			subtitleNote.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			hookTableContainer.topAnchor.constraint(
				equalTo: subtitleNote.bottomAnchor, constant: 16),
			hookTableContainer.leadingAnchor.constraint(
				equalTo: card.leadingAnchor, constant: 20),
			hookTableContainer.trailingAnchor.constraint(
				equalTo: card.trailingAnchor, constant: -20),

			hookRowsStack.topAnchor.constraint(equalTo: hookTableContainer.topAnchor),
			hookRowsStack.leadingAnchor.constraint(equalTo: hookTableContainer.leadingAnchor),
			hookRowsStack.trailingAnchor.constraint(equalTo: hookTableContainer.trailingAnchor),
			hookRowsStack.bottomAnchor.constraint(equalTo: hookTableContainer.bottomAnchor),

			actionRow.topAnchor.constraint(
				equalTo: hookTableContainer.bottomAnchor, constant: 14),
			actionRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			actionRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			statusPanel.topAnchor.constraint(equalTo: actionRow.bottomAnchor, constant: 14),
			statusPanel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			statusPanel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			monoRow.topAnchor.constraint(equalTo: statusPanel.bottomAnchor, constant: 14),
			monoRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			monoRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			monoRow.heightAnchor.constraint(equalToConstant: 56),

			pruneRow.topAnchor.constraint(equalTo: monoRow.bottomAnchor, constant: 10),
			pruneRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			pruneRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			pruneRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
			pruneRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	private func rebuildHookRows(_ rows: [GeneralTabViewModel.PlatformRow]) {
		hookRows.forEach { $0.removeFromSuperview() }
		hookRows = rows.enumerated().map { index, row in
			HookRowView(row: row, showsDivider: index < rows.count - 1)
		}
		hookRows.forEach {
			hookRowsStack.addArrangedSubview($0)
			$0.widthAnchor.constraint(equalTo: hookRowsStack.widthAnchor).isActive = true
		}
	}

	@objc private func installTapped() { onInstallHooks() }
	@objc private func updateTapped() { onUpdateHooks() }
	@objc private func removeTapped() { onUninstallHooks() }
	@objc private func monochromeToggleChanged() {
		onMonochromeToggled?(monochromeSwitch.state == .on)
	}
	@objc private func requirePruneConfirmationToggleChanged() {
		onRequirePruneConfirmationToggled?(requirePruneConfirmationSwitch.state == .on)
	}

	@objc private func copyDiagnosticsTapped() {
		let json = viewModel.diagnosticsJSON()
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(json, forType: .string)
		statusPanel.state = .success("Diagnostics copied to clipboard.")
	}
}

// MARK: - HookRowView

/// One row in the Hooks table: platform icon + name, a colored status pill,
/// and a short descriptor. Replaces the old single monospaced status-line
/// blob with a per-row rendering of `PlatformRow.statusPresentation` — no new
/// data, just a richer display of the same fields.
private final class HookRowView: NSView {
	init(row: GeneralTabViewModel.PlatformRow, showsDivider: Bool) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setupViews(row: row, showsDivider: showsDivider)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews(row: GeneralTabViewModel.PlatformRow, showsDivider: Bool) {
		let presentation = row.statusPresentation

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attribution = platformAttribution(forBadgeKey: row.originKey) {
			iconView.image = NSImage(named: attribution.assetName)
		}
		iconView.contentTintColor = Self.iconTint(forOriginKey: row.originKey)

		let nameLabel = NSTextField(labelWithString: row.name)
		nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
		nameLabel.translatesAutoresizingMaskIntoConstraints = false

		let pill = makeStatusPill(presentation)

		let descriptorLabel = NSTextField(labelWithString: presentation.descriptor)
		descriptorLabel.font = .systemFont(ofSize: 11)
		descriptorLabel.textColor = .secondaryLabelColor
		descriptorLabel.lineBreakMode = .byTruncatingTail
		descriptorLabel.translatesAutoresizingMaskIntoConstraints = false

		addSubview(iconView)
		addSubview(nameLabel)
		addSubview(pill)
		addSubview(descriptorLabel)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 40),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 26),
			iconView.heightAnchor.constraint(equalToConstant: 26),

			nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
			nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			nameLabel.widthAnchor.constraint(equalToConstant: 130),

			pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 330),
			pill.centerYAnchor.constraint(equalTo: centerYAnchor),

			// Column 3 sits at a fixed offset from the row's leading edge — not
			// `pill.trailingAnchor` — so it lines up across rows regardless of how
			// wide any one row's pill text ("Update available" vs "Installed") is.
			descriptorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 640),
			descriptorLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: trailingAnchor, constant: -14),
			descriptorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
		])

		if showsDivider {
			let divider = NSView()
			divider.translatesAutoresizingMaskIntoConstraints = false
			divider.wantsLayer = true
			divider.layer?.backgroundColor = SettingsTheme.rowDivider.cgColor
			addSubview(divider)
			NSLayoutConstraint.activate([
				divider.leadingAnchor.constraint(equalTo: leadingAnchor),
				divider.trailingAnchor.constraint(equalTo: trailingAnchor),
				divider.bottomAnchor.constraint(equalTo: bottomAnchor),
				divider.heightAnchor.constraint(equalToConstant: 1),
			])
		}
	}

	/// Brand-ish tint per platform so the template logo assets read distinctly
	/// (mockup treatment) instead of a uniform monochrome column.
	private static func iconTint(forOriginKey key: String) -> NSColor {
		switch key {
		case "claude_code":
			return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // Anthropic clay
		case "codex":
			return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)  // OpenAI green
		case "vscode":
			return NSColor(srgbRed: 0.00, green: 0.48, blue: 0.80, alpha: 1)  // VS Code blue
		case "cursor":
			return NSColor(calibratedWhite: 0.78, alpha: 1)  // Cursor slate
		case "antigravity":
			return NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1)  // "AI" violet
		default:
			return .labelColor
		}
	}

	private func makeStatusPill(
		_ presentation: GeneralTabViewModel.PlatformRow.StatusPresentation
	) -> NSView {
		let tint: NSColor
		switch presentation.pill {
		case .installed: tint = .systemGreen
		case .updateAvailable: tint = .systemYellow
		case .detectedNotInstalled: tint = .secondaryLabelColor
		case .notInstalled, .notSupported: tint = .tertiaryLabelColor
		}

		let container = NSView()
		container.wantsLayer = true
		container.layer?.cornerRadius = 5
		container.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
		container.translatesAutoresizingMaskIntoConstraints = false

		let label = NSTextField(labelWithString: presentation.pillTitle)
		label.font = .systemFont(ofSize: 11, weight: .semibold)
		label.textColor = tint
		label.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(label)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
			label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
			label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
			label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
		])
		return container
	}
}

// MARK: - DynamicStatusPanelView

/// Single status/feedback panel for the Hooks section. Shows the current
/// registration state by default (up to date, or an attention message when
/// stale/a new tool was detected) and temporarily reflects the result of an
/// install/update/remove action while one is in flight or just completed.
/// Replaces the old always-hidden-unless-stale `UpdateBannerView` plus a
/// separate plain-text feedback label with one view, one state.
private final class DynamicStatusPanelView: NSView {
	enum State: Equatable {
		case upToDate
		case attention(String)
		case working(String)
		case success(String)
		case error(String)
	}

	var state: State = .upToDate {
		didSet {
			guard state != oldValue else { return }
			render()
		}
	}

	private let iconView = NSImageView()
	private let spinner = NSProgressIndicator()
	private let headlineLabel = NSTextField(labelWithString: "")
	private let subtextLabel = NSTextField(labelWithString: "")

	init() {
		super.init(frame: .zero)
		setupViews()
		render()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		wantsLayer = true
		layer?.cornerRadius = 6

		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		addSubview(iconView)

		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.isDisplayedWhenStopped = false
		spinner.translatesAutoresizingMaskIntoConstraints = false
		addSubview(spinner)

		headlineLabel.font = .systemFont(ofSize: 12, weight: .semibold)
		headlineLabel.lineBreakMode = .byWordWrapping

		subtextLabel.font = .systemFont(ofSize: 11)
		subtextLabel.textColor = .secondaryLabelColor
		subtextLabel.lineBreakMode = .byWordWrapping

		// Headline + optional subtext live in one stack centered on the panel's
		// vertical axis, so single-line states (attention/success/error, which
		// hide the subtext) align with the icon instead of hugging the top edge.
		let textStack = NSStackView(views: [headlineLabel, subtextLabel])
		textStack.orientation = .vertical
		textStack.alignment = .leading
		textStack.spacing = 2
		textStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(textStack)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 26),
			iconView.heightAnchor.constraint(equalToConstant: 26),

			spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
			spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
			textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
			textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
		])
	}

	private func render() {
		let symbolName: String?
		let tint: NSColor
		let headline: String
		let subtext: String?

		switch state {
		case .upToDate:
			symbolName = "checkmark.circle"
			tint = .secondaryLabelColor
			headline = "Hooks are up to date"
			subtext = "All supported tools are registered and ready."
		case .attention(let message):
			symbolName = "exclamationmark.triangle.fill"
			tint = .systemYellow
			headline = message
			subtext = nil
		case .working(let message):
			symbolName = nil
			tint = .secondaryLabelColor
			headline = message
			subtext = "This may take a few moments."
		case .success(let message):
			symbolName = "checkmark.circle.fill"
			tint = .systemGreen
			headline = message
			subtext = nil
		case .error(let message):
			symbolName = "exclamationmark.triangle.fill"
			tint = .systemRed
			headline = message
			subtext = nil
		}

		layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
		headlineLabel.textColor = .labelColor
		headlineLabel.stringValue = headline
		subtextLabel.stringValue = subtext ?? ""
		subtextLabel.isHidden = subtext == nil

		if let symbolName {
			iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
			iconView.contentTintColor = tint
			iconView.isHidden = false
			spinner.stopAnimation(nil)
		} else {
			iconView.isHidden = true
			spinner.startAnimation(nil)
		}
	}
}

// MARK: - PetTabView

/// Pet tab — a single flat grid of pet cards. Every pet appears once,
/// deduplicated across the bundled, Codex, and canonical-store sources.
///
/// Installed pets show a portrait thumbnail (raised to align with the pet name)
/// and an Assign icon in the name row that opens a multiselect badge dropdown.
/// Importable pets (present only under `~/.codex/pets/`) show an Import icon
/// centered beneath the thumbnail. Assigned badge pills appear below the
/// description. The Default badge holder carries a blue selection border.
private final class PetTabView: NSView, NSSearchFieldDelegate {
	/// View identifiers used by layout tests to locate cards and their
	/// description labels in the rendered hierarchy.
	static let cardIdentifier = NSUserInterfaceItemIdentifier("petCard")
	static let descriptionIdentifier = NSUserInterfaceItemIdentifier("petCardDescription")

	private var viewModel: PetTabViewModel
	private let onImportPet: (String) -> Void

	private let searchField = NSSearchField()
	private let openFolderButton = NSButton(title: "Open pet folder", target: nil, action: nil)
	private let gridScrollView = NSScrollView()
	/// Flipped so a short grid (few search results) anchors to the TOP of the
	/// scroll area. A default non-flipped document view sinks short content to
	/// the bottom — the scroll origin sits bottom-left.
	private let gridStack = FlippedStackView()
	private let emptyLabel = NSTextField(labelWithString: "")
	private let footerLabel = NSTextField(labelWithString: "")
	private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
	private var feedbackHeightConstraint: NSLayoutConstraint?

	/// Idle-frame thumbnails are sliced once and cached by spritesheet path so
	/// repeated grid rebuilds (resize, assign, search) don't re-decode WebP.
	private var thumbnailCache: [String: NSImage?] = [:]
	/// Column count last laid out — guards `layout()` from rebuilding the grid
	/// on every resize tick, only when the responsive column count changes.
	private var lastColumnCount = 0
	private var currentEntries: [PetCatalogEntry] = []
	private var activeAssignPopover: NSPopover?

	private let cardSpacing: CGFloat = 12
	private let minCardWidth: CGFloat = 300
	private let maxColumns = 3
	private let thumbSize: CGFloat = 64

	init(
		viewModel: PetTabViewModel,
		onImportPet: @escaping (String) -> Void
	) {
		self.viewModel = viewModel
		self.onImportPet = onImportPet
		super.init(frame: .zero)
		setupViews()
		reloadEntries()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func setPetImportSuccess(petId: String) {
		setFeedback("Imported \(petId) to ~/.codogotchi/pets/.", color: .systemGreen)
	}

	func setPetImportError(_ message: String) {
		setFeedback(message, color: .systemRed)
	}

	/// Rebuild the grid from the current ViewModel state (after import).
	func refreshPetList(viewModel: PetTabViewModel) {
		self.viewModel = viewModel
		reloadEntries()
	}

	private func setupViews() {
		// Lighter wrapper card with an icon-badge header, matching the Hooks
		// card on General (and the Customization wrapper) so all tabs share one
		// design language.
		let wrapper = NSView()
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.wantsLayer = true
		wrapper.layer?.cornerRadius = 10
		wrapper.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
		wrapper.layer?.borderWidth = 1
		wrapper.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		addSubview(wrapper)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: "pawprint.fill", color: .systemPink)
		wrapper.addSubview(headerBadge)

		let title = settingsSectionTitle("Pet")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		wrapper.addSubview(title)

		let storeNote = settingsBodyLabel(
			"Installed pets live in ~/.codogotchi/pets/. "
				+ "Pets in ~/.codex/pets/ show an Import action."
		)
		wrapper.addSubview(storeNote)

		searchField.placeholderString = "Search pets…"
		searchField.delegate = self
		searchField.sendsWholeSearchString = false
		searchField.sendsSearchStringImmediately = true
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		wrapper.addSubview(searchField)

		openFolderButton.bezelStyle = .rounded
		openFolderButton.target = self
		openFolderButton.action = #selector(openPetFolder)
		openFolderButton.translatesAutoresizingMaskIntoConstraints = false
		openFolderButton.setContentHuggingPriority(.required, for: .horizontal)
		wrapper.addSubview(openFolderButton)

		gridStack.orientation = .vertical
		gridStack.alignment = .leading
		gridStack.spacing = cardSpacing
		gridStack.translatesAutoresizingMaskIntoConstraints = false

		gridScrollView.hasVerticalScroller = true
		gridScrollView.hasHorizontalScroller = false
		gridScrollView.autohidesScrollers = true
		gridScrollView.borderType = .noBorder
		gridScrollView.drawsBackground = false
		gridScrollView.translatesAutoresizingMaskIntoConstraints = false
		gridScrollView.documentView = gridStack
		wrapper.addSubview(gridScrollView)

		NSLayoutConstraint.activate([
			gridStack.widthAnchor.constraint(equalTo: gridScrollView.contentView.widthAnchor),
		])

		emptyLabel.font = .systemFont(ofSize: 12)
		emptyLabel.textColor = .secondaryLabelColor
		emptyLabel.alignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(emptyLabel)

		footerLabel.font = .systemFont(ofSize: 11)
		footerLabel.textColor = .tertiaryLabelColor
		footerLabel.alignment = .center
		footerLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(footerLabel)

		feedbackLabel.isEditable = false
		feedbackLabel.isBordered = false
		feedbackLabel.backgroundColor = .clear
		feedbackLabel.font = .systemFont(ofSize: 11)
		feedbackLabel.textColor = .secondaryLabelColor
		feedbackLabel.isHidden = true
		feedbackLabel.identifier = NSUserInterfaceItemIdentifier("petTabFeedback")
		feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(feedbackLabel)
		feedbackHeightConstraint = feedbackLabel.heightAnchor.constraint(equalToConstant: 0)
		feedbackHeightConstraint?.isActive = true

		NSLayoutConstraint.activate([
			wrapper.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			wrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			wrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			wrapper.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),

			title.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 18),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),

			searchField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			searchField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
			searchField.widthAnchor.constraint(equalToConstant: 200),

			openFolderButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openFolderButton.trailingAnchor.constraint(
				equalTo: searchField.leadingAnchor, constant: -8),
			openFolderButton.leadingAnchor.constraint(
				greaterThanOrEqualTo: title.trailingAnchor, constant: 16),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			storeNote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			storeNote.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			feedbackLabel.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 8),
			feedbackLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			feedbackLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			gridScrollView.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 8),
			gridScrollView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			gridScrollView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			emptyLabel.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),

			footerLabel.topAnchor.constraint(equalTo: gridScrollView.bottomAnchor, constant: 8),
			footerLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			footerLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
			footerLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
		])
	}

	/// NSTabView sizes its selected item view by frame-setting, which does not
	/// reliably schedule a constraint layout pass on this view. Without this,
	/// the first (and only) `layout()` can run while the view is still zero-
	/// sized: the grid stays in its initial 1-column build and descriptions
	/// render single-line at full width.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsLayout = true
	}

	override func layout() {
		super.layout()
		// `super.layout()` positions only direct subviews; the scroll view is
		// nested inside the wrapper card, so on a one-shot pass its frame can
		// still be zero here. Resolve the wrapper's subtree before sampling the
		// width the column count depends on.
		gridScrollView.superview?.layoutSubtreeIfNeeded()
		// Rebuild only when the responsive column count actually changes, so
		// resize drags don't thrash the grid.
		let columns = columnCount(forWidth: gridScrollView.contentView.bounds.width)
		if columns != lastColumnCount {
			rebuildGrid()
		}
		sizeDocumentToFit()
	}

	// MARK: - Data

	/// Pull a fresh catalog from the view model and rebuild. Footer counts use
	/// the full (unfiltered) catalog; the grid honors the current search text.
	private func reloadEntries() {
		currentEntries = viewModel.catalog()
		updateFooter()
		rebuildGrid()
	}

	private func updateFooter() {
		let total = currentEntries.count
		let installed = currentEntries.filter { $0.state != .importable }.count
		let importable = total - installed
		footerLabel.stringValue =
			"\(total) PETS — \(installed) INSTALLED · \(importable) IMPORTABLE"
	}

	private var filteredEntries: [PetCatalogEntry] {
		let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
		guard !query.isEmpty else { return currentEntries }
		return currentEntries.filter {
			$0.displayName.lowercased().contains(query) || $0.id.lowercased().contains(query)
		}
	}

	// MARK: - Grid

	private func columnCount(forWidth width: CGFloat) -> Int {
		guard width > 0 else { return 1 }
		let columns = Int((width + cardSpacing) / (minCardWidth + cardSpacing))
		return max(1, min(maxColumns, columns))
	}

	private func rebuildGrid() {
		for view in gridStack.arrangedSubviews {
			gridStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		let entries = filteredEntries
		if entries.isEmpty {
			let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
			emptyLabel.stringValue =
				query.isEmpty ? "No pets available." : "No pets match \"\(query)\"."
			emptyLabel.isHidden = false
			lastColumnCount = columnCount(forWidth: gridScrollView.contentView.bounds.width)
			sizeDocumentToFit()
			return
		}
		emptyLabel.isHidden = true

		let columns = columnCount(forWidth: gridScrollView.contentView.bounds.width)
		lastColumnCount = columns

		var index = 0
		while index < entries.count {
			let slice = entries[index..<min(index + columns, entries.count)]
			var rowViews: [NSView] = slice.map { makeCard(for: $0) }
			// Pad the final row with invisible spacers so `.fillEqually` keeps
			// the real cards at one-column width instead of stretching them.
			while rowViews.count < columns {
				let spacer = NSView()
				spacer.translatesAutoresizingMaskIntoConstraints = false
				rowViews.append(spacer)
			}
			let row = NSStackView(views: rowViews)
			row.orientation = .horizontal
			row.distribution = .fillEqually
			row.alignment = .top
			row.spacing = cardSpacing
			row.translatesAutoresizingMaskIntoConstraints = false
			// All real cards in the row adopt the height of the tallest card.
			let realCount = slice.count
			if realCount > 1 {
				for i in 1..<realCount {
					rowViews[i].heightAnchor.constraint(equalTo: rowViews[0].heightAnchor).isActive =
						true
				}
			}
			gridStack.addArrangedSubview(row)
			// Pin width only after the row joins the stack — activating a
			// cross-view constraint before they share an ancestor throws
			// NSGenericException and aborts the whole Settings window.
			row.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
			index += columns
		}
		sizeDocumentToFit()
	}

	private func sizeDocumentToFit() {
		gridStack.layoutSubtreeIfNeeded()
		let fitting = gridStack.fittingSize
		var frame = gridStack.frame
		frame.size = CGSize(
			width: gridScrollView.contentView.bounds.width,
			height: fitting.height
		)
		gridStack.frame = frame
	}

	private func makeCard(for entry: PetCatalogEntry) -> NSView {
		let card = NSView()
		card.translatesAutoresizingMaskIntoConstraints = false
		card.wantsLayer = true
		card.layer?.cornerRadius = 10
		card.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		card.layer?.borderWidth = entry.isDefault ? 2 : 1
		card.layer?.borderColor =
			(entry.isDefault ? NSColor.controlAccentColor : SettingsTheme.cardBorder).cgColor
		card.identifier = PetTabView.cardIdentifier
		card.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true

		// Thumbnail — left column, raised to align with the pet name row.
		let thumb = NSImageView()
		thumb.translatesAutoresizingMaskIntoConstraints = false
		thumb.imageScaling = .scaleProportionallyUpOrDown
		thumb.image = thumbnail(for: entry)
		thumb.wantsLayer = true
		thumb.layer?.cornerRadius = 10
		thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
		thumb.layer?.masksToBounds = true
		card.addSubview(thumb)

		NSLayoutConstraint.activate([
			thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
			thumb.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
			thumb.widthAnchor.constraint(equalToConstant: thumbSize),
			thumb.heightAnchor.constraint(equalToConstant: thumbSize),
		])

		// Import icon — centered beneath thumbnail, only for importable pets.
		var leftBottomAnchor: NSLayoutYAxisAnchor = thumb.bottomAnchor
		var leftBottomConstant: CGFloat = 14
		if entry.state == .importable {
			let importBtn = makeImportIconButton(for: entry)
			card.addSubview(importBtn)
			NSLayoutConstraint.activate([
				importBtn.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 6),
				importBtn.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
			])
			leftBottomAnchor = importBtn.bottomAnchor
			leftBottomConstant = 12
		}

		// Name label — truncates tail when the name is long.
		let nameLabel = NSTextField(labelWithString: entry.displayName)
		nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		// Assign icon — right-aligned in the name row, only for installed pets.
		let nameRowViews: [NSView]
		if entry.state == .installed {
			let assignBtn = makeAssignButton(for: entry)
			nameRowViews = [nameLabel, assignBtn]
		} else {
			nameRowViews = [nameLabel]
		}

		let nameRow = NSStackView(views: nameRowViews)
		nameRow.orientation = .horizontal
		nameRow.spacing = 6
		nameRow.alignment = .top
		nameRow.distribution = .fill
		nameRow.translatesAutoresizingMaskIntoConstraints = false
		// Cards with no assignBtn have a shorter intrinsic nameRow (~17pt vs 20pt).
		// A minimum height normalises the gap so descLabel always starts at the same Y.
		nameRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

		// Description — full-width in the right column, wraps up to 5 lines.
		let descLabel = NSTextField(wrappingLabelWithString: entry.description)
		descLabel.font = .systemFont(ofSize: 12)
		descLabel.textColor = .secondaryLabelColor
		descLabel.maximumNumberOfLines = 5
		descLabel.lineBreakMode = .byWordWrapping
		descLabel.cell?.truncatesLastVisibleLine = true
		descLabel.identifier = PetTabView.descriptionIdentifier
		descLabel.translatesAutoresizingMaskIntoConstraints = false
		descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		// Prevent the label from stretching below its intrinsic height.
		// When equal-height constraints force a shorter card to match a taller sibling,
		// the preferRight anchor (card.bottom = descLabel.bottom + 14, .defaultHigh)
		// would otherwise pull descLabel's bottom down to fill the extra space.
		descLabel.setContentHuggingPriority(.required, for: .vertical)

		card.addSubview(nameRow)
		card.addSubview(descLabel)

		NSLayoutConstraint.activate([
			nameRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
			nameRow.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 14),
			nameRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

			descLabel.topAnchor.constraint(equalTo: nameRow.bottomAnchor, constant: 4),
			descLabel.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor),
			descLabel.trailingAnchor.constraint(equalTo: nameRow.trailingAnchor),
		])

		// Badge pills — always present (zero-height "invisible pill" when this pet holds no
		// badges) so every card's right column ends on the same anchor. The top gap is a
		// `>=` minimum, not a fixed offset: when the equal-height row constraint forces a
		// shorter card taller, the slack must open up here (between description and pills)
		// rather than stretching descLabel or leaving pills floating high above the bottom.
		let entryBadges = viewModel.badges(for: entry.id)
		let pillsRow = makeBadgePillsRow(badges: entryBadges)
		card.addSubview(pillsRow)
		NSLayoutConstraint.activate([
			pillsRow.topAnchor.constraint(greaterThanOrEqualTo: descLabel.bottomAnchor, constant: 6),
			pillsRow.leadingAnchor.constraint(equalTo: descLabel.leadingAnchor),
			pillsRow.trailingAnchor.constraint(
				lessThanOrEqualTo: card.trailingAnchor, constant: -16),
		])
		let rightBottomAnchor: NSLayoutYAxisAnchor = pillsRow.bottomAnchor
		let rightBottomConstant: CGFloat = 14

		// Card bottom is driven by the taller of the two columns.
		// The `.defaultHigh` equality tracks the right column exactly; the
		// required `>=` from the left column overrides upward when taller.
		let leftBottom = card.bottomAnchor.constraint(
			greaterThanOrEqualTo: leftBottomAnchor, constant: leftBottomConstant)
		let rightBottom = card.bottomAnchor.constraint(
			greaterThanOrEqualTo: rightBottomAnchor, constant: rightBottomConstant)
		let preferRight = card.bottomAnchor.constraint(
			equalTo: rightBottomAnchor, constant: rightBottomConstant)
		preferRight.priority = .defaultHigh
		NSLayoutConstraint.activate([leftBottom, rightBottom, preferRight])

		return card
	}

	// MARK: - Card sub-views

	/// Small icon button in the pet name row. Tapping opens the badge dropdown.
	private func makeAssignButton(for entry: PetCatalogEntry) -> NSButton {
		let btn = NSButton()
		btn.isBordered = false
		btn.imagePosition = .imageOnly
		btn.imageScaling = .scaleProportionallyUpOrDown
		btn.image = NSImage(
			systemSymbolName: "person.badge.plus",
			accessibilityDescription: "Assign platform badge")
		btn.contentTintColor = .secondaryLabelColor
		btn.toolTip = "Assign Pet to a Platform"
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.setContentHuggingPriority(.required, for: .horizontal)
		NSLayoutConstraint.activate([
			btn.widthAnchor.constraint(equalToConstant: 20),
			btn.heightAnchor.constraint(equalToConstant: 20),
		])
		btn.target = self
		btn.action = #selector(assignButtonTapped(_:))
		objc_setAssociatedObject(btn, &assignBtnKey, entry.id, .OBJC_ASSOCIATION_RETAIN)
		return btn
	}

	/// Small icon button centered beneath the thumbnail for importable pets.
	private func makeImportIconButton(for entry: PetCatalogEntry) -> NSButton {
		let btn = NSButton()
		btn.isBordered = false
		btn.imagePosition = .imageOnly
		btn.imageScaling = .scaleProportionallyUpOrDown
		btn.image = NSImage(
			systemSymbolName: "square.and.arrow.down",
			accessibilityDescription: "Import pet")
		btn.contentTintColor = .secondaryLabelColor
		btn.toolTip = "Import Codex Pet"
		btn.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			btn.widthAnchor.constraint(equalToConstant: 20),
			btn.heightAnchor.constraint(equalToConstant: 20),
		])
		btn.target = self
		btn.action = #selector(importIconTapped(_:))
		objc_setAssociatedObject(btn, &importBtnKey, entry.id, .OBJC_ASSOCIATION_RETAIN)
		return btn
	}

	/// Horizontal row of compact icon-only badge pills for all badges held by this pet.
	private func makeBadgePillsRow(badges: Set<String>) -> NSView {
		let sorted = ASSIGNMENT_BADGE_KEYS.filter { badges.contains($0) }
		let pills = sorted.map { key -> NSView in makePlatformIconPill(key: key) }
		let row = NSStackView(views: pills)
		row.orientation = .horizontal
		row.spacing = 4
		row.alignment = .centerY
		row.translatesAutoresizingMaskIntoConstraints = false
		return row
	}

	private func makePlatformIconPill(key: String) -> NSView {
		let tint: NSColor = key == "default" ? .systemGreen : .secondaryLabelColor
		let container = NSView()
		container.wantsLayer = true
		container.layer?.cornerRadius = 5
		container.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
		container.translatesAutoresizingMaskIntoConstraints = false

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attr = platformAttribution(forBadgeKey: key) {
			iconView.image = NSImage(named: attr.assetName)
		}
		iconView.contentTintColor = tint

		container.addSubview(iconView)
		NSLayoutConstraint.activate([
			iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 12),
			iconView.heightAnchor.constraint(equalToConstant: 12),
			container.widthAnchor.constraint(equalToConstant: 22),
			container.heightAnchor.constraint(equalToConstant: 18),
		])
		return container
	}

	private func thumbnail(for entry: PetCatalogEntry) -> NSImage? {
		guard let sheet = entry.spritesheetURL else { return nil }
		let key = sheet.path
		if let cached = thumbnailCache[key] { return cached }
		let image = PetThumbnail.idleFirstFrame(spritesheetURL: sheet, targetHeight: thumbSize)
		thumbnailCache[key] = image
		return image
	}

	// MARK: - Actions

	func controlTextDidChange(_ obj: Notification) {
		guard (obj.object as? NSSearchField) === searchField else { return }
		rebuildGrid()
	}

	@objc private func openPetFolder() {
		CodogotchiFolders.reveal(CodogotchiFolders.petFolderURL())
	}

	/// Opens a persistent badge popover for `sender`'s associated pet.
	/// The popover stays open while the user toggles platforms and dismisses on outside click.
	@objc private func assignButtonTapped(_ sender: NSButton) {
		guard let petId = objc_getAssociatedObject(sender, &assignBtnKey) as? String else { return }
		activeAssignPopover?.close()
		activeAssignPopover = nil

		let vc = PetAssignPopoverController(petId: petId, viewModel: viewModel)
		let popover = NSPopover()
		popover.contentViewController = vc
		popover.behavior = .transient
		popover.delegate = self
		popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
		activeAssignPopover = popover
	}

	private func setAssignmentPersistenceError() {
		setFeedback(
			"Couldn’t save assignment. Check Codogotchi folder permissions.",
			color: .systemRed)
	}

	private func setFeedback(_ message: String, color: NSColor) {
		feedbackLabel.stringValue = message
		feedbackLabel.textColor = color
		feedbackLabel.isHidden = false
		feedbackHeightConstraint?.isActive = false
	}

	private func clearFeedback() {
		feedbackLabel.stringValue = ""
		feedbackLabel.isHidden = true
		feedbackHeightConstraint?.isActive = true
	}

	/// Import icon tapped for an importable pet.
	@objc private func importIconTapped(_ sender: NSButton) {
		guard let petId = objc_getAssociatedObject(sender, &importBtnKey) as? String else { return }
		onImportPet(petId)
	}
}

extension PetTabView: NSPopoverDelegate {
	func popoverDidClose(_ notification: Notification) {
		// Rebuild the grid so badge pills reflect any toggles made in the popover.
		reloadEntries()
		activeAssignPopover = nil
	}
}

// MARK: - Assign popover

/// A persistent popover listing all assignable platforms for one pet.
/// Rows toggle without closing the popover; clicking outside dismisses it.
private final class PetAssignPopoverController: NSViewController {
	private let petId: String
	private let viewModel: PetTabViewModel
	private var rowViews: [String: BadgeRowView] = [:]

	init(petId: String, viewModel: PetTabViewModel) {
		self.petId = petId
		self.viewModel = viewModel
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	override func loadView() {
		let stack = NSStackView()
		stack.orientation = .vertical
		stack.spacing = 1
		stack.translatesAutoresizingMaskIntoConstraints = false

		for key in ASSIGNMENT_BADGE_KEYS {
			let row = makePlatformRow(for: key)
			rowViews[key] = row
			stack.addArrangedSubview(row)
		}

		let wrapper = NSView()
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
			stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
			stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
			wrapper.widthAnchor.constraint(equalToConstant: 200),
		])
		view = wrapper
	}

	private func makePlatformRow(for key: String) -> BadgeRowView {
		let badges = viewModel.badges(for: petId)
		let isChecked = badges.contains(key)
		let isDefaultHeld = key == "default" && isChecked
		let row = BadgeRowView(isDisabled: isDefaultHeld)
		row.translatesAutoresizingMaskIntoConstraints = false
		row.heightAnchor.constraint(equalToConstant: 32).isActive = true

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attr = platformAttribution(forBadgeKey: key) {
			iconView.image = NSImage(named: attr.assetName)
		}
		iconView.contentTintColor = .labelColor

		let label = NSTextField(labelWithString: badgeDisplayName(key))
		label.font = .systemFont(ofSize: 13)
		label.translatesAutoresizingMaskIntoConstraints = false

		let check = NSImageView()
		check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
		check.contentTintColor = .controlAccentColor
		check.isHidden = !isChecked
		check.translatesAutoresizingMaskIntoConstraints = false
		row.checkmark = check

		row.addSubview(iconView)
		row.addSubview(label)
		row.addSubview(check)

		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
			iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 16),
			iconView.heightAnchor.constraint(equalToConstant: 16),
			label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
			label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -4),
			check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
			check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			check.widthAnchor.constraint(equalToConstant: 12),
			check.heightAnchor.constraint(equalToConstant: 12),
		])

		row.onTap = { [weak self] in self?.toggleBadge(key) }
		return row
	}

	private func toggleBadge(_ key: String) {
		let isChecked = viewModel.badges(for: petId).contains(key)
		if isChecked {
			_ = viewModel.unassign(badge: key, from: petId)
		} else {
			try? viewModel.assign(badge: key, to: petId)
		}
		// Refresh all rows — e.g. assigning Default moves it off the previous holder.
		let updated = viewModel.badges(for: petId)
		for (k, row) in rowViews {
			let nowChecked = updated.contains(k)
			row.update(isChecked: nowChecked, isDisabled: k == "default" && nowChecked)
		}
	}
}

private final class BadgeRowView: NSView {
	private var isDisabled: Bool
	var onTap: (() -> Void)?
	var checkmark: NSImageView?

	init(isDisabled: Bool) {
		self.isDisabled = isDisabled
		super.init(frame: .zero)
		wantsLayer = true
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func update(isChecked: Bool, isDisabled: Bool) {
		self.isDisabled = isDisabled
		checkmark?.isHidden = !isChecked
		updateTrackingAreas()
	}

	override func mouseUp(with event: NSEvent) {
		guard !isDisabled else { return }
		onTap?()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach { removeTrackingArea($0) }
		guard !isDisabled else { return }
		addTrackingArea(NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInActiveApp],
			owner: self,
			userInfo: nil
		))
	}

	override func mouseEntered(with event: NSEvent) {
		layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor
	}

	override func mouseExited(with event: NSEvent) {
		layer?.backgroundColor = .clear
	}
}

private func badgeDisplayName(_ key: String) -> String {
	switch key {
	case "default": return "Default"
	case "claude_code": return "Claude Code"
	case "vscode": return "VS Code"
	case "codex": return "Codex"
	case "cursor": return "Cursor"
	case "antigravity": return "Antigravity"
	default: return key
	}
}

private func platformAttribution(forBadgeKey key: String) -> PlatformAttribution? {
	switch key {
	case "default": return .default
	case "claude_code": return .claudeCode
	case "vscode": return .vscode
	case "codex": return .codex
	case "cursor": return .cursor
	case "antigravity": return .antigravity
	default: return nil
	}
}

private var assignBtnKey: UInt8 = 0
private var importBtnKey: UInt8 = 2

/// Top-left origin so a short pet grid anchors to the top of its scroll view
/// instead of sinking to the bottom (the default non-flipped behavior).
private final class FlippedStackView: NSStackView {
	override var isFlipped: Bool { true }
}

// MARK: - RPGTabView

/// RPG tab — HUD opt-out toggle and demo mode preview.
private final class RPGTabView: NSView {
	private let hudModePicker = NSPopUpButton()
	private let sicknessSwitch = NSSwitch()
	private let skipWeekendsSwitch = NSSwitch()
	private let decayHoursPicker = NSPopUpButton()
	private let regenMinutesPicker = NSPopUpButton()
	private let mildSicknessPicker = NSPopUpButton()
	private let severeSicknessPicker = NSPopUpButton()
	private let sicknessSummary = settingsBodyLabel("")
	private var viewModel: RPGTabViewModel
	private let onHUDModeChanged: (PetConfig.RPGHUDMode) -> Void

	init(viewModel: RPGTabViewModel, onHUDModeChanged: @escaping (PetConfig.RPGHUDMode) -> Void) {
		self.viewModel = viewModel
		self.onHUDModeChanged = onHUDModeChanged
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func reload(viewModel: RPGTabViewModel) {
		self.viewModel = viewModel
		NSLayoutConstraint.deactivate(constraints)
		subviews.forEach { $0.removeFromSuperview() }
		setupViews()
		needsLayout = true
	}

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.rpg.symbolName, color: .systemGreen)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("RPG")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		let note = settingsBodyLabel(
			"When enabled, a floating HUD shows hearts, level, and XP ring while "
				+ "you code. Toggle off to hide it completely — the RPG engine keeps "
				+ "running in the background."
		)
		card.addSubview(note)

		let previewPanel = makePreviewPanel()
		let healthPanel = makeHealthConfigurationPanel()
		healthPanel.setContentHuggingPriority(.defaultLow, for: .vertical)

		let leftColumn = NSStackView()
		leftColumn.translatesAutoresizingMaskIntoConstraints = false
		leftColumn.orientation = .vertical
		leftColumn.alignment = .leading
		leftColumn.distribution = .fill
		leftColumn.spacing = 16
		leftColumn.addArrangedSubview(previewPanel)
		leftColumn.addArrangedSubview(healthPanel)

		let hudPanel = makeHudElementsPanel()
		hudPanel.setContentHuggingPriority(.required, for: .vertical)
		let sicknessPanel = makeSicknessConfigurationPanel()
		sicknessPanel.setContentHuggingPriority(.defaultLow, for: .vertical)
		let rightColumn = NSStackView()
		rightColumn.translatesAutoresizingMaskIntoConstraints = false
		rightColumn.orientation = .vertical
		rightColumn.alignment = .leading
		rightColumn.spacing = 16
		rightColumn.addArrangedSubview(hudPanel)
		rightColumn.addArrangedSubview(sicknessPanel)

		let content = NSStackView()
		content.translatesAutoresizingMaskIntoConstraints = false
		content.orientation = .horizontal
		content.alignment = .top
		content.distribution = .fill
		content.spacing = 22
		content.addArrangedSubview(leftColumn)
		content.addArrangedSubview(rightColumn)
		card.addSubview(content)

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),
			title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			note.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			note.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			content.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 22),
			content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),

			// Only the left column carries a width multiplier; the right column
			// fills whatever remains after the stack's fixed spacing. Pinning
			// BOTH columns to multipliers (0.44 + 0.54) plus the 22pt spacing
			// was satisfiable only at one exact content width (1100pt) — wider
			// than the fixed 1120pt window provides — so AppKit grew the window
			// to meet it, and the oversized frame then leaked extra bottom
			// padding into every other tab after visiting RPG.
			leftColumn.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.44),
			previewPanel.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
			healthPanel.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
			hudPanel.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
			sicknessPanel.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
			// 320 (not the previous 400) keeps the full left column — preview +
			// 16 spacing + ≥210 health card — inside the height the fixed
			// 770pt window actually offers, for the same no-window-growth
			// reason as the width note above.
			previewPanel.heightAnchor.constraint(equalToConstant: 320),
			hudPanel.heightAnchor.constraint(equalTo: previewPanel.heightAnchor),
			healthPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
			sicknessPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
		])
	}

	private static let hudModeOptions = PetConfig.RPGHUDMode.allCases

	private func hudModeLabel(_ mode: PetConfig.RPGHUDMode) -> String {
		switch mode {
		case .all: return "Show HUD on All Pets"
		case .mostRecent: return "Show HUD on Most Recent Pet"
		case .hidden: return "Hide HUD"
		}
	}

	private func makePreviewPanel() -> NSView {
		let panel = settingsThemedCard()
		let title = settingsColumnHeader("HUD PREVIEW")
		let subtitle = settingsBodyLabel("Selected Default Pet: \(viewModel.petName)")
		// Groups title+subtitle so the mode picker can center against their
		// combined vertical span, not just the title's baseline.
		let headerTextStack = NSStackView(views: [title, subtitle])
		headerTextStack.translatesAutoresizingMaskIntoConstraints = false
		headerTextStack.orientation = .vertical
		headerTextStack.alignment = .leading
		headerTextStack.spacing = 6

		configurePopup(
			hudModePicker,
			options: Self.hudModeOptions,
			selected: viewModel.hudMode,
			label: hudModeLabel,
			action: #selector(hudModeChanged)
		)

		let preview = RPGHUDPreviewView(viewModel: viewModel)
		panel.addSubview(headerTextStack)
		panel.addSubview(hudModePicker)
		panel.addSubview(preview)

		NSLayoutConstraint.activate([
			headerTextStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
			headerTextStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
			headerTextStack.trailingAnchor.constraint(
				lessThanOrEqualTo: hudModePicker.leadingAnchor, constant: -12),

			hudModePicker.centerYAnchor.constraint(equalTo: headerTextStack.centerYAnchor),
			hudModePicker.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),

			preview.topAnchor.constraint(equalTo: headerTextStack.bottomAnchor, constant: 14),
			preview.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
			preview.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
			preview.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
			preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
		])
		return panel
	}

	@objc private func hudModeChanged(_ sender: NSPopUpButton) {
		guard let mode = sender.selectedItem?.representedObject as? PetConfig.RPGHUDMode else { return }
		onHUDModeChanged(mode)
	}

	private func makeHudElementsPanel() -> NSView {
		let panel = settingsThemedCard()
		let title = settingsColumnHeader("HUD ELEMENTS")
		let subtitle = settingsBodyLabel("Current RPG state values shown by the in-session HUD.")
		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.spacing = 12
		let heartsRow = HUDElementRowView(
			icon: RPGHUDIconTileView(icon: makeSingleHeartIcon()),
			title: "Hearts",
			subtitle: "Represent your pet's health.",
			valueView: RPGHeartStripView(hearts: viewModel.hearts, heartSize: 22)
		)
		let levelRow = HUDElementRowView(
			icon: RPGHUDIconTileView(icon: RPGMiniRingIconView(fraction: viewModel.ringFraction)),
			title: "Level",
			subtitle: "Your pet's current level.",
			value: "\(viewModel.level)"
		)
		let xpRow = HUDElementRowView(
			icon: RPGHUDIconTileView(icon: RPGMiniXPBadgeView()),
			title: "XP Ring",
			subtitle: "Progress toward next level.",
			value: viewModel.xpPercentText,
			footer: RPGProgressBarView(fraction: viewModel.ringFraction)
		)
		stack.addArrangedSubview(heartsRow)
		stack.addArrangedSubview(levelRow)
		stack.addArrangedSubview(xpRow)
		// Hearts/Level have no footer so their intrinsic height is shorter than
		// XP Ring's (which carries a progress bar) — pin them equal so the row
		// backgrounds line up and the centered icon tile never overflows past a
		// short row's border.
		NSLayoutConstraint.activate([
			heartsRow.heightAnchor.constraint(equalTo: xpRow.heightAnchor),
			levelRow.heightAnchor.constraint(equalTo: xpRow.heightAnchor),
		])

		panel.addSubview(title)
		panel.addSubview(subtitle)
		panel.addSubview(stack)
		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
			title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
			title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),

			subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
			subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

			stack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
			stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
			stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
		])
		return panel
	}

	private func makeSingleHeartIcon() -> NSView {
		let heart = RPGHeartView(frame: .zero)
		heart.translatesAutoresizingMaskIntoConstraints = false
		heart.setState(.full)
		NSLayoutConstraint.activate([
			heart.widthAnchor.constraint(equalToConstant: 28),
			heart.heightAnchor.constraint(equalToConstant: 28),
		])
		return heart
	}

	private func makeHealthConfigurationPanel() -> NSView {
		let panel = settingsThemedCard()
		let title = settingsColumnHeader("HEALTH CONFIGURATION")
		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.distribution = .fillEqually
		stack.spacing = 12

		configurePopup(
			decayHoursPicker,
			options: RPGTabViewModel.inactivityDecayHourOptions,
			selected: viewModel.healthLogic.inactivityDecayHours,
			label: { "\(Int($0)) hours" },
			fixedWidth: 126
		)
		configurePopup(
			regenMinutesPicker,
			options: RPGTabViewModel.activityRegenMinuteOptions,
			selected: viewModel.healthLogic.activityRegenMinutes,
			label: { $0 == 60 ? "60 minutes" : "\($0) minutes" },
			fixedWidth: 126
		)
		skipWeekendsSwitch.state = viewModel.healthLogic.skipWeekends ? .on : .off
		skipWeekendsSwitch.target = self
		skipWeekendsSwitch.action = #selector(skipWeekendsChanged)
		skipWeekendsSwitch.translatesAutoresizingMaskIntoConstraints = false

		stack.addArrangedSubview(
			settingRow(
				title: "Inactivity Decay Config",
				value: "Lose 1/2 heart after sustained inactivity.",
				controls: [decayHoursPicker]))
		stack.addArrangedSubview(
			settingRow(
				title: "Activity Regeneration",
				value: "Regain 1/2 heart after active coding time.",
				controls: [regenMinutesPicker]))
		stack.addArrangedSubview(
			settingRow(
				title: "Skip Weekends",
				value: "No health decay on weekends.",
				controls: [skipWeekendsSwitch]))

		panel.addSubview(title)
		panel.addSubview(stack)
		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
			title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
			title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
			stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
			stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
			stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
		])
		for row in stack.arrangedSubviews {
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return panel
	}

	private func makeSicknessConfigurationPanel() -> NSView {
		let panel = settingsThemedCard()
		let title = settingsColumnHeader("PET SICKNESS CONFIGURATION")
		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.distribution = .fillEqually
		stack.spacing = 12

		sicknessSwitch.state = viewModel.healthLogic.diseaseAnimationsEnabled ? .on : .off
		sicknessSwitch.target = self
		sicknessSwitch.action = #selector(sicknessAnimationsChanged)
		sicknessSwitch.translatesAutoresizingMaskIntoConstraints = false

		configureSicknessPopup(
			mildSicknessPicker,
			options: RPGTabViewModel.sicknessTriggerOptions,
			selected: viewModel.healthLogic.mildSicknessHalfHearts
		)
		configureSicknessPopup(
			severeSicknessPicker,
			options: viewModel.severeSicknessOptions,
			selected: viewModel.healthLogic.severeSicknessHalfHearts
		)

		stack.addArrangedSubview(
			settingRow(title: "Sickness animations", value: sicknessSummary, controls: [sicknessSwitch]))
		stack.addArrangedSubview(
			settingRow(
				title: "Mild Sickness animation triggers on:",
				value: "Heart level that triggers mild sickness.",
				controls: [mildSicknessPicker]))
		stack.addArrangedSubview(
			settingRow(
				title: "Severe Sickness animation triggers on:",
				value: "Heart level that triggers severe sickness.",
				controls: [severeSicknessPicker]))
		refreshSicknessSummary()

		panel.addSubview(title)
		panel.addSubview(stack)
		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
			title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
			title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
			stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
			stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
			stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
		])
		for row in stack.arrangedSubviews {
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return panel
	}

	/// Menu options are half-heart counts (`0` = Never). "Never" is the only
	/// textual option; every heart value renders as the literal heart state
	/// (e.g. 3/2 = a full heart followed by a half heart), image-only.
	///
	/// Items are built as `NSMenuItem`s rather than via `addItem(withTitle:)`
	/// because that API removes an existing item with the same title — and the
	/// image-only options all share the empty title, so they would collapse
	/// into a single entry.
	private func configureSicknessPopup(_ popup: NSPopUpButton, options: [Int], selected: Int) {
		popup.removeAllItems()
		popup.translatesAutoresizingMaskIntoConstraints = false
		popup.target = self
		popup.action = #selector(sicknessTriggerChanged)
		for option in options {
			let item = NSMenuItem(title: option == 0 ? "Never" : "", action: nil, keyEquivalent: "")
			item.representedObject = option
			item.image = Self.sicknessTriggerImage(option)
			popup.menu?.addItem(item)
		}
		let selectedIndex = options.firstIndex(of: selected) ?? 0
		popup.selectItem(at: selectedIndex)
		pinPopupWidth(popup, to: 126)
	}

	/// Composite strip of the literal heart state for a half-heart count:
	/// full hearts first, then the trailing half heart for odd values.
	private static func sicknessTriggerImage(_ halfHearts: Int) -> NSImage? {
		guard halfHearts > 0 else { return nil }
		let fullCount = halfHearts / 2
		let hasHalf = !halfHearts.isMultiple(of: 2)
		let heartCount = fullCount + (hasHalf ? 1 : 0)
		let heartSize: CGFloat = 18
		let gap: CGFloat = 4
		let width = CGFloat(heartCount) * heartSize + CGFloat(heartCount - 1) * gap
		return NSImage(size: NSSize(width: width, height: heartSize), flipped: false) { _ in
			var x: CGFloat = 0
			for index in 0..<heartCount {
				let name = index < fullCount ? "heart_full_health" : "heart_half_health"
				NSImage(named: name)?.draw(in: NSRect(x: x, y: 0, width: heartSize, height: heartSize))
				x += heartSize + gap
			}
			return true
		}
	}

	private func configurePopup<T: Equatable>(
		_ popup: NSPopUpButton,
		options: [T],
		selected: T,
		label: (T) -> String,
		action: Selector = #selector(healthPopupChanged),
		fixedWidth: CGFloat? = nil
	) {
		popup.removeAllItems()
		popup.translatesAutoresizingMaskIntoConstraints = false
		popup.target = self
		popup.action = action
		for option in options {
			popup.addItem(withTitle: label(option))
			popup.lastItem?.representedObject = option
		}
		let selectedIndex = options.firstIndex(of: selected) ?? 0
		popup.selectItem(at: selectedIndex)
		if let fixedWidth {
			pinPopupWidth(popup, to: fixedWidth)
		} else {
			NSLayoutConstraint.deactivate(popup.constraints.filter { $0.firstAttribute == .width })
			popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 126).isActive = true
		}
	}

	/// Pins a popup to an exact width. The pickers are shared instances that
	/// survive `reload(viewModel:)` rebuilds and live menu swaps (the severe
	/// picker is rebuilt whenever mild changes), and an intrinsic-size-driven
	/// width lets those rebuilds stretch the control mid-flight. An exact,
	/// once-installed constraint plus required hugging keeps the width stable.
	private func pinPopupWidth(_ popup: NSPopUpButton, to width: CGFloat) {
		popup.setContentHuggingPriority(.required, for: .horizontal)
		popup.setContentCompressionResistancePriority(.required, for: .horizontal)
		NSLayoutConstraint.deactivate(popup.constraints.filter { $0.firstAttribute == .width })
		popup.widthAnchor.constraint(equalToConstant: width).isActive = true
	}

	private func settingRow(title: String, value: String, controls: [NSView]) -> NSView {
		let valueLabel = settingsBodyLabel(value)
		return settingRow(title: title, value: valueLabel, controls: controls)
	}

	private func settingRow(title: String, value: NSTextField, controls: [NSView]) -> NSView {
		let row = settingsThemedCard()
		let label = settingsSectionTitle(title)
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		// The subtitle must wrap short of the trailing controls instead of
		// running underneath the vertically-centered toggle/dropdown.
		value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let controlStack = NSStackView(views: controls)
		controlStack.translatesAutoresizingMaskIntoConstraints = false
		controlStack.orientation = .horizontal
		controlStack.spacing = 8
		controlStack.setContentHuggingPriority(.required, for: .horizontal)
		controlStack.setContentCompressionResistancePriority(.required, for: .horizontal)
		row.addSubview(label)
		row.addSubview(value)
		row.addSubview(controlStack)
		NSLayoutConstraint.activate([
			label.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
			label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
			label.trailingAnchor.constraint(lessThanOrEqualTo: controlStack.leadingAnchor, constant: -12),
			controlStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			controlStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
			value.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
			value.leadingAnchor.constraint(equalTo: label.leadingAnchor),
			value.trailingAnchor.constraint(lessThanOrEqualTo: controlStack.leadingAnchor, constant: -12),
			value.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -13),
		])
		return row
	}

	@objc private func healthPopupChanged(_ sender: NSPopUpButton) {
		switch sender {
		case decayHoursPicker:
			if let value = sender.selectedItem?.representedObject as? Double {
				viewModel.setInactivityDecayHours(value)
			}
		case regenMinutesPicker:
			if let value = sender.selectedItem?.representedObject as? Int {
				viewModel.setActivityRegenMinutes(value)
			}
		default:
			break
		}
	}

	@objc private func sicknessAnimationsChanged() {
		viewModel.setDiseaseAnimationsEnabled(sicknessSwitch.state == .on)
		refreshSicknessSummary()
	}

	@objc private func skipWeekendsChanged() {
		viewModel.setSkipWeekends(skipWeekendsSwitch.state == .on)
	}

	@objc private func sicknessTriggerChanged(_ sender: NSPopUpButton) {
		guard let value = sender.selectedItem?.representedObject as? Int else { return }
		switch sender {
		case mildSicknessPicker:
			viewModel.setMildSicknessHalfHearts(value)
			// Mild caps severe exclusively, so the severe menu is rebuilt from the
			// surviving options; the view-model already snapped an invalidated
			// severe value to the maximal valid one.
			configureSicknessPopup(
				severeSicknessPicker,
				options: viewModel.severeSicknessOptions,
				selected: viewModel.healthLogic.severeSicknessHalfHearts
			)
		case severeSicknessPicker:
			viewModel.setSevereSicknessHalfHearts(value)
		default:
			break
		}
	}

	private func refreshSicknessSummary() {
		sicknessSummary.stringValue = viewModel.healthLogic.diseaseAnimationsEnabled
			? "Low-health illness visuals can appear."
			: "Health still runs; illness visuals are suppressed."
	}
}

private final class RPGHUDPreviewView: NSView {
	private let hearts: RPGHeartStripView
	private let ring = RPGRingView(frame: .zero)
	private let petView = NSImageView()
	private let fallbackLabel = settingsBodyLabel("Default pet preview unavailable")
	private let ringFraction: Double
	private let level: Int

	init(viewModel: RPGTabViewModel) {
		self.hearts = RPGHeartStripView(hearts: viewModel.hearts, heartSize: 24)
		self.ringFraction = viewModel.ringFraction
		self.level = viewModel.level
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor
		layer?.backgroundColor = SettingsTheme.windowBackground.withAlphaComponent(0.55).cgColor

		for view in [hearts, ring, petView, fallbackLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		petView.image = viewModel.petImage
		petView.imageScaling = .scaleProportionallyUpOrDown
		fallbackLabel.alignment = .center
		fallbackLabel.isHidden = viewModel.petImage != nil
		ring.configure(fraction: ringFraction, level: level, ringDiameter: 96)

		// Geometry is tuned against the 320pt preview panel (see RPGTabView's
		// column constraints): the HUD column (hearts + ring) sits compact on
		// the left, and the pet takes the reclaimed space — pinned to the
		// preview's vertical bounds rather than a fixed height so it always
		// renders as large as the panel allows without overflowing it.
		NSLayoutConstraint.activate([
			hearts.topAnchor.constraint(equalTo: topAnchor, constant: 32),
			hearts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
			hearts.widthAnchor.constraint(equalToConstant: 90),
			hearts.heightAnchor.constraint(equalToConstant: 28),

			ring.topAnchor.constraint(equalTo: hearts.bottomAnchor, constant: 18),
			ring.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 46),
			ring.widthAnchor.constraint(equalToConstant: 96),
			ring.heightAnchor.constraint(equalToConstant: 96),

			petView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
			petView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
			petView.leadingAnchor.constraint(equalTo: ring.trailingAnchor, constant: 36),
			petView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
			petView.widthAnchor.constraint(equalToConstant: 210),

			fallbackLabel.centerXAnchor.constraint(equalTo: petView.centerXAnchor),
			fallbackLabel.centerYAnchor.constraint(equalTo: petView.centerYAnchor),
			fallbackLabel.widthAnchor.constraint(lessThanOrEqualTo: petView.widthAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

private final class RPGHeartStripView: NSView {
	private let hearts: [HeartState]
	private let heartSize: CGFloat
	private let spacing: CGFloat = 6

	init(hearts: [HeartState], heartSize: CGFloat) {
		self.hearts = hearts
		self.heartSize = heartSize
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .horizontal
		stack.spacing = spacing
		addSubview(stack)
		for state in hearts {
			let heart = RPGHeartView(frame: .zero)
			heart.translatesAutoresizingMaskIntoConstraints = false
			heart.setState(state)
			stack.addArrangedSubview(heart)
			NSLayoutConstraint.activate([
				heart.widthAnchor.constraint(equalToConstant: heartSize),
				heart.heightAnchor.constraint(equalToConstant: heartSize),
			])
		}
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	override var intrinsicContentSize: NSSize {
		let count = CGFloat(hearts.count)
		let width = count * heartSize + max(0, count - 1) * spacing
		return NSSize(width: width, height: heartSize)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

private final class RPGHUDIconTileView: NSView {
	init(icon: NSView) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
		layer?.borderWidth = 1
		layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
		icon.translatesAutoresizingMaskIntoConstraints = false
		addSubview(icon)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 54),
			heightAnchor.constraint(equalToConstant: 54),
			icon.centerXAnchor.constraint(equalTo: centerXAnchor),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

private final class RPGMiniRingIconView: NSView {
	private let shapeLayer = CAShapeLayer()

	init(fraction: Double) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.addSublayer(shapeLayer)
		shapeLayer.fillColor = NSColor.clear.cgColor
		shapeLayer.strokeColor = NSColor.systemYellow.cgColor
		shapeLayer.lineWidth = 4
		shapeLayer.lineCap = .round
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 34),
			heightAnchor.constraint(equalToConstant: 34),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	override func layout() {
		super.layout()
		let inset: CGFloat = 6
		let rect = bounds.insetBy(dx: inset, dy: inset)
		let path = CGMutablePath()
		path.addEllipse(in: rect)
		shapeLayer.frame = bounds
		shapeLayer.path = path
	}
}

private final class RPGMiniXPBadgeView: NSView {
	override init(frame: NSRect) {
		super.init(frame: frame)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 17
		layer?.borderWidth = 4
		layer?.borderColor = NSColor.systemGreen.cgColor
		let label = NSTextField(labelWithString: "XP")
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: 11, weight: .heavy)
		label.textColor = .white
		addSubview(label)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 34),
			heightAnchor.constraint(equalToConstant: 34),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

private final class RPGProgressBarView: NSView {
	private let fill = NSView()
	private let fraction: Double

	init(fraction: Double) {
		self.fraction = fraction.isFinite ? max(0, min(1, fraction)) : 0
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 5
		layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
		fill.translatesAutoresizingMaskIntoConstraints = false
		fill.wantsLayer = true
		fill.layer?.cornerRadius = 5
		fill.layer?.backgroundColor = NSColor.systemYellow.cgColor
		addSubview(fill)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 10),
			fill.leadingAnchor.constraint(equalTo: leadingAnchor),
			fill.topAnchor.constraint(equalTo: topAnchor),
			fill.bottomAnchor.constraint(equalTo: bottomAnchor),
			fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: self.fraction),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

private final class HUDElementRowView: NSView {
	init(icon: NSView, title: String, subtitle: String, value: String? = nil, valueView: NSView? = nil, footer: NSView? = nil) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor
		layer?.backgroundColor = SettingsTheme.windowBackground.withAlphaComponent(0.45).cgColor

		let titleLabel = settingsSectionTitle(title)
		titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		let subtitleLabel = settingsBodyLabel(subtitle)
		let valueLabel = value.map { text -> NSTextField in
			let label = settingsSectionTitle(text)
			label.font = .systemFont(ofSize: 15, weight: .bold)
			label.alignment = .right
			return label
		}

		for view in [icon, titleLabel, subtitleLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		if let valueLabel {
			addSubview(valueLabel)
		}
		if let valueView {
			valueView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(valueView)
		}
		if let footer {
			footer.translatesAutoresizingMaskIntoConstraints = false
			addSubview(footer)
		}

		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14),
			icon.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),

			titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
			titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

			subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
		])

		if let valueLabel {
			NSLayoutConstraint.activate([
				valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
				valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -16),
			])
		}
		if let valueView {
			NSLayoutConstraint.activate([
				valueView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
				valueView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueView.leadingAnchor, constant: -16),
			])
		}
		if let footer {
			NSLayoutConstraint.activate([
				footer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
				footer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
				footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
			])
		} else {
			// Minimum only (not equality): an external equal-height constraint
			// (Hearts/Level pinned to XP Ring's taller height, in
			// makeHudElementsPanel) stretches this row past its intrinsic
			// content height, and a required equality here would conflict with
			// that at required priority.
			bottomAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.bottomAnchor, constant: 14)
				.isActive = true
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

// MARK: - DeveloperTabView

/// Developer tab — read-only observability. Shows state.json, gate.json,
/// last 5 transitions, schema version, hooks summary, and platform attribution note.
private final class DeveloperTabView: NSView {
	private var viewModel: DeveloperTabViewModel
	private let scrollView = NSScrollView()
	private let textView = NSTextView()
	private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
	private let openDataButton = NSButton(title: "Open data folder", target: nil, action: nil)

	init(viewModel: DeveloperTabViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
		renderContent()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.developer.symbolName, color: .systemOrange)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("Developer")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		refreshButton.bezelStyle = .rounded
		refreshButton.target = self
		refreshButton.action = #selector(refresh)
		refreshButton.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(refreshButton)

		openDataButton.bezelStyle = .rounded
		openDataButton.target = self
		openDataButton.action = #selector(openDataFolder)
		openDataButton.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(openDataButton)

		textView.isEditable = false
		textView.isSelectable = true
		textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		textView.backgroundColor = SettingsTheme.tableBackground
		textView.textContainerInset = NSSize(width: 8, height: 8)
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		scrollView.borderType = .noBorder
		scrollView.wantsLayer = true
		scrollView.layer?.cornerRadius = 8
		scrollView.layer?.borderWidth = 1
		scrollView.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(scrollView)

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.centerYAnchor.constraint(equalTo: headerBadge.centerYAnchor),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),

			refreshButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			refreshButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			openDataButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openDataButton.trailingAnchor.constraint(
				equalTo: refreshButton.leadingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: headerBadge.bottomAnchor, constant: 10),
			scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	private func renderContent() {
		var lines: [String] = []

		// Schema version
		let sv = viewModel.stateSchemaVersion
		let rv = viewModel.rendererSchemaVersion
		let mismatch = viewModel.schemaVersionMismatch
		lines.append("=== Schema ===")
		lines.append("state.d/ (latest): v\(sv == 0 ? "?" : "\(sv)")   renderer: v\(rv)")
		if mismatch {
			lines.append("⚠️ VERSION MISMATCH — schema v\(sv) is not v\(rv). Update the app or reinstall the hook.")
		}
		lines.append("")

		// Hooks summary
		if let summary = viewModel.hooksPresentSummary {
			lines.append("=== Hooks ===")
			lines.append(summary)
			lines.append("")
		}

		// Last 5 transitions
		lines.append("=== Last 5 Transitions ===")
		let transitions = viewModel.last5Transitions
		if transitions.isEmpty {
			lines.append("(no transitions recorded)")
		} else {
			for t in transitions {
				var parts = [t.ts, "→ \(t.state)"]
				if let p = t.prev { parts.append("(was: \(p))") }
				if let o = t.sourceOrigin { parts.append("via: \(o)") }
				if let k = t.sourceKind { parts.append("[\(k)]") }
				if let n = t.sourceName { parts.append(n) }
				lines.append(parts.joined(separator: "  "))
			}
		}
		lines.append("")

		// Which platform last drove the pet.
		if let origin = viewModel.lastSeenSourceOrigin {
			lines.append("=== Platform attribution ===")
			let name = viewModel.lastSeenSourceName ?? "(unknown tool)"
			if origin == "cursor" {
				lines.append("Last seen from Cursor (\(name)).")
			} else if origin == "claude_code" {
				lines.append("Last seen from Claude Code (\(name)).")
			} else {
				lines.append("Last seen from \(origin) (\(name)).")
			}
			lines.append("")
		}

		// latest slice from state.d/
		lines.append("=== state.d/ (latest slice) ===")
		lines.append(viewModel.stateJsonPretty)
		lines.append("")

		// gate.json (per-origin state.d/ slice when present, else the legacy flat file)
		if let gatePretty = viewModel.gateJsonPretty {
			lines.append("=== \(viewModel.gateJsonSourceLabel) (latest) ===")
			lines.append(gatePretty)
			lines.append("")
		}

		// delivery-context.json (per-origin state.d/ slice when present, else the legacy flat file)
		if let deliveryContextPretty = viewModel.deliveryContextPretty {
			lines.append("=== \(viewModel.deliveryContextSourceLabel) (latest) ===")
			lines.append(deliveryContextPretty)
		}

		textView.string = lines.joined(separator: "\n")
	}

	@objc private func refresh() {
		renderContent()
	}

	@objc private func openDataFolder() {
		CodogotchiFolders.reveal(CodogotchiFolders.dataFolderURL())
	}
}

// MARK: - CustomizationTabView

/// Customization tab — per-platform mode pickers and idle-dismiss TTL.
///
/// Origins are shown in the fixed order defined by `CustomizationTabViewModel.origins`
/// so the UI is stable across sessions regardless of which platforms are active.
private final class CustomizationTabView: NSView {
	private var viewModel: CustomizationTabViewModel
	private var modePickers: [String: NSPopUpButton] = [:]
	private var sessionsPickers: [String: NSPopUpButton] = [:]
	private var sessionCapPickers: [String: NSPopUpButton] = [:]
	private var ttlPicker: NSPopUpButton = NSPopUpButton()
	private var impatientPicker: NSPopUpButton = NSPopUpButton()
	private var frustratedPicker: NSPopUpButton = NSPopUpButton()
	private var evictSessionPetsPicker: NSPopUpButton = NSPopUpButton()
	private var combinedMinimalistCheckbox = NSButton()
	private var badgeScaleSlider = NSSlider()

	/// Wide enough to fit "Minimalist", the longest `PlatformMode` label, without truncation.
	private static let modeColumnWidth: CGFloat = 120
	/// Width of the centered "Sessions" column (dropdown with "Enabled"/"Disabled").
	private static let sessionsColumnWidth: CGFloat = 110
	/// Fixed content width for the Platform Settings card: label(110) + mode
	/// picker + sessions column + cap picker(110), plus row/column gaps
	/// and the 16pt card margins on each side. Sized from content rather than
	/// stretched full-width now that Minimalist Panel Options sits beside it
	/// as a second column.
	private static let platformCardWidth: CGFloat =
		16 + 110 + 8 + modeColumnWidth + 24 + sessionsColumnWidth + 24 + 110 + 16

	/// Observer for `.customizationDidChangeExternally` — a right-click mode
	/// switch on a floating panel writes customization.json through its own
	/// short-lived view model, so this tab's controls would silently go stale
	/// without a re-sync trigger.
	private var externalChangeObserver: NSObjectProtocol?

	init(viewModel: CustomizationTabViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
		externalChangeObserver = NotificationCenter.default.addObserver(
			forName: .customizationDidChangeExternally,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in self?.refreshFromDisk() }
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	deinit {
		if let externalChangeObserver {
			NotificationCenter.default.removeObserver(externalChangeObserver)
		}
	}

	/// Re-reads customization.json via the view model and re-syncs every
	/// control to the reloaded state, mirroring each control's initial
	/// selection logic in `setupViews`. Unmatchable persisted values (e.g. a
	/// hand-edited TTL between presets) keep the current selection rather than
	/// guessing, so a refresh never moves a picker to a value the file does
	/// not actually contain a preset for.
	private func refreshFromDisk() {
		viewModel.reload()
		for origin in CustomizationTabViewModel.origins {
			let mode = viewModel.mode(for: origin)
			modePickers[origin]?.selectItem(withTitle: mode.rawValue.capitalized)
			let sessionsEnabled = viewModel.sessionPetsEnabled[origin] == true
			sessionsPickers[origin]?.selectItem(withTitle: sessionsEnabled ? "Enabled" : "Disabled")
			sessionsPickers[origin]?.isEnabled = mode.supportsSessionPets
			let capOption =
				SessionCapOption.matching(viewModel.effectiveSessionCap(for: origin)) ?? .three
			sessionCapPickers[origin]?.selectItem(withTitle: capOption.label)
			sessionCapPickers[origin]?.isEnabled = mode.supportsSessionPets && sessionsEnabled
		}
		combinedMinimalistCheckbox.state = viewModel.combinedMinimalistEnabled ? .on : .off
		badgeScaleSlider.doubleValue = viewModel.minimalistBadgeScale
		if let preset = IdleDismissTTL.matching(viewModel.idleDismissTtlSeconds) {
			ttlPicker.selectItem(withTitle: preset.label)
		}
		if let preset = IdleEscalationTiming.matching(viewModel.idleImpatientSeconds) {
			impatientPicker.selectItem(withTitle: preset.label)
		}
		if let preset = IdleEscalationTiming.matching(viewModel.idleFrustratedSeconds) {
			frustratedPicker.selectItem(withTitle: preset.label)
		}
		evictSessionPetsPicker.selectItem(
			withTitle: viewModel.evictSessionPetsEnabled ? "Enabled" : "Disabled")
	}

	/// Styled inner panel used for the "Platform Settings", "Minimalist Panel
	/// Options", and idle/eviction sections. Uses the darker table shade (the
	/// Hooks table / monochrome-row treatment) so panels read as strips nested
	/// inside the tab's lighter wrapper card.
	private func makeSettingsCard() -> NSView {
		let card = NSView()
		card.translatesAutoresizingMaskIntoConstraints = false
		card.wantsLayer = true
		card.layer?.cornerRadius = 8
		card.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		card.layer?.borderWidth = 1
		card.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		return card
	}

	private func setupViews() {
		// Lighter wrapper card grouping the whole tab, mirroring the Hooks card
		// on General so every tab shares one design language: icon badge +
		// title + subtitle header, darker nested panels below.
		let wrapper = NSView()
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.wantsLayer = true
		wrapper.layer?.cornerRadius = 10
		wrapper.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
		wrapper.layer?.borderWidth = 1
		wrapper.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		addSubview(wrapper)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.customization.symbolName, color: .systemPurple)
		wrapper.addSubview(headerBadge)

		let title = settingsSectionTitle("Customization")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		wrapper.addSubview(title)

		let note = settingsBodyLabel(
			"Choose how each coding platform displays your pet.\n"
				+ "Own = dedicated floating window per tool. "
				+ "Combined = all active tools share one window. "
				+ "Minimalist = compact badge strip. "
				+ "Off = no window for that tool."
		)
		wrapper.addSubview(note)

		// MARK: Platform Settings card (left column)

		let platformCard = makeSettingsCard()
		wrapper.addSubview(platformCard)

		let platformBadge = settingsHeaderIconBadge(
			symbolName: "macwindow.on.rectangle", color: .systemBlue, side: 24)
		platformCard.addSubview(platformBadge)

		let platformTitle = settingsSectionTitle("Platform Settings")
		platformCard.addSubview(platformTitle)

		let modeHeader = settingsColumnHeader("Mode")
		platformCard.addSubview(modeHeader)
		let sessionsHeader = settingsColumnHeader("Sessions")
		sessionsHeader.alignment = .center
		platformCard.addSubview(sessionsHeader)
		let sessionCapHeader = settingsColumnHeader("Session Cap")
		platformCard.addSubview(sessionCapHeader)

		var previousAnchor: NSLayoutYAxisAnchor = sessionsHeader.bottomAnchor
		var previousConstant: CGFloat = 10

		for origin in CustomizationTabViewModel.origins {
			let label = NSTextField(labelWithString: displayName(for: origin))
			label.font = .systemFont(ofSize: 13)
			label.translatesAutoresizingMaskIntoConstraints = false
			platformCard.addSubview(label)

			let picker = NSPopUpButton()
			picker.translatesAutoresizingMaskIntoConstraints = false
			for mode in [PlatformMode.own, .combined, .minimalist, .off] {
				picker.addItem(withTitle: mode.rawValue.capitalized)
				picker.lastItem?.representedObject = mode
			}
			let mode = viewModel.mode(for: origin)
			picker.selectItem(withTitle: mode.rawValue.capitalized)
			picker.target = self
			picker.action = #selector(modePickerChanged(_:))
			picker.identifier = NSUserInterfaceItemIdentifier(origin)
			platformCard.addSubview(picker)
			modePickers[origin] = picker

			let sessionsPicker = NSPopUpButton()
			sessionsPicker.translatesAutoresizingMaskIntoConstraints = false
			for enabled in [true, false] {
				sessionsPicker.addItem(withTitle: enabled ? "Enabled" : "Disabled")
				sessionsPicker.lastItem?.representedObject = enabled
			}
			let sessionsEnabled = viewModel.sessionPetsEnabled[origin] == true
			sessionsPicker.selectItem(withTitle: sessionsEnabled ? "Enabled" : "Disabled")
			sessionsPicker.isEnabled = mode.supportsSessionPets
			sessionsPicker.identifier = NSUserInterfaceItemIdentifier(origin)
			sessionsPicker.target = self
			sessionsPicker.action = #selector(sessionsPickerChanged(_:))
			platformCard.addSubview(sessionsPicker)
			sessionsPickers[origin] = sessionsPicker

			let sessionCapPicker = NSPopUpButton()
			sessionCapPicker.translatesAutoresizingMaskIntoConstraints = false
			for option in SessionCapOption.allCases {
				sessionCapPicker.addItem(withTitle: option.label)
				sessionCapPicker.lastItem?.representedObject = option
			}
			let effectiveCap = viewModel.effectiveSessionCap(for: origin)
			let currentCapOption = SessionCapOption.matching(effectiveCap) ?? .three
			sessionCapPicker.selectItem(withTitle: currentCapOption.label)
			sessionCapPicker.isEnabled = mode.supportsSessionPets && sessionsEnabled
			sessionCapPicker.target = self
			sessionCapPicker.action = #selector(sessionCapPickerChanged(_:))
			sessionCapPicker.identifier = NSUserInterfaceItemIdentifier(origin)
			platformCard.addSubview(sessionCapPicker)
			sessionCapPickers[origin] = sessionCapPicker

			NSLayoutConstraint.activate([
				label.topAnchor.constraint(equalTo: previousAnchor, constant: previousConstant),
				label.leadingAnchor.constraint(equalTo: platformCard.leadingAnchor, constant: 16),
				label.widthAnchor.constraint(equalToConstant: 110),

				picker.centerYAnchor.constraint(equalTo: label.centerYAnchor),
				picker.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
				picker.widthAnchor.constraint(equalToConstant: Self.modeColumnWidth),

				sessionsPicker.centerYAnchor.constraint(equalTo: label.centerYAnchor),
				sessionsPicker.centerXAnchor.constraint(equalTo: sessionsHeader.centerXAnchor),
				sessionsPicker.widthAnchor.constraint(equalToConstant: Self.sessionsColumnWidth),

				sessionCapPicker.centerYAnchor.constraint(equalTo: label.centerYAnchor),
				sessionCapPicker.trailingAnchor.constraint(equalTo: platformCard.trailingAnchor, constant: -16),
				sessionCapPicker.widthAnchor.constraint(equalToConstant: 110),
			])
			previousAnchor = label.bottomAnchor
			previousConstant = 10
		}

		// MARK: Minimalist Panel Options card (right column, beside Platform Settings)

		let minimalistCard = makeSettingsCard()
		wrapper.addSubview(minimalistCard)

		let minimalistBadge = settingsHeaderIconBadge(
			symbolName: "slider.horizontal.3", color: .systemTeal, side: 24)
		minimalistCard.addSubview(minimalistBadge)

		let minimalistTitle = settingsSectionTitle("Minimalist Panel Options")
		minimalistCard.addSubview(minimalistTitle)

		combinedMinimalistCheckbox = NSButton(
			checkboxWithTitle: "Enable Minimalist mode for Combined pet",
			target: self,
			action: #selector(combinedMinimalistChanged(_:))
		)
		combinedMinimalistCheckbox.state = viewModel.combinedMinimalistEnabled ? .on : .off
		combinedMinimalistCheckbox.translatesAutoresizingMaskIntoConstraints = false
		minimalistCard.addSubview(combinedMinimalistCheckbox)

		let combinedMinimalistNote = settingsBodyLabel(
			"When enabled, all platforms set to Combined render to a single Minimalist-mode panel."
		)
		minimalistCard.addSubview(combinedMinimalistNote)

		let scaleLabel = NSTextField(labelWithString: "PlatformChip and AnimationBadge Size:")
		scaleLabel.font = .systemFont(ofSize: 13)
		scaleLabel.translatesAutoresizingMaskIntoConstraints = false
		minimalistCard.addSubview(scaleLabel)

		badgeScaleSlider.translatesAutoresizingMaskIntoConstraints = false
		badgeScaleSlider.minValue = Double(GateBadgeLayout.achievableMinScale)
		badgeScaleSlider.maxValue = Double(GateBadgeLayout.achievableMaxScale)
		badgeScaleSlider.doubleValue = viewModel.minimalistBadgeScale
		badgeScaleSlider.isContinuous = true
		badgeScaleSlider.target = self
		badgeScaleSlider.action = #selector(badgeScaleChanged(_:))
		minimalistCard.addSubview(badgeScaleSlider)

		let smallLabel = NSTextField(labelWithString: "Small")
		smallLabel.font = .systemFont(ofSize: 11)
		smallLabel.textColor = .secondaryLabelColor
		smallLabel.translatesAutoresizingMaskIntoConstraints = false
		minimalistCard.addSubview(smallLabel)

		let largeLabel = NSTextField(labelWithString: "Large")
		largeLabel.font = .systemFont(ofSize: 11)
		largeLabel.textColor = .secondaryLabelColor
		largeLabel.translatesAutoresizingMaskIntoConstraints = false
		minimalistCard.addSubview(largeLabel)

		let scaleNote = settingsBodyLabel(
			"Adjusts the size of the Minimalist PlatformChip and AnimationBadge."
		)
		minimalistCard.addSubview(scaleNote)

		// The card is stretched to match Platform Settings' height, so its content
		// is shorter than the card. Equal-height spacer guides above and below the
		// content block center it vertically instead of leaving all the slack as
		// bottom padding.
		let minimalistTopSpacer = NSLayoutGuide()
		let minimalistBottomSpacer = NSLayoutGuide()
		minimalistCard.addLayoutGuide(minimalistTopSpacer)
		minimalistCard.addLayoutGuide(minimalistBottomSpacer)

		// MARK: Pet Idle Preferences card (left column, below Platform Settings)

		let idleCard = makeSettingsCard()
		wrapper.addSubview(idleCard)

		let idleBadge = settingsHeaderIconBadge(
			symbolName: "moon.zzz.fill", color: .systemIndigo, side: 24)
		idleCard.addSubview(idleBadge)

		let idleTitle = settingsSectionTitle("Pet Idle Preferences")
		idleCard.addSubview(idleTitle)

		let ttlLabel = NSTextField(labelWithString: "Hide Idle Pet After:")
		ttlLabel.font = .systemFont(ofSize: 13)
		ttlLabel.translatesAutoresizingMaskIntoConstraints = false
		idleCard.addSubview(ttlLabel)

		ttlPicker.translatesAutoresizingMaskIntoConstraints = false
		for preset in IdleDismissTTL.allCases {
			ttlPicker.addItem(withTitle: preset.label)
			ttlPicker.lastItem?.representedObject = preset
		}
		let currentPreset = IdleDismissTTL.matching(viewModel.idleDismissTtlSeconds)
		if let preset = currentPreset {
			ttlPicker.selectItem(withTitle: preset.label)
		} else {
			ttlPicker.selectItem(withTitle: IdleDismissTTL.fiveMinutes.label)
		}
		ttlPicker.target = self
		ttlPicker.action = #selector(ttlPickerChanged(_:))
		idleCard.addSubview(ttlPicker)

		let ttlNote = settingsBodyLabel(
			"\"Never\" keeps the pet visible until you switch tools or quit. "
				+ "Changes take effect on the next poll cycle."
		)
		idleCard.addSubview(ttlNote)

		// Thin divider between the Idle Dismiss and Escalation Timing sections.
		let idleSeparator = NSView()
		idleSeparator.translatesAutoresizingMaskIntoConstraints = false
		idleSeparator.wantsLayer = true
		idleSeparator.layer?.backgroundColor = SettingsTheme.cardBorder.cgColor
		idleCard.addSubview(idleSeparator)

		// MARK: Pet Idle Escalation Timing (inside the Pet Idle Preferences card, below Idle Dismiss)

		let escalationTitle = settingsSectionTitle("Pet Idle Escalation Timing")
		idleCard.addSubview(escalationTitle)

		let impatientLabel = NSTextField(labelWithString: "Pet Idle Impatient After:")
		impatientLabel.font = .systemFont(ofSize: 13)
		impatientLabel.translatesAutoresizingMaskIntoConstraints = false
		idleCard.addSubview(impatientLabel)

		impatientPicker.translatesAutoresizingMaskIntoConstraints = false
		for preset in IdleEscalationTiming.allCases {
			impatientPicker.addItem(withTitle: preset.label)
			impatientPicker.lastItem?.representedObject = preset
		}
		if let preset = IdleEscalationTiming.matching(viewModel.idleImpatientSeconds) {
			impatientPicker.selectItem(withTitle: preset.label)
		} else {
			impatientPicker.selectItem(withTitle: IdleEscalationTiming.fiveMinutes.label)
		}
		impatientPicker.target = self
		impatientPicker.action = #selector(impatientPickerChanged(_:))
		idleCard.addSubview(impatientPicker)

		let frustratedLabel = NSTextField(labelWithString: "Pet Idle Frustrated After:")
		frustratedLabel.font = .systemFont(ofSize: 13)
		frustratedLabel.translatesAutoresizingMaskIntoConstraints = false
		idleCard.addSubview(frustratedLabel)

		frustratedPicker.translatesAutoresizingMaskIntoConstraints = false
		for preset in IdleEscalationTiming.allCases {
			frustratedPicker.addItem(withTitle: preset.label)
			frustratedPicker.lastItem?.representedObject = preset
		}
		if let preset = IdleEscalationTiming.matching(viewModel.idleFrustratedSeconds) {
			frustratedPicker.selectItem(withTitle: preset.label)
		} else {
			frustratedPicker.selectItem(withTitle: IdleEscalationTiming.tenMinutes.label)
		}
		frustratedPicker.target = self
		frustratedPicker.action = #selector(frustratedPickerChanged(_:))
		idleCard.addSubview(frustratedPicker)

		let escalationNote = settingsBodyLabel(
			"Controls when an idle pet's badge reads \"Impatient\" then \"Frustrated\". "
				+ "Frustrated After automatically stays one step above Impatient After."
		)
		idleCard.addSubview(escalationNote)

		// MARK: Pet Session Eviction Policy card (right column, beside Pet Idle Preferences)

		let evictionCard = makeSettingsCard()
		wrapper.addSubview(evictionCard)

		let evictionBadge = settingsHeaderIconBadge(
			symbolName: "shield.fill", color: .systemBlue, side: 24)
		evictionCard.addSubview(evictionBadge)

		let evictionTitle = settingsSectionTitle("Pet Session Eviction Policy")
		evictionCard.addSubview(evictionTitle)

		let evictionLabel = NSTextField(labelWithString: "Evict Session Pets:")
		evictionLabel.font = .systemFont(ofSize: 13)
		evictionLabel.translatesAutoresizingMaskIntoConstraints = false
		evictionCard.addSubview(evictionLabel)

		evictSessionPetsPicker.translatesAutoresizingMaskIntoConstraints = false
		evictSessionPetsPicker.addItem(withTitle: "Enabled")
		evictSessionPetsPicker.lastItem?.representedObject = true
		evictSessionPetsPicker.addItem(withTitle: "Disabled")
		evictSessionPetsPicker.lastItem?.representedObject = false
		evictSessionPetsPicker.selectItem(withTitle: viewModel.evictSessionPetsEnabled ? "Enabled" : "Disabled")
		evictSessionPetsPicker.target = self
		evictSessionPetsPicker.action = #selector(evictSessionPetsPickerChanged(_:))
		evictionCard.addSubview(evictSessionPetsPicker)

		let evictionNote = settingsBodyLabel(
			"When Enabled, a new session can evict an idle sibling session once its "
				+ "platform's Session Cap is full (today's default behavior). "
				+ "Disabled protects every existing session from eviction — a new "
				+ "session waits for a slot to open on its own."
		)
		evictionCard.addSubview(evictionNote)

		let rowsTop = note.bottomAnchor

		// The bottom row of cards sits below whichever of the two top cards is
		// taller (Platform Settings, with one row per origin, is expected to
		// usually be the taller one, but this must not assume that).
		let idleBelowPlatform = idleCard.topAnchor.constraint(
			greaterThanOrEqualTo: platformCard.bottomAnchor, constant: 24)
		let idleBelowMinimalist = idleCard.topAnchor.constraint(
			greaterThanOrEqualTo: minimalistCard.bottomAnchor, constant: 24)
		let idlePrefersBelowPlatform = idleCard.topAnchor.constraint(
			equalTo: platformCard.bottomAnchor, constant: 24)
		idlePrefersBelowPlatform.priority = .defaultHigh

		NSLayoutConstraint.activate([
			wrapper.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			wrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			wrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			wrapper.bottomAnchor.constraint(equalTo: idleCard.bottomAnchor, constant: 20),

			headerBadge.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),

			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),
			title.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 18),
			title.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			note.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			note.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			// Platform Settings (left column) and Minimalist Panel Options (right
			// column) sit side by side; Idle Dismiss stacks full-width below both.
			platformCard.topAnchor.constraint(equalTo: rowsTop, constant: 16),
			platformCard.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			platformCard.widthAnchor.constraint(equalToConstant: Self.platformCardWidth),

			platformBadge.centerYAnchor.constraint(equalTo: platformTitle.centerYAnchor),
			platformBadge.leadingAnchor.constraint(equalTo: platformCard.leadingAnchor, constant: 16),

			platformTitle.topAnchor.constraint(equalTo: platformCard.topAnchor, constant: 16),
			platformTitle.leadingAnchor.constraint(equalTo: platformBadge.trailingAnchor, constant: 10),
			platformTitle.trailingAnchor.constraint(equalTo: platformCard.trailingAnchor, constant: -16),

			modeHeader.topAnchor.constraint(equalTo: platformTitle.bottomAnchor, constant: 14),
			modeHeader.leadingAnchor.constraint(equalTo: platformCard.leadingAnchor, constant: 16 + 110 + 8),
			modeHeader.widthAnchor.constraint(equalToConstant: Self.modeColumnWidth),

			sessionsHeader.centerYAnchor.constraint(equalTo: modeHeader.centerYAnchor),
			sessionsHeader.leadingAnchor.constraint(equalTo: modeHeader.trailingAnchor, constant: 24),
			sessionsHeader.widthAnchor.constraint(equalToConstant: Self.sessionsColumnWidth),

			sessionCapHeader.centerYAnchor.constraint(equalTo: modeHeader.centerYAnchor),
			sessionCapHeader.trailingAnchor.constraint(equalTo: platformCard.trailingAnchor, constant: -16),
			sessionCapHeader.widthAnchor.constraint(equalToConstant: 110),

			previousAnchor.constraint(equalTo: platformCard.bottomAnchor, constant: -16),

			// Minimalist Panel Options (right column, same top as Platform Settings).
			minimalistCard.topAnchor.constraint(equalTo: rowsTop, constant: 16),
			minimalistCard.leadingAnchor.constraint(equalTo: platformCard.trailingAnchor, constant: 20),
			minimalistCard.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			minimalistBadge.centerYAnchor.constraint(equalTo: minimalistTitle.centerYAnchor),
			minimalistBadge.leadingAnchor.constraint(equalTo: minimalistCard.leadingAnchor, constant: 16),

			minimalistTitle.topAnchor.constraint(equalTo: minimalistCard.topAnchor, constant: 16),
			minimalistTitle.leadingAnchor.constraint(equalTo: minimalistBadge.trailingAnchor, constant: 10),
			minimalistTitle.trailingAnchor.constraint(equalTo: minimalistCard.trailingAnchor, constant: -16),

			minimalistTopSpacer.topAnchor.constraint(equalTo: minimalistTitle.bottomAnchor),
			minimalistTopSpacer.bottomAnchor.constraint(
				equalTo: combinedMinimalistCheckbox.topAnchor),
			minimalistTopSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 10),

			minimalistBottomSpacer.topAnchor.constraint(equalTo: scaleNote.bottomAnchor),
			minimalistBottomSpacer.bottomAnchor.constraint(equalTo: minimalistCard.bottomAnchor),
			minimalistBottomSpacer.heightAnchor.constraint(
				equalTo: minimalistTopSpacer.heightAnchor),

			combinedMinimalistCheckbox.leadingAnchor.constraint(
				equalTo: minimalistCard.leadingAnchor, constant: 16),

			combinedMinimalistNote.topAnchor.constraint(
				equalTo: combinedMinimalistCheckbox.bottomAnchor, constant: 4),
			combinedMinimalistNote.leadingAnchor.constraint(
				equalTo: minimalistCard.leadingAnchor, constant: 16),
			combinedMinimalistNote.trailingAnchor.constraint(
				equalTo: minimalistCard.trailingAnchor, constant: -16),

			scaleLabel.topAnchor.constraint(equalTo: combinedMinimalistNote.bottomAnchor, constant: 16),
			scaleLabel.leadingAnchor.constraint(equalTo: minimalistCard.leadingAnchor, constant: 16),

			badgeScaleSlider.topAnchor.constraint(equalTo: scaleLabel.bottomAnchor, constant: 8),
			badgeScaleSlider.leadingAnchor.constraint(equalTo: smallLabel.trailingAnchor, constant: 6),
			badgeScaleSlider.trailingAnchor.constraint(equalTo: largeLabel.leadingAnchor, constant: -6),

			smallLabel.centerYAnchor.constraint(equalTo: badgeScaleSlider.centerYAnchor),
			smallLabel.leadingAnchor.constraint(equalTo: minimalistCard.leadingAnchor, constant: 16),

			largeLabel.centerYAnchor.constraint(equalTo: badgeScaleSlider.centerYAnchor),
			largeLabel.trailingAnchor.constraint(equalTo: minimalistCard.trailingAnchor, constant: -16),

			scaleNote.topAnchor.constraint(equalTo: badgeScaleSlider.bottomAnchor, constant: 6),
			scaleNote.leadingAnchor.constraint(equalTo: minimalistCard.leadingAnchor, constant: 16),
			scaleNote.trailingAnchor.constraint(equalTo: minimalistCard.trailingAnchor, constant: -16),

			// Match the Platform Settings card's height for visual symmetry, since
			// both cards share the same top anchor (rowsTop + 20).
			minimalistCard.bottomAnchor.constraint(equalTo: platformCard.bottomAnchor),

			// Pet Idle Preferences (left column, same width as Platform Settings).
			idleBelowPlatform, idleBelowMinimalist, idlePrefersBelowPlatform,
			idleCard.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			idleCard.trailingAnchor.constraint(equalTo: platformCard.trailingAnchor),

			idleBadge.centerYAnchor.constraint(equalTo: idleTitle.centerYAnchor),
			idleBadge.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),

			idleTitle.topAnchor.constraint(equalTo: idleCard.topAnchor, constant: 16),
			idleTitle.leadingAnchor.constraint(equalTo: idleBadge.trailingAnchor, constant: 10),
			idleTitle.trailingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: -16),

			ttlLabel.topAnchor.constraint(equalTo: idleTitle.bottomAnchor, constant: 14),
			ttlLabel.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			ttlLabel.widthAnchor.constraint(equalToConstant: 170),

			ttlPicker.centerYAnchor.constraint(equalTo: ttlLabel.centerYAnchor),
			ttlPicker.leadingAnchor.constraint(equalTo: ttlLabel.trailingAnchor, constant: 8),
			ttlPicker.widthAnchor.constraint(equalToConstant: 130),

			ttlNote.topAnchor.constraint(equalTo: ttlLabel.bottomAnchor, constant: 8),
			ttlNote.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			ttlNote.trailingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: -16),

			idleSeparator.topAnchor.constraint(equalTo: ttlNote.bottomAnchor, constant: 14),
			idleSeparator.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			idleSeparator.trailingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: -16),
			idleSeparator.heightAnchor.constraint(equalToConstant: 1),

			escalationTitle.topAnchor.constraint(equalTo: idleSeparator.bottomAnchor, constant: 14),
			escalationTitle.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			escalationTitle.trailingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: -16),

			impatientLabel.topAnchor.constraint(equalTo: escalationTitle.bottomAnchor, constant: 10),
			impatientLabel.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			impatientLabel.widthAnchor.constraint(equalToConstant: 190),

			impatientPicker.centerYAnchor.constraint(equalTo: impatientLabel.centerYAnchor),
			impatientPicker.leadingAnchor.constraint(equalTo: impatientLabel.trailingAnchor, constant: 8),
			impatientPicker.widthAnchor.constraint(equalToConstant: 130),

			frustratedLabel.topAnchor.constraint(equalTo: impatientLabel.bottomAnchor, constant: 10),
			frustratedLabel.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			frustratedLabel.widthAnchor.constraint(equalToConstant: 190),

			frustratedPicker.centerYAnchor.constraint(equalTo: frustratedLabel.centerYAnchor),
			frustratedPicker.leadingAnchor.constraint(equalTo: frustratedLabel.trailingAnchor, constant: 8),
			frustratedPicker.widthAnchor.constraint(equalToConstant: 130),

			escalationNote.topAnchor.constraint(equalTo: frustratedLabel.bottomAnchor, constant: 8),
			escalationNote.leadingAnchor.constraint(equalTo: idleCard.leadingAnchor, constant: 16),
			escalationNote.trailingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: -16),
			escalationNote.bottomAnchor.constraint(equalTo: idleCard.bottomAnchor, constant: -16),

			// Pet Session Eviction Policy (right column, same top and bottom as
			// Pet Idle Preferences; content is shorter, so slack stays at the
			// bottom of the card).
			evictionCard.topAnchor.constraint(equalTo: idleCard.topAnchor),
			evictionCard.leadingAnchor.constraint(equalTo: idleCard.trailingAnchor, constant: 20),
			evictionCard.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
			evictionCard.bottomAnchor.constraint(equalTo: idleCard.bottomAnchor),

			evictionBadge.centerYAnchor.constraint(equalTo: evictionTitle.centerYAnchor),
			evictionBadge.leadingAnchor.constraint(equalTo: evictionCard.leadingAnchor, constant: 16),

			evictionTitle.topAnchor.constraint(equalTo: evictionCard.topAnchor, constant: 16),
			evictionTitle.leadingAnchor.constraint(equalTo: evictionBadge.trailingAnchor, constant: 10),
			evictionTitle.trailingAnchor.constraint(equalTo: evictionCard.trailingAnchor, constant: -16),

			evictionLabel.topAnchor.constraint(equalTo: evictionTitle.bottomAnchor, constant: 14),
			evictionLabel.leadingAnchor.constraint(equalTo: evictionCard.leadingAnchor, constant: 16),
			evictionLabel.widthAnchor.constraint(equalToConstant: 140),

			evictSessionPetsPicker.centerYAnchor.constraint(equalTo: evictionLabel.centerYAnchor),
			evictSessionPetsPicker.leadingAnchor.constraint(equalTo: evictionLabel.trailingAnchor, constant: 8),
			evictSessionPetsPicker.widthAnchor.constraint(equalToConstant: 130),

			evictionNote.topAnchor.constraint(equalTo: evictionLabel.bottomAnchor, constant: 12),
			evictionNote.leadingAnchor.constraint(equalTo: evictionCard.leadingAnchor, constant: 16),
			evictionNote.trailingAnchor.constraint(equalTo: evictionCard.trailingAnchor, constant: -16),
			evictionNote.bottomAnchor.constraint(lessThanOrEqualTo: evictionCard.bottomAnchor, constant: -16),
		])
	}

	private func displayName(for origin: String) -> String {
		switch origin {
		case "claude_code": return "Claude Code"
		case "vscode": return "VS Code"
		case "codex": return "Codex"
		case "cursor": return "Cursor"
		case "antigravity": return "Antigravity"
		default: return origin
		}
	}

	@objc private func modePickerChanged(_ sender: NSPopUpButton) {
		guard
			let origin = sender.identifier?.rawValue,
			let mode = sender.selectedItem?.representedObject as? PlatformMode
		else { return }
		viewModel.setMode(mode, for: origin)
		// Mode gates interactivity only — it never touches a stored session-pets
		// picker or cap value, so Combined/Off can be toggled back to
		// Own/Minimalist without losing anything.
		let picker = sessionsPickers[origin]
		picker?.isEnabled = mode.supportsSessionPets
		let enabled = picker?.selectedItem?.representedObject as? Bool ?? false
		sessionCapPickers[origin]?.isEnabled = mode.supportsSessionPets && enabled
	}

	@objc private func sessionsPickerChanged(_ sender: NSPopUpButton) {
		guard
			let origin = sender.identifier?.rawValue,
			let enabled = sender.selectedItem?.representedObject as? Bool
		else { return }
		viewModel.setSessionPetsEnabled(enabled, for: origin)
		sessionCapPickers[origin]?.isEnabled = enabled && viewModel.mode(for: origin).supportsSessionPets
	}

	@objc private func sessionCapPickerChanged(_ sender: NSPopUpButton) {
		guard
			let origin = sender.identifier?.rawValue,
			let option = sender.selectedItem?.representedObject as? SessionCapOption
		else { return }
		viewModel.setSessionCap(option.rawValue, for: origin)
	}

	@objc private func ttlPickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? IdleDismissTTL else { return }
		viewModel.setTTL(preset.rawValue)
	}

	@objc private func impatientPickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? IdleEscalationTiming else { return }
		viewModel.setIdleImpatientSeconds(preset.rawValue)
		// setIdleImpatientSeconds may silently bump Frustrated to keep it one
		// step above Impatient — re-sync the Frustrated picker so the UI never
		// shows a stale selection.
		if let frustratedPreset = IdleEscalationTiming.matching(viewModel.idleFrustratedSeconds) {
			frustratedPicker.selectItem(withTitle: frustratedPreset.label)
		}
	}

	@objc private func frustratedPickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? IdleEscalationTiming else { return }
		viewModel.setIdleFrustratedSeconds(preset.rawValue)
	}

	@objc private func evictSessionPetsPickerChanged(_ sender: NSPopUpButton) {
		guard let enabled = sender.selectedItem?.representedObject as? Bool else { return }
		viewModel.setEvictSessionPetsEnabled(enabled)
	}

	@objc private func combinedMinimalistChanged(_ sender: NSButton) {
		viewModel.setCombinedMinimalistEnabled(sender.state == .on)
	}

	@objc private func badgeScaleChanged(_ sender: NSSlider) {
		viewModel.setMinimalistBadgeScale(sender.doubleValue)
	}
}

// MARK: - SessionsTabView

/// Sessions tab — visualizes every `state.d/` slice bucketed into the three
/// lifecycle tiers `SessionsTabViewModel` computes: Active (rendered or
/// renderable via Show/Hide All Pets), Live (fresh but not currently
/// rendered), and Archived (past the reader's fresh window, short of
/// `SlicePruner`'s deletion horizon). One themed section per tier, scrolled
/// together since the row count is unbounded; `reload(viewModel:)` tears
/// down and rebuilds, mirroring `RPGTabView`'s pattern for viewModel swaps.
private final class SessionsTabView: NSView {
	private var viewModel: SessionsTabViewModel
	private let customizationTabViewModel: CustomizationTabViewModel
	private let scrollView = NSScrollView()
	private let archiveAfterIdlePicker = NSPopUpButton()
	private let pruneArchivedPicker = NSPopUpButton()

	init(viewModel: SessionsTabViewModel, customizationTabViewModel: CustomizationTabViewModel) {
		self.viewModel = viewModel
		self.customizationTabViewModel = customizationTabViewModel
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func reload(viewModel: SessionsTabViewModel) {
		self.viewModel = viewModel
		// setupViews() below swaps in a brand-new documentView, which resets
		// the clip view to origin (0,0) — the *bottom* of an un-flipped
		// document view, not the top. Every Show/Hide/Prune action rebuilds
		// via reload(), so without restoring this the scrollbar would jerk to
		// the bottom on every single action.
		let savedScrollOrigin = scrollView.contentView.bounds.origin
		NSLayoutConstraint.deactivate(constraints)
		subviews.forEach { $0.removeFromSuperview() }
		setupViews()
		scrollView.contentView.scroll(to: savedScrollOrigin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		needsLayout = true
	}

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.sessions.symbolName, color: .systemTeal)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("Sessions")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		let note = settingsBodyLabel(
			"Every coding-tool session Codogotchi has heard from, grouped by lifecycle stage. "
				+ "Active sessions are what Show/Hide All Pets controls — shown on screen, or "
				+ "hidden by you or the idle timer. Live sessions are fresh but not rendered."
		)
		card.addSubview(note)

		// MARK: Archive/Prune TTL pickers

		let archiveLabel = NSTextField(labelWithString: "Archive Session After Idle:")
		archiveLabel.font = .systemFont(ofSize: 13)
		archiveLabel.translatesAutoresizingMaskIntoConstraints = false

		archiveAfterIdlePicker.translatesAutoresizingMaskIntoConstraints = false
		for preset in ArchiveSessionAfterIdleTTL.allCases {
			archiveAfterIdlePicker.addItem(withTitle: preset.label)
			archiveAfterIdlePicker.lastItem?.representedObject = preset
		}
		let currentArchivePreset = ArchiveSessionAfterIdleTTL.matching(
			customizationTabViewModel.archiveSessionAfterIdleSeconds)
		archiveAfterIdlePicker.selectItem(
			withTitle: (currentArchivePreset ?? .twoHours).label)
		archiveAfterIdlePicker.target = self
		archiveAfterIdlePicker.action = #selector(archiveAfterIdlePickerChanged(_:))

		let pruneLabel = NSTextField(labelWithString: "Prune Archived Sessions:")
		pruneLabel.font = .systemFont(ofSize: 13)
		pruneLabel.translatesAutoresizingMaskIntoConstraints = false

		pruneArchivedPicker.translatesAutoresizingMaskIntoConstraints = false
		for preset in PruneArchivedSessionsTTL.allCases {
			pruneArchivedPicker.addItem(withTitle: preset.label)
			pruneArchivedPicker.lastItem?.representedObject = preset
		}
		let currentPrunePreset = PruneArchivedSessionsTTL.matching(
			customizationTabViewModel.pruneArchivedSessionsAfterSeconds)
		pruneArchivedPicker.selectItem(withTitle: (currentPrunePreset ?? .oneDay).label)
		pruneArchivedPicker.target = self
		pruneArchivedPicker.action = #selector(pruneArchivedPickerChanged(_:))

		// Thin vertical rule separating the two label+picker groups, mirroring
		// the mockup's divided control row.
		let ttlDivider = NSView()
		ttlDivider.translatesAutoresizingMaskIntoConstraints = false
		ttlDivider.wantsLayer = true
		ttlDivider.layer?.backgroundColor = SettingsTheme.cardBorder.cgColor
		NSLayoutConstraint.activate([
			ttlDivider.widthAnchor.constraint(equalToConstant: 1),
			ttlDivider.heightAnchor.constraint(equalToConstant: 26),
		])

		let ttlRow = NSStackView(views: [
			archiveLabel, archiveAfterIdlePicker, ttlDivider, pruneLabel, pruneArchivedPicker,
		])
		ttlRow.orientation = .horizontal
		ttlRow.alignment = .centerY
		ttlRow.spacing = 12
		// Generous breathing room on both sides of the divider so the two
		// groups read as separate settings, not one run-on control strip.
		ttlRow.setCustomSpacing(28, after: archiveAfterIdlePicker)
		ttlRow.setCustomSpacing(28, after: ttlDivider)
		ttlRow.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(ttlRow)

		let contentStack = NSStackView()
		contentStack.orientation = .vertical
		contentStack.alignment = .leading
		contentStack.spacing = 16
		contentStack.translatesAutoresizingMaskIntoConstraints = false

		let activeSection = SessionTierSectionView(
			title: "Active",
			iconSymbol: "eye.fill",
			tint: .systemGreen,
			rows: viewModel.activeRows,
			emptyText: "No pets are currently shown or hidden.",
			bulkAction: nil,
			onShow: { [weak self] row in self?.show(row) },
			onHide: { [weak self] row in self?.hide(row) },
			onPrune: { [weak self] row in self?.pruneActive(row) }
		)
		contentStack.addArrangedSubview(activeSection)
		activeSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

		let liveSection = SessionTierSectionView(
			title: "Live",
			iconSymbol: "clock.fill",
			tint: .systemYellow,
			rows: viewModel.liveRows,
			emptyText: "No sessions are waiting to be resumed.",
			bulkAction: viewModel.liveRows.isEmpty
				? nil
				: ("Show All Live", { [weak self] in self?.showAllLive() }),
			onShow: { [weak self] row in self?.show(row) },
			onHide: nil,
			onPrune: nil
		)
		contentStack.addArrangedSubview(liveSection)
		liveSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

		let archivedSection = SessionTierSectionView(
			title: "Archived",
			iconSymbol: "archivebox.fill",
			tint: .secondaryLabelColor,
			rows: viewModel.archivedRows,
			emptyText: "Nothing has gone stale in the last 24 hours.",
			bulkAction: viewModel.archivedRows.isEmpty
				? nil
				: ("Prune All Archived", { [weak self] in self?.pruneAllArchived() }),
			onShow: { [weak self] row in self?.show(row) },
			onHide: nil,
			onPrune: { [weak self] row in self?.prune(row) }
		)
		contentStack.addArrangedSubview(archivedSection)
		archivedSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = contentStack
		card.addSubview(scrollView)

		NSLayoutConstraint.activate([
			contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
		])

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),
			title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			note.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			note.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			// Even 16pt above and below the control row so it sits centered
			// between the header note and the tier sections.
			ttlRow.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 16),
			ttlRow.leadingAnchor.constraint(equalTo: note.leadingAnchor),
			ttlRow.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -20),

			scrollView.topAnchor.constraint(equalTo: ttlRow.bottomAnchor, constant: 16),
			scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	@objc private func archiveAfterIdlePickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? ArchiveSessionAfterIdleTTL else {
			return
		}
		customizationTabViewModel.setArchiveSessionAfterIdleSeconds(preset.rawValue)
		// The tier boundary just moved — re-bucket rows immediately rather than
		// waiting for the next tab visit.
		viewModel.refresh()
		reload(viewModel: viewModel)
	}

	@objc private func pruneArchivedPickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? PruneArchivedSessionsTTL else {
			return
		}
		customizationTabViewModel.setPruneArchivedSessionsAfterSeconds(preset.rawValue)
		viewModel.refresh()
		reload(viewModel: viewModel)
	}

	private func show(_ row: SessionRow) {
		viewModel.show(key: row.id)
		reload(viewModel: viewModel)
	}

	private func hide(_ row: SessionRow) {
		viewModel.hide(key: row.id)
		reload(viewModel: viewModel)
	}

	private func showAllLive() {
		viewModel.showAllLive()
		reload(viewModel: viewModel)
	}

	private func pruneAllArchived() {
		viewModel.pruneArchivedNow()
		reload(viewModel: viewModel)
	}

	private func prune(_ row: SessionRow) {
		viewModel.prune(row: row)
		reload(viewModel: viewModel)
	}

	/// Same confirmation contract as the right-click "Prune Session" alert
	/// (`FloatingPetPanel.presentPruneConfirmation`): skipped entirely once
	/// `features.skip_prune_confirmation` is set, otherwise a destructive
	/// "Prune"/"Cancel" alert with a "Do not show this warning again."
	/// checkbox that persists the skip.
	private func pruneActive(_ row: SessionRow) {
		guard !PetConfig.resolvedSkipPruneConfirmation() else {
			viewModel.pruneActive(row: row)
			reload(viewModel: viewModel)
			return
		}
		let alert = NSAlert()
		alert.messageText = "Prune Session"
		alert.informativeText =
			"This destroys the panel and its session data. This cannot be undone."
		alert.addButton(withTitle: "Prune")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true
		let skipCheckbox = NSButton(
			checkboxWithTitle: "Do not show this warning again.", target: nil, action: nil)
		skipCheckbox.state = .off
		alert.accessoryView = skipCheckbox
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		if skipCheckbox.state == .on {
			try? PetConfig.write(skipPruneConfirmation: true, to: PetConfig.configURL())
		}
		viewModel.pruneActive(row: row)
		reload(viewModel: viewModel)
	}
}

/// One tier's card: icon badge + title + count pill + optional bulk-action
/// button in the header, then one `SessionRowView` per row (or an empty-state
/// label when there are none).
private final class SessionTierSectionView: NSView {
	init(
		title: String,
		iconSymbol: String,
		tint: NSColor,
		rows: [SessionRow],
		emptyText: String,
		bulkAction: (title: String, action: () -> Void)?,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setup(
			title: title, iconSymbol: iconSymbol, tint: tint, rows: rows, emptyText: emptyText,
			bulkAction: bulkAction, onShow: onShow, onHide: onHide, onPrune: onPrune)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setup(
		title: String,
		iconSymbol: String,
		tint: NSColor,
		rows: [SessionRow],
		emptyText: String,
		bulkAction: (title: String, action: () -> Void)?,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor

		let badge = settingsHeaderIconBadge(symbolName: iconSymbol, color: tint, side: 24)
		addSubview(badge)

		let titleLabel = settingsSectionTitle("\(title) (\(rows.count))")
		addSubview(titleLabel)

		var bulkButton: NSButton?
		if let bulkAction {
			let button = ActionButton(title: bulkAction.title, tint: tint, action: bulkAction.action)
			addSubview(button)
			bulkButton = button
		}

		let rowsStack = NSStackView()
		rowsStack.orientation = .vertical
		rowsStack.spacing = 0
		rowsStack.alignment = .leading
		rowsStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(rowsStack)

		if rows.isEmpty {
			let empty = settingsBodyLabel(emptyText)
			rowsStack.addArrangedSubview(empty)
			empty.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
		} else {
			for (index, row) in rows.enumerated() {
				let rowView = SessionRowView(
					row: row, showsDivider: index < rows.count - 1,
					onShow: onShow, onHide: onHide, onPrune: onPrune)
				rowsStack.addArrangedSubview(rowView)
				rowView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
			}
		}

		NSLayoutConstraint.activate([
			badge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
			badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

			titleLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
			titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),

			rowsStack.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 10),
			rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
			rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
		])

		if let bulkButton {
			NSLayoutConstraint.activate([
				bulkButton.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
				bulkButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
				titleLabel.trailingAnchor.constraint(
					lessThanOrEqualTo: bulkButton.leadingAnchor, constant: -12),
			])
		}
	}
}

/// One session row: platform icon, display label, a relative-age caption, and
/// up to two trailing action buttons (Show/Hide, and Prune for Archived rows).
private final class SessionRowView: NSView {
	init(
		row: SessionRow, showsDivider: Bool,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setup(row: row, showsDivider: showsDivider, onShow: onShow, onHide: onHide, onPrune: onPrune)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setup(
		row: SessionRow, showsDivider: Bool,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attribution = platformAttribution(forBadgeKey: row.origin) {
			iconView.image = NSImage(named: attribution.assetName)
		} else {
			iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
		}
		iconView.contentTintColor = Self.iconTint(forOrigin: row.origin)
		addSubview(iconView)

		let label = NSTextField(labelWithString: row.displayLabel)
		label.font = .systemFont(ofSize: 12, weight: .medium)
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		let statusText: String
		switch row.tier {
		case .active: statusText = row.isShown ? "Shown" : "Hidden"
		case .live: statusText = "Idle \(Self.relativeAge(row.ageSeconds))"
		case .archived: statusText = "Quiet \(Self.relativeAge(row.ageSeconds))"
		}
		let statusLabel = NSTextField(labelWithString: statusText)
		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(statusLabel)

		var trailingButtons: [NSButton] = []
		if row.tier == .active {
			// Gated on `sessionId` (session-keyed window), mirroring the
			// right-click affordance's `hasActiveSessionBadge` gate: a
			// plain-origin/combined row has no session to prune.
			if row.sessionId != nil, let onPrune {
				trailingButtons.append(ActionButton(title: "Prune", tint: .systemRed) { onPrune(row) })
			}
			if row.isShown {
				if let onHide {
					trailingButtons.append(
						ActionButton(title: "Hide", tint: .secondaryLabelColor) { onHide(row) })
				}
			} else if let onShow {
				trailingButtons.append(ActionButton(title: "Show", tint: .systemBlue) { onShow(row) })
			}
		} else {
			if let onShow {
				trailingButtons.append(ActionButton(title: "Show", tint: .systemBlue) { onShow(row) })
			}
			if let onPrune {
				trailingButtons.append(ActionButton(title: "Prune", tint: .systemRed) { onPrune(row) })
			}
		}

		let buttonStack = NSStackView(views: trailingButtons)
		buttonStack.orientation = .horizontal
		buttonStack.spacing = 6
		buttonStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(buttonStack)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 36),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 20),
			iconView.heightAnchor.constraint(equalToConstant: 20),

			label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
			label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),

			statusLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
			statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),

			buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			buttonStack.leadingAnchor.constraint(
				greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
		])

		if showsDivider {
			let divider = NSView()
			divider.translatesAutoresizingMaskIntoConstraints = false
			divider.wantsLayer = true
			divider.layer?.backgroundColor = SettingsTheme.rowDivider.cgColor
			addSubview(divider)
			NSLayoutConstraint.activate([
				divider.leadingAnchor.constraint(equalTo: leadingAnchor),
				divider.trailingAnchor.constraint(equalTo: trailingAnchor),
				divider.bottomAnchor.constraint(equalTo: bottomAnchor),
				divider.heightAnchor.constraint(equalToConstant: 1),
			])
		}
	}

	private static func iconTint(forOrigin origin: String) -> NSColor {
		switch origin {
		case "claude_code": return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
		case "codex": return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)
		case "vscode": return NSColor(srgbRed: 0.00, green: 0.48, blue: 0.80, alpha: 1)
		case "cursor": return NSColor(calibratedWhite: 0.78, alpha: 1)
		case "antigravity": return NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1)
		default: return .labelColor
		}
	}

	private static func relativeAge(_ seconds: TimeInterval) -> String {
		let minutes = Int(seconds / 60)
		if minutes < 1 { return "just now" }
		if minutes < 60 { return "\(minutes)m ago" }
		let hours = Int(seconds / 3600)
		if hours < 24 { return "\(hours)h ago" }
		let days = Int(seconds / 86400)
		return "\(days)d ago"
	}
}

/// Small pill-style text button shared by bulk and per-row session actions —
/// the same borderless-with-tint treatment as the Hooks card's action row,
/// scaled down for inline row use.
private final class ActionButton: NSButton {
	private let handler: () -> Void

	init(title: String, tint: NSColor, action: @escaping () -> Void) {
		self.handler = action
		super.init(frame: .zero)
		self.title = title
		translatesAutoresizingMaskIntoConstraints = false
		isBordered = false
		wantsLayer = true
		layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
		layer?.cornerRadius = 6
		font = .systemFont(ofSize: 11, weight: .semibold)
		contentTintColor = tint
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [.foregroundColor: tint, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)])
		target = self
		self.action = #selector(tapped)
		heightAnchor.constraint(equalToConstant: 22).isActive = true
		widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
	}

	/// Real horizontal padding. The 52pt min width alone only pads titles
	/// shorter than it ("Show", "Prune"); a longer title ("Prune All
	/// Archived") would otherwise render its text flush with the pill edges.
	override var intrinsicContentSize: NSSize {
		var size = super.intrinsicContentSize
		size.width += 20
		return size
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	@objc private func tapped() { handler() }
}

// MARK: - AboutTabView

/// About tab — app version, bundled hook-binary version, and product links.
private final class AboutTabView: NSView {
	private let viewModel: AboutViewModel

	init(viewModel: AboutViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.about.symbolName, color: .systemBlue)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("About")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		let appVersionLabel = settingsBodyLabel("Codogotchi \(viewModel.appVersion)")
		card.addSubview(appVersionLabel)

		let hookVersionLabel = settingsBodyLabel("Bundled hook binary: \(viewModel.hookVersion)")
		card.addSubview(hookVersionLabel)

		let links = NSStackView(views: [
			linkButton(title: "Website", urlString: "https://codogotchi.app"),
			linkButton(title: "GitHub", urlString: "https://github.com/cesarnml/codogotchi"),
			linkButton(
				title: "Documentation",
				urlString: "https://github.com/cesarnml/codogotchi#readme"
			),
			linkButton(title: "Dev Guide", urlString: "https://codogotchifordummies.vercel.app/"),
		])
		links.orientation = .horizontal
		links.spacing = 12
		links.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(links)

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.centerYAnchor.constraint(equalTo: headerBadge.centerYAnchor),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),
			title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			appVersionLabel.topAnchor.constraint(equalTo: headerBadge.bottomAnchor, constant: 12),
			appVersionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			appVersionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			hookVersionLabel.topAnchor.constraint(equalTo: appVersionLabel.bottomAnchor, constant: 6),
			hookVersionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			hookVersionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			links.topAnchor.constraint(equalTo: hookVersionLabel.bottomAnchor, constant: 16),
			links.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			links.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	private func linkButton(title: String, urlString: String) -> NSButton {
		let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
		button.bezelStyle = .inline
		button.isBordered = false
		button.contentTintColor = .linkColor
		button.toolTip = urlString
		button.identifier = NSUserInterfaceItemIdentifier(urlString)
		return button
	}

	@objc private func openLink(_ sender: NSButton) {
		guard
			let urlString = sender.identifier?.rawValue,
			let url = URL(string: urlString)
		else { return }
		NSWorkspace.shared.open(url)
	}
}

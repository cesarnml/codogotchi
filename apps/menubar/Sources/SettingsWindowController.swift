import AppKit

/// Shows the Settings window — a standard macOS window (not an `NSPanel`) with
/// six selectable tabs:
/// - **General**: per-platform hook install/uninstall/status; Cursor native-hook note.
/// - **Pet**: list + select pets from `~/.codogotchi/pets/`; import from `~/.codex/pets/`.
/// - **Customization**: per-platform mode pickers and idle-dismiss TTL.
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
	private let tabModel = SettingsTabModel()
	private let generalViewModel: GeneralTabViewModel
	private let petTabViewModel: PetTabViewModel
	private let rpgTabViewModel: RPGTabViewModel
	private let customizationTabViewModel: CustomizationTabViewModel

	private let settingsController: SettingsController
	private let petImportHelper: PetImportHelper
	private let aboutViewModel: AboutViewModel
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void

	/// Called when the user activates a pet in the Pet tab. Receives the new pet ID.
	/// Wire this in `MenubarApp` to reload pet loaders and push a fresh frame.
	var onPetActivated: ((String) -> Void)?

	/// Called when the user toggles the RPG HUD checkbox. Receives the persisted
	/// enabled state. Wire this in `MenubarApp` to push HUD visibility to the
	/// floating pet live, so the change takes effect without an app restart.
	var onRPGHUDEnabledChanged: ((Bool) -> Void)?

	/// Called when the user toggles "Monochrome menu bar icon". Receives the new
	/// state. Wire this in `MenubarApp` to toggle `image.isTemplate` on the status item.
	var onMonochromeChanged: ((Bool) -> Void)?

	init(
		settingsController: SettingsController = SettingsController(),
		petImportHelper: PetImportHelper = PetImportHelper(),
		petTabViewModel: PetTabViewModel = PetTabViewModel(),
		rpgTabViewModel: RPGTabViewModel = RPGTabViewModel(),
		customizationTabViewModel: CustomizationTabViewModel = CustomizationTabViewModel(),
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
	}

	// MARK: - Private

	private func openWindow() {
		// Width sized so the Pet tab grid shows three columns by default
		// (each card needs ~300pt; see PetTabView.minCardWidth/maxColumns) with
		// headroom for the Customization tab's two-column layout.
		let frame = CGRect(x: 0, y: 0, width: 1120, height: 680)
		let w = NSWindow(
			contentRect: frame,
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		w.title = Self.windowTitle
		w.isReleasedWhenClosed = false
		w.minSize = CGSize(width: 460, height: 480)
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
		petTabViewModel.onAssignmentsChanged = { [weak self] in
			self?.onPetActivated?(self?.petTabViewModel.assignmentsSnapshot.default ?? DEFAULT_PET_NAME)
		}
		let pet = PetTabView(
			viewModel: petTabViewModel,
			onImportPet: { [weak self] petId in self?.handleImportPet(id: petId) }
		)
		let customization = CustomizationTabView(viewModel: customizationTabViewModel)
		let rpg = RPGTabView(
			viewModel: rpgTabViewModel,
			onToggle: { [weak self] enabled in
				guard let self else { return }
				self.rpgTabViewModel.setRPGHUDEnabled(enabled)
				// Fire with the *persisted* value: `setRPGHUDEnabled` reverts on a
				// failed write, so the live HUD must track what survives a relaunch.
				self.onRPGHUDEnabledChanged?(self.rpgTabViewModel.rpgHUDEnabled)
			}
		)
		let developerViewModel = makeDeveloperTabViewModel()
		let developer = DeveloperTabView(viewModel: developerViewModel)
		let about = AboutTabView(viewModel: aboutViewModel)

		let tabView = NSTabView()
		tabView.tabViewType = .topTabsBezelBorder
		tabView.translatesAutoresizingMaskIntoConstraints = false

		for (tab, view): (SettingsTab, NSView) in [
			(.general, general),
			(.pet, pet),
			(.customization, customization),
			(.rpg, rpg),
			(.developer, developer),
			(.about, about),
		] {
			let item = NSTabViewItem(identifier: tab.rawValue)
			item.label = tab.title
			item.view = view
			tabView.addTabViewItem(item)
		}

		let container = NSView(frame: frame)
		container.addSubview(tabView)
		NSLayoutConstraint.activate([
			tabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
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
		tabView.delegate = self

		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.window = w
		self.generalTab = general
		self.petTab = pet
		self.tabView = tabView
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

/// General tab — Install / Update / Remove hooks + per-platform status + Copy diagnostics.
private final class GeneralTabView: NSView {
	private let hooksStatusLabel = NSTextField(wrappingLabelWithString: "")
	private let installButton = NSButton(title: "Install hooks", target: nil, action: nil)
	private let updateButton = NSButton(title: "Update hooks", target: nil, action: nil)
	private let removeButton = NSButton(title: "Remove hooks", target: nil, action: nil)
	private let copyDiagnosticsButton = NSButton(
		title: "Copy diagnostics", target: nil, action: nil
	)
	private let hooksFeedbackLabel = NSTextField(wrappingLabelWithString: "")
	private let bannerView = UpdateBannerView()
	private let monochromeToggle = NSButton(
		checkboxWithTitle: "Monochrome menu bar icon", target: nil, action: nil)

	private let onInstallHooks: () -> Void
	private let onUpdateHooks: () -> Void
	private let onUninstallHooks: () -> Void
	var onMonochromeToggled: ((Bool) -> Void)?
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
		bannerView.onUpdate = onUpdateHooks
		applyViewModel(viewModel)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func applyViewModel(_ vm: GeneralTabViewModel) {
		viewModel = vm
		hooksStatusLabel.stringValue = vm.rows.map { platformLine($0) }.joined(separator: "\n")
		bannerView.message = vm.updateBannerMessage
		bannerView.isHidden = !vm.shouldShowUpdateBanner
		monochromeToggle.state = vm.menubarIconMonochrome ? .on : .off
	}

	func setHooksWorking(message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = false }
		hooksFeedbackLabel.stringValue = message
		hooksFeedbackLabel.textColor = .secondaryLabelColor
	}

	func setHooksSuccess(message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = true }
		hooksFeedbackLabel.stringValue = message
		hooksFeedbackLabel.textColor = .systemGreen
	}

	func setHooksError(_ message: String) {
		[installButton, updateButton, removeButton].forEach { $0.isEnabled = true }
		hooksFeedbackLabel.stringValue = message
		hooksFeedbackLabel.textColor = .systemRed
	}

	private func setupViews() {
		// Prevent unsatisfiable-constraint log when the view is constructed at
		// .zero before joining the window hierarchy. The real window min-width
		// (460pt) wins once the view is in the superview chain.
		let floor = widthAnchor.constraint(greaterThanOrEqualToConstant: 460)
		floor.priority = .defaultHigh
		floor.isActive = true

		let title = settingsSectionTitle("Hooks")
		addSubview(title)

		hooksStatusLabel.isEditable = false
		hooksStatusLabel.isBordered = false
		hooksStatusLabel.backgroundColor = .clear
		hooksStatusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		hooksStatusLabel.textColor = .secondaryLabelColor
		hooksStatusLabel.stringValue = "Loading…"
		hooksStatusLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(hooksStatusLabel)

		for btn in [installButton, updateButton, removeButton, copyDiagnosticsButton] {
			btn.bezelStyle = .rounded
		}
		installButton.target = self
		installButton.action = #selector(installTapped)
		updateButton.target = self
		updateButton.action = #selector(updateTapped)
		removeButton.target = self
		removeButton.action = #selector(removeTapped)
		copyDiagnosticsButton.target = self
		copyDiagnosticsButton.action = #selector(copyDiagnosticsTapped)

		let actionRow = NSStackView(views: [installButton, updateButton, removeButton])
		actionRow.orientation = .horizontal
		actionRow.spacing = 8
		actionRow.translatesAutoresizingMaskIntoConstraints = false
		addSubview(actionRow)

		let diagRow = NSStackView(views: [copyDiagnosticsButton])
		diagRow.orientation = .horizontal
		diagRow.translatesAutoresizingMaskIntoConstraints = false
		addSubview(diagRow)

		hooksFeedbackLabel.isEditable = false
		hooksFeedbackLabel.isBordered = false
		hooksFeedbackLabel.backgroundColor = .clear
		hooksFeedbackLabel.font = .systemFont(ofSize: 11)
		hooksFeedbackLabel.textColor = .secondaryLabelColor
		hooksFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(hooksFeedbackLabel)

		let cursorNote = settingsBodyLabel(
			"Install hooks wires every coding tool detected on this machine — Codex, "
				+ "Claude Code, Cursor, VS Code, and Antigravity — re-run any time to "
				+ "update or pick up a newly installed tool. Cursor only reads hooks at "
				+ "launch, so restart it after installing."
		)
		addSubview(cursorNote)

		bannerView.translatesAutoresizingMaskIntoConstraints = false
		bannerView.isHidden = true
		addSubview(bannerView)

		monochromeToggle.target = self
		monochromeToggle.action = #selector(monochromeToggleChanged)
		monochromeToggle.translatesAutoresizingMaskIntoConstraints = false
		addSubview(monochromeToggle)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			hooksStatusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
			hooksStatusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			hooksStatusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			actionRow.topAnchor.constraint(equalTo: hooksStatusLabel.bottomAnchor, constant: 12),
			actionRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			diagRow.topAnchor.constraint(equalTo: actionRow.bottomAnchor, constant: 8),
			diagRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			hooksFeedbackLabel.topAnchor.constraint(equalTo: diagRow.bottomAnchor, constant: 8),
			hooksFeedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			hooksFeedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			cursorNote.topAnchor.constraint(equalTo: hooksFeedbackLabel.bottomAnchor, constant: 8),
			cursorNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			cursorNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			bannerView.topAnchor.constraint(equalTo: cursorNote.bottomAnchor, constant: 12),
			bannerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			bannerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			monochromeToggle.topAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: 16),
			monochromeToggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
		])
	}

	private func platformLine(_ row: GeneralTabViewModel.PlatformRow) -> String {
		var parts: [String] = [row.name]
		if row.installable {
			if row.installed {
				parts.append("installed")
			} else if row.partiallyInstalled {
				// Present and firing, just missing a newly-added event. Don't
				// read as "not installed" — nudge a re-install to complete it.
				parts.append("installed (update available — re-run Install hooks)")
			} else if row.detected {
				// Tool is present on this machine but has no hooks yet — the
				// actionable case. Re-running Install/Update wires it.
				parts.append("detected — run Install hooks to wire")
			} else {
				parts.append("not installed")
			}
			if row.firingRecently { parts.append("firing") }
			if let t = row.lastEventAt { parts.append("last: \(t)") }
		} else {
			parts.append("not yet supported")
		}
		return parts.joined(separator: " · ")
	}

	@objc private func installTapped() { onInstallHooks() }
	@objc private func updateTapped() { onUpdateHooks() }
	@objc private func removeTapped() { onUninstallHooks() }
	@objc private func monochromeToggleChanged() {
		onMonochromeToggled?(monochromeToggle.state == .on)
	}

	@objc private func copyDiagnosticsTapped() {
		let json = viewModel.diagnosticsJSON()
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(json, forType: .string)
		hooksFeedbackLabel.stringValue = "Diagnostics copied to clipboard."
		hooksFeedbackLabel.textColor = .secondaryLabelColor
	}
}

// MARK: - UpdateBannerView

/// Persistent non-blocking banner shown when the installed hook registration
/// drifted from what the current binary would write (missing event slots or a
/// stale command path), or a newly detected tool has no hooks yet. A pure
/// binary-version bump with an unchanged registration shows nothing. Cleared
/// after a successful update.
private final class UpdateBannerView: NSView {
	var onUpdate: (() -> Void)?

	/// The banner copy. Set per-reason by the controller (binary out of date vs
	/// incomplete wiring) so a single banner serves both update prompts.
	var message: String {
		get { messageLabel.stringValue }
		set { messageLabel.stringValue = newValue }
	}

	private let messageLabel = NSTextField(
		labelWithString: "Hooks are out of date — click Update to apply the bundled version."
	)
	private let updateButton = NSButton(title: "Update Hooks", target: nil, action: nil)

	init() {
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		wantsLayer = true
		layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.15).cgColor
		layer?.cornerRadius = 6

		messageLabel.font = .systemFont(ofSize: 12)
		messageLabel.textColor = .labelColor
		messageLabel.lineBreakMode = .byWordWrapping
		messageLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(messageLabel)

		updateButton.bezelStyle = .rounded
		updateButton.target = self
		updateButton.action = #selector(updateTapped)
		updateButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(updateButton)

		NSLayoutConstraint.activate([
			messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
			messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			messageLabel.trailingAnchor.constraint(
				equalTo: updateButton.leadingAnchor, constant: -8
			),

			updateButton.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
			updateButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

			bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 10),
		])
	}

	@objc private func updateTapped() { onUpdate?() }
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
		let title = settingsSectionTitle("Pet")
		addSubview(title)

		let storeNote = settingsBodyLabel(
			"Installed pets live in ~/.codogotchi/pets/. "
				+ "Pets in ~/.codex/pets/ show an Import action."
		)
		addSubview(storeNote)

		searchField.placeholderString = "Search pets…"
		searchField.delegate = self
		searchField.sendsWholeSearchString = false
		searchField.sendsSearchStringImmediately = true
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		addSubview(searchField)

		openFolderButton.bezelStyle = .rounded
		openFolderButton.target = self
		openFolderButton.action = #selector(openPetFolder)
		openFolderButton.translatesAutoresizingMaskIntoConstraints = false
		openFolderButton.setContentHuggingPriority(.required, for: .horizontal)
		addSubview(openFolderButton)

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
		addSubview(gridScrollView)

		NSLayoutConstraint.activate([
			gridStack.widthAnchor.constraint(equalTo: gridScrollView.contentView.widthAnchor),
		])

		emptyLabel.font = .systemFont(ofSize: 12)
		emptyLabel.textColor = .secondaryLabelColor
		emptyLabel.alignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(emptyLabel)

		footerLabel.font = .systemFont(ofSize: 11)
		footerLabel.textColor = .tertiaryLabelColor
		footerLabel.alignment = .center
		footerLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(footerLabel)

		feedbackLabel.isEditable = false
		feedbackLabel.isBordered = false
		feedbackLabel.backgroundColor = .clear
		feedbackLabel.font = .systemFont(ofSize: 11)
		feedbackLabel.textColor = .secondaryLabelColor
		feedbackLabel.isHidden = true
		feedbackLabel.identifier = NSUserInterfaceItemIdentifier("petTabFeedback")
		feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(feedbackLabel)
		feedbackHeightConstraint = feedbackLabel.heightAnchor.constraint(equalToConstant: 0)
		feedbackHeightConstraint?.isActive = true

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			searchField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			searchField.widthAnchor.constraint(equalToConstant: 200),

			openFolderButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openFolderButton.trailingAnchor.constraint(
				equalTo: searchField.leadingAnchor, constant: -8),
			openFolderButton.leadingAnchor.constraint(
				greaterThanOrEqualTo: title.trailingAnchor, constant: 16),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			storeNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			storeNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			feedbackLabel.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 8),
			feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			feedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			gridScrollView.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 8),
			gridScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			gridScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			emptyLabel.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),

			footerLabel.topAnchor.constraint(equalTo: gridScrollView.bottomAnchor, constant: 8),
			footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			footerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
		])
	}

	override func layout() {
		super.layout()
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
		card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
		card.layer?.borderWidth = entry.isDefault ? 2 : 1
		card.layer?.borderColor =
			(entry.isDefault ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
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
	private let toggleButton = NSButton(checkboxWithTitle: "Show RPG HUD", target: nil, action: nil)
	private let onToggle: (Bool) -> Void

	init(viewModel: RPGTabViewModel, onToggle: @escaping (Bool) -> Void) {
		self.onToggle = onToggle
		super.init(frame: .zero)
		toggleButton.state = viewModel.rpgHUDEnabled ? .on : .off
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let title = settingsSectionTitle("RPG")
		addSubview(title)

		let note = settingsBodyLabel(
			"When enabled, a floating HUD shows hearts, level, and XP ring while "
				+ "you code. Toggle off to hide it completely — the RPG engine keeps "
				+ "running in the background."
		)
		addSubview(note)

		toggleButton.target = self
		toggleButton.action = #selector(toggleChanged)
		toggleButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(toggleButton)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			toggleButton.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 16),
			toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
		])
	}

	@objc private func toggleChanged() {
		onToggle(toggleButton.state == .on)
	}
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
		let title = settingsSectionTitle("Developer")
		addSubview(title)

		refreshButton.bezelStyle = .rounded
		refreshButton.target = self
		refreshButton.action = #selector(refresh)
		refreshButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(refreshButton)

		openDataButton.bezelStyle = .rounded
		openDataButton.target = self
		openDataButton.action = #selector(openDataFolder)
		openDataButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(openDataButton)

		textView.isEditable = false
		textView.isSelectable = true
		textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		textView.backgroundColor = NSColor.textBackgroundColor
		textView.textContainerInset = NSSize(width: 8, height: 8)
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		scrollView.borderType = .bezelBorder
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scrollView)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 16),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			refreshButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			openDataButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openDataButton.trailingAnchor.constraint(
				equalTo: refreshButton.leadingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
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

	init(viewModel: CustomizationTabViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	/// Styled container used for the "Platform Display Mode" and "Minimalist Panel
	/// Options" columns, matching the pet-card look elsewhere in Settings.
	private func makeSettingsCard() -> NSView {
		let card = NSView()
		card.translatesAutoresizingMaskIntoConstraints = false
		card.wantsLayer = true
		card.layer?.cornerRadius = 10
		card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
		card.layer?.borderWidth = 1
		card.layer?.borderColor = NSColor.separatorColor.cgColor
		return card
	}

	private func setupViews() {
		let title = settingsSectionTitle("Customization")
		addSubview(title)

		let note = settingsBodyLabel(
			"Choose how each coding platform displays your pet.\n"
				+ "Own = dedicated floating window per tool. "
				+ "Combined = all active tools share one window. "
				+ "Minimalist = compact badge strip. "
				+ "Off = no window for that tool."
		)
		addSubview(note)

		// MARK: Platform Settings card (left column)

		let platformCard = makeSettingsCard()
		addSubview(platformCard)

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
		addSubview(minimalistCard)

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

		// MARK: Pet Idle and Eviction Preferences (full-width card, below both cards)

		let ttlCard = makeSettingsCard()
		addSubview(ttlCard)

		let ttlTitle = settingsSectionTitle("Pet Idle and Eviction Preferences")
		ttlCard.addSubview(ttlTitle)

		let ttlLabel = NSTextField(labelWithString: "Dismiss Idle Pet After:")
		ttlLabel.font = .systemFont(ofSize: 13)
		ttlLabel.translatesAutoresizingMaskIntoConstraints = false
		ttlCard.addSubview(ttlLabel)

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
		ttlCard.addSubview(ttlPicker)

		let ttlNote = settingsBodyLabel(
			"\"Never\" keeps the pet visible until you switch tools or quit. "
				+ "Changes take effect on the next poll cycle."
		)
		ttlCard.addSubview(ttlNote)

		let rowsTop = note.bottomAnchor

		// The card sits below whichever of the two side-by-side cards is
		// taller (Platform Settings, with one row per origin, is expected to
		// usually be the taller one, but this must not assume that).
		let ttlBelowPlatform = ttlCard.topAnchor.constraint(
			greaterThanOrEqualTo: platformCard.bottomAnchor, constant: 24)
		let ttlBelowMinimalist = ttlCard.topAnchor.constraint(
			greaterThanOrEqualTo: minimalistCard.bottomAnchor, constant: 24)
		let ttlPrefersBelowPlatform = ttlCard.topAnchor.constraint(
			equalTo: platformCard.bottomAnchor, constant: 24)
		ttlPrefersBelowPlatform.priority = .defaultHigh

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			// Platform Settings (left column) and Minimalist Panel Options (right
			// column) sit side by side; Idle Dismiss stacks full-width below both.
			platformCard.topAnchor.constraint(equalTo: rowsTop, constant: 20),
			platformCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			platformCard.widthAnchor.constraint(equalToConstant: Self.platformCardWidth),

			platformTitle.topAnchor.constraint(equalTo: platformCard.topAnchor, constant: 16),
			platformTitle.leadingAnchor.constraint(equalTo: platformCard.leadingAnchor, constant: 16),
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
			minimalistCard.topAnchor.constraint(equalTo: rowsTop, constant: 20),
			minimalistCard.leadingAnchor.constraint(equalTo: platformCard.trailingAnchor, constant: 20),
			minimalistCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			minimalistTitle.topAnchor.constraint(equalTo: minimalistCard.topAnchor, constant: 16),
			minimalistTitle.leadingAnchor.constraint(equalTo: minimalistCard.leadingAnchor, constant: 16),
			minimalistTitle.trailingAnchor.constraint(equalTo: minimalistCard.trailingAnchor, constant: -16),

			combinedMinimalistCheckbox.topAnchor.constraint(
				equalTo: minimalistTitle.bottomAnchor, constant: 10),
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

			scaleNote.bottomAnchor.constraint(
				lessThanOrEqualTo: minimalistCard.bottomAnchor, constant: -16),

			// Match the Platform Settings card's height for visual symmetry, since
			// both cards share the same top anchor (rowsTop + 20).
			minimalistCard.bottomAnchor.constraint(equalTo: platformCard.bottomAnchor),

			ttlBelowPlatform, ttlBelowMinimalist, ttlPrefersBelowPlatform,
			ttlCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			ttlCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			ttlTitle.topAnchor.constraint(equalTo: ttlCard.topAnchor, constant: 16),
			ttlTitle.leadingAnchor.constraint(equalTo: ttlCard.leadingAnchor, constant: 16),
			ttlTitle.trailingAnchor.constraint(equalTo: ttlCard.trailingAnchor, constant: -16),

			ttlLabel.topAnchor.constraint(equalTo: ttlTitle.bottomAnchor, constant: 14),
			ttlLabel.leadingAnchor.constraint(equalTo: ttlCard.leadingAnchor, constant: 16),
			ttlLabel.widthAnchor.constraint(equalToConstant: 170),

			ttlPicker.centerYAnchor.constraint(equalTo: ttlLabel.centerYAnchor),
			ttlPicker.leadingAnchor.constraint(equalTo: ttlLabel.trailingAnchor, constant: 8),
			ttlPicker.widthAnchor.constraint(equalToConstant: 130),

			ttlNote.topAnchor.constraint(equalTo: ttlLabel.bottomAnchor, constant: 8),
			ttlNote.leadingAnchor.constraint(equalTo: ttlCard.leadingAnchor, constant: 16),
			ttlNote.trailingAnchor.constraint(equalTo: ttlCard.trailingAnchor, constant: -16),

			ttlNote.bottomAnchor.constraint(equalTo: ttlCard.bottomAnchor, constant: -16),
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

	@objc private func combinedMinimalistChanged(_ sender: NSButton) {
		viewModel.setCombinedMinimalistEnabled(sender.state == .on)
	}

	@objc private func badgeScaleChanged(_ sender: NSSlider) {
		viewModel.setMinimalistBadgeScale(sender.doubleValue)
	}
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
		let title = settingsSectionTitle("About")
		addSubview(title)

		let appVersionLabel = settingsBodyLabel("Codogotchi \(viewModel.appVersion)")
		addSubview(appVersionLabel)

		let hookVersionLabel = settingsBodyLabel("Bundled hook binary: \(viewModel.hookVersion)")
		addSubview(hookVersionLabel)

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
		addSubview(links)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			appVersionLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
			appVersionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			appVersionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			hookVersionLabel.topAnchor.constraint(equalTo: appVersionLabel.bottomAnchor, constant: 6),
			hookVersionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			hookVersionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			links.topAnchor.constraint(equalTo: hookVersionLabel.bottomAnchor, constant: 16),
			links.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
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

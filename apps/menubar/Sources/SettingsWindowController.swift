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

	/// Opens (or brings to front) the settings window.
	func show() {
		if let existing = window {
			existing.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
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
		// (each card needs ~300pt; see PetTabView.minCardWidth/maxColumns).
		let frame = CGRect(x: 0, y: 0, width: 1020, height: 680)
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
		petTabViewModel.onActivePetChanged = { [weak self] petId in
			self?.onPetActivated?(petId)
		}
		let pet = PetTabView(
			viewModel: petTabViewModel,
			onImportPet: { [weak self] petId in self?.handleImportPet(id: petId) },
			onSelectPet: { [weak self] petId in self?.handleSelectPet(id: petId) }
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
		tabView.delegate = self
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
		tabView.selectTabViewItem(at: tabModel.selected.rawValue)

		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.window = w
		self.generalTab = general
		self.petTab = pet
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

	private func handleSelectPet(id: String) {
		petTabViewModel.selectPet(id: id)
		petTab?.refreshPetList(viewModel: petTabViewModel)
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

	private let onInstallHooks: () -> Void
	private let onUpdateHooks: () -> Void
	private let onUninstallHooks: () -> Void
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

	@objc private func copyDiagnosticsTapped() {
		let json = viewModel.diagnosticsJSON()
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(json, forType: .string)
		hooksFeedbackLabel.stringValue = "Diagnostics copied to clipboard."
		hooksFeedbackLabel.textColor = .secondaryLabelColor
	}
}

// MARK: - UpdateBannerView

/// Persistent non-blocking banner shown when the bundled hook binary is newer
/// than the last-recorded installed version. Cleared after a successful update.
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
/// deduplicated across the bundled, Codex, and canonical-store sources, in one
/// of three states keyed purely on where it lives:
///
/// - `Selected` — the active pet (disabled button, accent border, Default badge
///   for bundled Maew).
/// - `Installed` — in `~/.codogotchi/pets/`, offers a `Select` action.
/// - `Importable` — present only under `~/.codex/pets/`, offers an `Import`
///   action that copies it into the canonical store (after which it becomes an
///   ordinary installed pet — no auto-select).
///
/// A search field filters by display name / ID, and a footer reports installed
/// vs. importable counts. Thumbnails are the static idle first frame.
private final class PetTabView: NSView, NSSearchFieldDelegate {
	/// View identifiers used by layout tests to locate cards and their
	/// description labels in the rendered hierarchy.
	static let cardIdentifier = NSUserInterfaceItemIdentifier("petCard")
	static let descriptionIdentifier = NSUserInterfaceItemIdentifier("petCardDescription")

	private var viewModel: PetTabViewModel
	private let onImportPet: (String) -> Void
	private let onSelectPet: (String) -> Void

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

	/// Idle-frame thumbnails are sliced once and cached by spritesheet path so
	/// repeated grid rebuilds (resize, select, search) don't re-decode WebP.
	private var thumbnailCache: [String: NSImage?] = [:]
	/// Column count last laid out — guards `layout()` from rebuilding the grid
	/// on every resize tick, only when the responsive column count changes.
	private var lastColumnCount = 0
	private var currentEntries: [PetCatalogEntry] = []

	private let cardHeight: CGFloat = 128
	private let cardSpacing: CGFloat = 12
	private let minCardWidth: CGFloat = 300
	private let maxColumns = 3
	private let thumbSize: CGFloat = 64

	init(
		viewModel: PetTabViewModel,
		onImportPet: @escaping (String) -> Void,
		onSelectPet: @escaping (String) -> Void
	) {
		self.viewModel = viewModel
		self.onImportPet = onImportPet
		self.onSelectPet = onSelectPet
		super.init(frame: .zero)
		setupViews()
		reloadEntries()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func setPetImportSuccess(petId: String) {
		feedbackLabel.stringValue = "Imported \(petId) to ~/.codogotchi/pets/."
		feedbackLabel.textColor = .systemGreen
	}

	func setPetImportError(_ message: String) {
		feedbackLabel.stringValue = message
		feedbackLabel.textColor = .systemRed
	}

	/// Rebuild the grid from the current ViewModel state (after import/select).
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
		feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(feedbackLabel)

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

			gridScrollView.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 12),
			gridScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			gridScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			emptyLabel.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),

			feedbackLabel.topAnchor.constraint(equalTo: gridScrollView.bottomAnchor, constant: 8),
			feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			feedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			footerLabel.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 6),
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
				query.isEmpty ? "No pets available." : "No pets match “\(query)”."
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
		card.layer?.borderWidth = entry.state == .selected ? 2 : 1
		card.layer?.borderColor =
			(entry.state == .selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
		card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
		card.identifier = PetTabView.cardIdentifier

		// Thumbnail on a rounded dark tile, vertically centered (Codex-style).
		let thumb = NSImageView()
		thumb.translatesAutoresizingMaskIntoConstraints = false
		thumb.imageScaling = .scaleProportionallyUpOrDown
		thumb.image = thumbnail(for: entry)
		thumb.wantsLayer = true
		thumb.layer?.cornerRadius = 10
		thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
		thumb.layer?.masksToBounds = true
		card.addSubview(thumb)

		let nameLabel = NSTextField(labelWithString: entry.displayName)
		nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let nameRow = NSStackView(views: [nameLabel])
		nameRow.orientation = .horizontal
		nameRow.spacing = 6
		nameRow.alignment = .centerY
		if entry.isDefault {
			nameRow.addArrangedSubview(makeBadge(text: "Default", tint: .systemGreen))
		}
		if entry.state == .importable {
			nameRow.addArrangedSubview(makeBadge(text: "~/.codex", tint: .secondaryLabelColor))
		}

		nameRow.translatesAutoresizingMaskIntoConstraints = false

		let descLabel = NSTextField(wrappingLabelWithString: entry.description)
		descLabel.font = .systemFont(ofSize: 12)
		descLabel.textColor = .secondaryLabelColor
		descLabel.maximumNumberOfLines = 5
		// Word-wrap (not truncating-tail, which collapses to one line) capped at
		// 5 lines, with an ellipsis on the last line when the text overflows.
		descLabel.lineBreakMode = .byWordWrapping
		descLabel.cell?.truncatesLastVisibleLine = true
		descLabel.identifier = PetTabView.descriptionIdentifier
		descLabel.translatesAutoresizingMaskIntoConstraints = false
		descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		// Name + description in a container, vertically centered against the card
		// so short and long descriptions both stay balanced with the thumbnail
		// and the action button. The container's leading/trailing are pinned so
		// the wrapping description has a fixed width to wrap within (a bare
		// wrapping label in a stack collapses to one truncated line).
		let textContainer = NSView()
		textContainer.translatesAutoresizingMaskIntoConstraints = false
		textContainer.addSubview(nameRow)
		textContainer.addSubview(descLabel)
		card.addSubview(textContainer)

		let button = makeActionButton(for: entry)
		card.addSubview(button)

		NSLayoutConstraint.activate([
			thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
			thumb.centerYAnchor.constraint(equalTo: card.centerYAnchor),
			thumb.widthAnchor.constraint(equalToConstant: thumbSize),
			thumb.heightAnchor.constraint(equalToConstant: thumbSize),

			textContainer.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 14),
			textContainer.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -12),
			textContainer.centerYAnchor.constraint(equalTo: card.centerYAnchor),
			textContainer.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 12),

			nameRow.topAnchor.constraint(equalTo: textContainer.topAnchor),
			nameRow.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
			nameRow.trailingAnchor.constraint(lessThanOrEqualTo: textContainer.trailingAnchor),

			descLabel.topAnchor.constraint(equalTo: nameRow.bottomAnchor, constant: 4),
			descLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
			descLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
			descLabel.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),

			button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
			button.centerYAnchor.constraint(equalTo: card.centerYAnchor),
		])

		return card
	}

	private func makeActionButton(for entry: PetCatalogEntry) -> NSButton {
		let button: NSButton
		switch entry.state {
		case .selected:
			button = NSButton(title: "Selected", target: nil, action: nil)
			button.bezelStyle = .rounded
			button.isEnabled = false
		case .installed:
			button = NSButton(title: "Select", target: self, action: #selector(petCardAction(_:)))
			button.bezelStyle = .rounded
			objc_setAssociatedObject(
				button, &actionKey, ("select", entry.id), .OBJC_ASSOCIATION_RETAIN)
		case .importable:
			button = NSButton(title: "Import", target: self, action: #selector(petCardAction(_:)))
			button.bezelStyle = .rounded
			objc_setAssociatedObject(
				button, &actionKey, ("import", entry.id), .OBJC_ASSOCIATION_RETAIN)
		}
		button.translatesAutoresizingMaskIntoConstraints = false
		button.setContentHuggingPriority(.required, for: .horizontal)
		return button
	}

	private func makeBadge(text: String, tint: NSColor) -> NSView {
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: 10, weight: .medium)
		label.textColor = tint
		label.alignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		label.wantsLayer = true
		label.drawsBackground = true
		label.backgroundColor = tint.withAlphaComponent(0.14)
		label.layer?.cornerRadius = 5
		label.layer?.masksToBounds = true
		label.setContentHuggingPriority(.required, for: .horizontal)
		label.setContentCompressionResistancePriority(.required, for: .horizontal)
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
			label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5),
			label.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
			label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
		])
		container.setContentHuggingPriority(.required, for: .horizontal)
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

	@objc private func petCardAction(_ sender: NSButton) {
		guard let (action, petId) = objc_getAssociatedObject(sender, &actionKey) as? (String, String)
		else { return }
		switch action {
		case "import": onImportPet(petId)
		case "select": onSelectPet(petId)
		default: break
		}
	}
}

private var actionKey: UInt8 = 0

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

		// gate.json
		if let gatePretty = viewModel.gateJsonPretty {
			lines.append("=== gate.json ===")
			lines.append(gatePretty)
			lines.append("")
		}

		// delivery-context.json
		if let deliveryContextPretty = viewModel.deliveryContextPretty {
			lines.append("=== delivery-context.json ===")
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
	private var ttlPicker: NSPopUpButton = NSPopUpButton()

	init(viewModel: CustomizationTabViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let title = settingsSectionTitle("Customization")
		addSubview(title)

		let note = settingsBodyLabel(
			"Choose how each coding platform displays your pet. "
				+ "Own = dedicated floating window per tool. "
				+ "Combined = all active tools share one window. "
				+ "Off = no window for that tool."
		)
		addSubview(note)

		// Per-platform mode rows
		let platformTitle = settingsSectionTitle("Platform display mode")
		addSubview(platformTitle)

		var previousAnchor: NSLayoutYAxisAnchor = platformTitle.bottomAnchor
		var previousConstant: CGFloat = 10

		for origin in CustomizationTabViewModel.origins {
			let label = NSTextField(labelWithString: displayName(for: origin))
			label.font = .systemFont(ofSize: 13)
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)

			let picker = NSPopUpButton()
			picker.translatesAutoresizingMaskIntoConstraints = false
			for mode in [PlatformMode.own, .combined, .off] {
				picker.addItem(withTitle: mode.rawValue.capitalized)
				picker.lastItem?.representedObject = mode
			}
			picker.selectItem(withTitle: viewModel.mode(for: origin).rawValue.capitalized)
			picker.target = self
			picker.action = #selector(modePickerChanged(_:))
			picker.identifier = NSUserInterfaceItemIdentifier(origin)
			addSubview(picker)
			modePickers[origin] = picker

			NSLayoutConstraint.activate([
				label.topAnchor.constraint(equalTo: previousAnchor, constant: previousConstant),
				label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
				label.widthAnchor.constraint(equalToConstant: 140),

				picker.centerYAnchor.constraint(equalTo: label.centerYAnchor),
				picker.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
				picker.widthAnchor.constraint(equalToConstant: 130),
			])
			previousAnchor = label.bottomAnchor
			previousConstant = 8
		}

		// TTL row
		let ttlTitle = settingsSectionTitle("Idle dismiss")
		addSubview(ttlTitle)

		let ttlLabel = NSTextField(labelWithString: "Dismiss after idle:")
		ttlLabel.font = .systemFont(ofSize: 13)
		ttlLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(ttlLabel)

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
		addSubview(ttlPicker)

		let ttlNote = settingsBodyLabel(
			"\"Never\" keeps the pet visible until you switch tools or quit. "
				+ "Changes take effect on the next poll cycle."
		)
		addSubview(ttlNote)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			platformTitle.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 20),
			platformTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			platformTitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			ttlTitle.topAnchor.constraint(equalTo: previousAnchor, constant: 24),
			ttlTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			ttlTitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			ttlLabel.topAnchor.constraint(equalTo: ttlTitle.bottomAnchor, constant: 10),
			ttlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			ttlLabel.widthAnchor.constraint(equalToConstant: 140),

			ttlPicker.centerYAnchor.constraint(equalTo: ttlLabel.centerYAnchor),
			ttlPicker.leadingAnchor.constraint(equalTo: ttlLabel.trailingAnchor, constant: 8),
			ttlPicker.widthAnchor.constraint(equalToConstant: 130),

			ttlNote.topAnchor.constraint(equalTo: ttlLabel.bottomAnchor, constant: 8),
			ttlNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			ttlNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
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
	}

	@objc private func ttlPickerChanged(_ sender: NSPopUpButton) {
		guard let preset = sender.selectedItem?.representedObject as? IdleDismissTTL else { return }
		viewModel.setTTL(preset.rawValue)
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
			linkButton(title: "GitHub", urlString: "https://github.com/cesarnml/codogotchi"),
			linkButton(
				title: "Documentation",
				urlString: "https://github.com/cesarnml/codogotchi#readme"
			),
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

import AppKit

/// Shows the Settings window — a standard macOS window (not an `NSPanel`) with
/// four selectable tabs:
/// - **General**: per-platform hook install/uninstall/status; Cursor native-hook note.
/// - **Pet**: list + select pets from `~/.codogotchi/pets/`; import from `~/.codex/pets/`.
/// - **Developer**: read-only observability (richer wiring lands in P8.08).
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

	private let settingsController: SettingsController
	private let petImportHelper: PetImportHelper
	private let aboutViewModel: AboutViewModel
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void

	/// Called when the user activates a pet in the Pet tab. Receives the new pet ID.
	/// Wire this in `MenubarApp` to reload pet loaders and push a fresh frame.
	var onPetActivated: ((String) -> Void)?

	init(
		settingsController: SettingsController = SettingsController(),
		petImportHelper: PetImportHelper = PetImportHelper(),
		petTabViewModel: PetTabViewModel = PetTabViewModel(),
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
		let frame = CGRect(x: 0, y: 0, width: 540, height: 560)
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
		let stateJsonPath = home.appendingPathComponent("state.json").path
		let gateJsonPath = home.appendingPathComponent("gate.json").path
		let deliveryContextPath = home.appendingPathComponent("delivery-context.json").path
		let logPath = TransitionLog.defaultPath().path
		let snapshot = appStateLoader().hooksStatus
		return DeveloperTabViewModel(
			stateJsonPath: stateJsonPath,
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
			"Install hooks wires Codex, Claude Code, and Cursor together for every "
				+ "tool you have installed — re-run any time to update. Cursor only reads "
				+ "hooks at launch, so restart it after installing."
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

/// Pet tab — lists all pets from three sources (bundled Maew, Codex, canonical store),
/// shows the active pet, and provides Select / Import actions per pet.
private final class PetTabView: NSView {
	private var viewModel: PetTabViewModel
	private let onImportPet: (String) -> Void
	private let onSelectPet: (String) -> Void

	private let petListStack = NSStackView()
	private let feedbackLabel = NSTextField(wrappingLabelWithString: "")

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

	/// Rebuild the pet list rows from the current ViewModel state.
	func refreshPetList(viewModel: PetTabViewModel) {
		self.viewModel = viewModel
		// `removeArrangedSubview` only unmanages the layout; the view stays in the
		// hierarchy at its old frame and the rebuilt rows paint on top of it
		// (Import/Select and "(active)"/Active overlap). Tear the row out of the
		// hierarchy too.
		for view in petListStack.arrangedSubviews {
			petListStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		buildPetRows()
	}

	private func setupViews() {
		let title = settingsSectionTitle("Pet")
		addSubview(title)

		let storeNote = settingsBodyLabel(
			"Pets are loaded from ~/.codogotchi/pets/. "
				+ "Import from ~/.codex/pets/ to make them available here."
		)
		addSubview(storeNote)

		petListStack.orientation = .vertical
		petListStack.alignment = .leading
		petListStack.spacing = 6
		petListStack.translatesAutoresizingMaskIntoConstraints = false
		buildPetRows()
		addSubview(petListStack)

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
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			storeNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			storeNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			petListStack.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 12),
			petListStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			petListStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			feedbackLabel.topAnchor.constraint(equalTo: petListStack.bottomAnchor, constant: 8),
			feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			feedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
		])
	}

	private func buildPetRows() {
		let fm = FileManager.default
		let codexIds = Set(
			(try? fm.contentsOfDirectory(
				at: viewModel.codexPetsRoot,
				includingPropertiesForKeys: [.isDirectoryKey], options: []
			))?.compactMap { url -> String? in
				let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
				return isDir ? url.lastPathComponent : nil
			} ?? []
		)

		for petId in viewModel.allPetIds() {
			let isActive = petId == viewModel.activePetId
			let isInCodexOnly = codexIds.contains(petId) && !isCanonical(petId)

			let nameLabel = NSTextField(labelWithString: isActive ? "\(petId) (active)" : petId)
			nameLabel.font = isActive ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)

			let actionButton: NSButton
			if isInCodexOnly {
				actionButton = NSButton(title: "Import", target: nil, action: nil)
				actionButton.bezelStyle = .rounded
				actionButton.target = self
				let capturedId = petId
				actionButton.action = #selector(petRowAction(_:))
				objc_setAssociatedObject(actionButton, &actionKey, ("import", capturedId), .OBJC_ASSOCIATION_RETAIN)
			} else {
				actionButton = NSButton(title: isActive ? "Active" : "Select", target: nil, action: nil)
				actionButton.bezelStyle = .rounded
				actionButton.isEnabled = !isActive
				let capturedId = petId
				actionButton.action = #selector(petRowAction(_:))
				actionButton.target = self
				objc_setAssociatedObject(actionButton, &actionKey, ("select", capturedId), .OBJC_ASSOCIATION_RETAIN)
			}

			let row = NSStackView(views: [nameLabel, actionButton])
			row.orientation = .horizontal
			row.spacing = 8
			row.alignment = .centerY
			petListStack.addArrangedSubview(row)
		}
	}

	private func isCanonical(_ petId: String) -> Bool {
		let petDir = viewModel.canonicalPetsRoot.appendingPathComponent(petId)
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: petDir.path, isDirectory: &isDir), isDir.boolValue
		else { return false }
		return FileManager.default.fileExists(
			atPath: petDir.appendingPathComponent("pet.json").path)
	}

	@objc private func petRowAction(_ sender: NSButton) {
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

// MARK: - DeveloperTabView

/// Developer tab — read-only observability. Shows state.json, gate.json,
/// last 5 transitions, schema version, hooks summary, and platform attribution note.
private final class DeveloperTabView: NSView {
	private var viewModel: DeveloperTabViewModel
	private let scrollView = NSScrollView()
	private let textView = NSTextView()
	private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

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
		lines.append("state.json: v\(sv == 0 ? "?" : "\(sv)")   renderer: v\(rv)")
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

		// state.json
		lines.append("=== state.json ===")
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

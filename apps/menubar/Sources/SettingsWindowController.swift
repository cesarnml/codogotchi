import AppKit

/// Shows the Settings window — a standard macOS window (not an `NSPanel`) with
/// four selectable tabs:
/// - **General**: per-platform hook install/uninstall/status; bridge note for Cursor.
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

	private let settingsController: SettingsController
	private let petImportHelper: PetImportHelper
	private let aboutViewModel: AboutViewModel
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void

	init(
		settingsController: SettingsController = SettingsController(),
		petImportHelper: PetImportHelper = PetImportHelper(),
		aboutViewModel: AboutViewModel = AboutViewModel(),
		appStateLoader: @escaping () -> FloatingAppState = {
			AppStateStore.load(visibleFrame: NSScreen.main?.visibleFrame ?? .zero)
		},
		appStateSaver: @escaping (FloatingAppState) throws -> Void = AppStateStore.save
	) {
		self.settingsController = settingsController
		self.petImportHelper = petImportHelper
		self.aboutViewModel = aboutViewModel
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
		generalTab?.updateHookStatus(snapshot)
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

		let snapshot = appStateLoader().hooksStatus

		let general = GeneralTabView(
			initialHooksStatus: snapshot,
			onInstallHooks: { [weak self] in self?.handleInstallHooks() },
			onUninstallHooks: { [weak self] in self?.handleUninstallHooks() }
		)
		let pet = PetTabView(
			availableCodexPets: petImportHelper.availableCodexPets(),
			onImportPet: { [weak self] petId in self?.handleImportPet(id: petId) }
		)
		let developer = DeveloperTabView()
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
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksInstall()
			DispatchQueue.main.async {
				guard let self else { return }
				if let msg = error {
					self.generalTab?.setHooksError(msg)
				} else {
					self.generalTab?.setHooksSuccess(message: "Installed.")
				}
			}
		}
	}

	private func handleUninstallHooks() {
		generalTab?.setHooksWorking(message: "Uninstalling…")
		let controller = settingsController
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksUninstall()
			DispatchQueue.main.async {
				guard let self else { return }
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
			try petImportHelper.importPet(id: id)
			petTab?.setPetImportSuccess(petId: id)
		} catch {
			petTab?.setPetImportError(String(describing: error))
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

// MARK: - GeneralTabView (Hooks)

/// General tab — hook install/uninstall/status. Content preserved verbatim from
/// the previous Hooks section; only the hosting container changed (P8.04 adds
/// the richer app-owned façade wiring).
private final class GeneralTabView: NSView {
	private let hooksStatusLabel = NSTextField(wrappingLabelWithString: "")
	private let installButton = NSButton(title: "Install", target: nil, action: nil)
	private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
	private let hooksFeedbackLabel = NSTextField(wrappingLabelWithString: "")

	private let onInstallHooks: () -> Void
	private let onUninstallHooks: () -> Void

	init(
		initialHooksStatus: HooksStatusSnapshot?,
		onInstallHooks: @escaping () -> Void,
		onUninstallHooks: @escaping () -> Void
	) {
		self.onInstallHooks = onInstallHooks
		self.onUninstallHooks = onUninstallHooks
		super.init(frame: .zero)
		setupViews()
		if let snap = initialHooksStatus {
			applyHooksStatus(snap)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func updateHookStatus(_ snapshot: HooksStatusSnapshot) {
		applyHooksStatus(snapshot)
	}

	func setHooksWorking(message: String) {
		installButton.isEnabled = false
		uninstallButton.isEnabled = false
		hooksFeedbackLabel.stringValue = message
		hooksFeedbackLabel.textColor = .secondaryLabelColor
	}

	func setHooksSuccess(message: String) {
		installButton.isEnabled = true
		uninstallButton.isEnabled = true
		hooksFeedbackLabel.stringValue = message
		hooksFeedbackLabel.textColor = .systemGreen
	}

	func setHooksError(_ message: String) {
		installButton.isEnabled = true
		uninstallButton.isEnabled = true
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

		let buttonRow = NSStackView(views: [installButton, uninstallButton])
		buttonRow.orientation = .horizontal
		buttonRow.spacing = 8
		buttonRow.translatesAutoresizingMaskIntoConstraints = false
		installButton.bezelStyle = .rounded
		installButton.target = self
		installButton.action = #selector(installTapped)
		uninstallButton.bezelStyle = .rounded
		uninstallButton.target = self
		uninstallButton.action = #selector(uninstallTapped)
		addSubview(buttonRow)

		hooksFeedbackLabel.isEditable = false
		hooksFeedbackLabel.isBordered = false
		hooksFeedbackLabel.backgroundColor = .clear
		hooksFeedbackLabel.font = .systemFont(ofSize: 11)
		hooksFeedbackLabel.textColor = .secondaryLabelColor
		hooksFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(hooksFeedbackLabel)

		let bridgeNote = settingsBodyLabel(
			"Cursor support routes via Claude Code hooks. See README for details."
		)
		addSubview(bridgeNote)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			hooksStatusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
			hooksStatusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			hooksStatusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			buttonRow.topAnchor.constraint(equalTo: hooksStatusLabel.bottomAnchor, constant: 12),
			buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			hooksFeedbackLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 8),
			hooksFeedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			hooksFeedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			bridgeNote.topAnchor.constraint(equalTo: hooksFeedbackLabel.bottomAnchor, constant: 8),
			bridgeNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			bridgeNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
		])
	}

	private func applyHooksStatus(_ snap: HooksStatusSnapshot) {
		func platformLine(_ name: String, _ p: HooksStatusSnapshot.Platform) -> String {
			var parts: [String] = [name]
			if p.installableInPhase {
				parts.append(p.installed ? "installed" : "not installed")
				if p.firingRecently { parts.append("firing") }
				if let t = p.lastEventAt { parts.append("last: \(t)") }
				if let o = p.sourceOrigin { parts.append("via \(o)") }
			} else {
				parts.append("bridge (not directly installable)")
			}
			return parts.joined(separator: " · ")
		}

		let lines = [
			platformLine("Codex", snap.codex),
			platformLine("Claude Code", snap.claudeCode),
			platformLine("Cursor", snap.cursor),
			platformLine("VS Code", snap.vscode),
			platformLine("Antigravity", snap.antigravity),
		]
		hooksStatusLabel.stringValue = lines.joined(separator: "\n")
	}

	@objc private func installTapped() { onInstallHooks() }
	@objc private func uninstallTapped() { onUninstallHooks() }
}

// MARK: - PetTabView

/// Pet tab — list/import pets. Content preserved verbatim from the previous Pet
/// section; richer enumerate/select wiring lands in P8.07.
private final class PetTabView: NSView {
	private let petPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let importButton = NSButton(title: "Import from Codex…", target: nil, action: nil)
	private let petFeedbackLabel = NSTextField(wrappingLabelWithString: "")

	private let onImportPet: (String) -> Void
	private let codexPetIds: [String]

	init(
		availableCodexPets: [String],
		onImportPet: @escaping (String) -> Void
	) {
		self.codexPetIds = availableCodexPets
		self.onImportPet = onImportPet
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func setPetImportSuccess(petId: String) {
		petFeedbackLabel.stringValue = "Imported \(petId) to ~/.codogotchi/pets/."
		petFeedbackLabel.textColor = .systemGreen
	}

	func setPetImportError(_ message: String) {
		petFeedbackLabel.stringValue = message
		petFeedbackLabel.textColor = .systemRed
	}

	private func setupViews() {
		let title = settingsSectionTitle("Pet")
		addSubview(title)

		let storeNote = settingsBodyLabel("Pets are loaded from ~/.codogotchi/pets/.")
		addSubview(storeNote)

		let importRow = NSStackView(views: [importButton, petPopup])
		importRow.orientation = .horizontal
		importRow.spacing = 8
		importRow.translatesAutoresizingMaskIntoConstraints = false
		importButton.bezelStyle = .rounded
		importButton.target = self
		importButton.action = #selector(importPetTapped)
		importButton.isEnabled = !codexPetIds.isEmpty

		petPopup.removeAllItems()
		if codexPetIds.isEmpty {
			petPopup.addItem(withTitle: "No Codex pets found")
			petPopup.isEnabled = false
		} else {
			for id in codexPetIds { petPopup.addItem(withTitle: id) }
			petPopup.isEnabled = true
		}
		addSubview(importRow)

		petFeedbackLabel.isEditable = false
		petFeedbackLabel.isBordered = false
		petFeedbackLabel.backgroundColor = .clear
		petFeedbackLabel.font = .systemFont(ofSize: 11)
		petFeedbackLabel.textColor = .secondaryLabelColor
		petFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(petFeedbackLabel)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			storeNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			storeNote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			importRow.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 12),
			importRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

			petFeedbackLabel.topAnchor.constraint(equalTo: importRow.bottomAnchor, constant: 8),
			petFeedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			petFeedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
		])
	}

	@objc private func importPetTapped() {
		let selected = petPopup.titleOfSelectedItem ?? ""
		guard !selected.isEmpty, selected != "No Codex pets found" else { return }
		onImportPet(selected)
	}
}

// MARK: - DeveloperTabView

/// Developer tab — read-only observability placeholder. Live `state.json` /
/// `gate.json`, the last transitions, and the schema-vs-renderer version land in
/// P8.08; this ticket establishes the selectable tab so there is no dead-end.
private final class DeveloperTabView: NSView {
	init() {
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let title = settingsSectionTitle("Developer")
		addSubview(title)

		let note = settingsBodyLabel(
			"Read-only observability — live state, recent transitions, and the "
				+ "schema-vs-renderer version — arrives in a later update."
		)
		addSubview(note)

		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
		])
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

import AppKit

/// Shows the Minimal Settings window with three sections:
/// - **Hooks**: per-platform install/uninstall/status for Codex + Claude Code; bridge note for Cursor.
/// - **Pet**: list + select pets from `~/.codogotchi/pets/`; import from `~/.codex/pets/`.
/// - **Alive (RPG)**: stub directing the user to `codogotchi rpg` in Terminal.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
	static let windowTitle = "Codogotchi Settings"

	private var window: NSPanel?
	private var contentView: SettingsContentView?

	private let settingsController: SettingsController
	private let petImportHelper: PetImportHelper
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void

	init(
		settingsController: SettingsController = SettingsController(),
		petImportHelper: PetImportHelper = PetImportHelper(),
		appStateLoader: @escaping () -> FloatingAppState = {
			AppStateStore.load(visibleFrame: NSScreen.main?.visibleFrame ?? .zero)
		},
		appStateSaver: @escaping (FloatingAppState) throws -> Void = AppStateStore.save
	) {
		self.settingsController = settingsController
		self.petImportHelper = petImportHelper
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

	/// Refreshes the Hooks section with a fresh status snapshot.
	func updateHookStatus(_ snapshot: HooksStatusSnapshot) {
		contentView?.updateHookStatus(snapshot)
	}

	// MARK: - NSWindowDelegate

	func windowWillClose(_ notification: Notification) {
		window = nil
		contentView = nil
	}

	// MARK: - Private

	private func openWindow() {
		let frame = CGRect(x: 0, y: 0, width: 520, height: 560)
		let p = NSPanel(
			contentRect: frame,
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		p.title = Self.windowTitle
		p.isReleasedWhenClosed = false
		p.level = .floating
		p.hidesOnDeactivate = false
		p.minSize = CGSize(width: 420, height: 480)
		p.delegate = self
		p.center()

		let snapshot = appStateLoader().hooksStatus
		let content = SettingsContentView(
			frame: CGRect(origin: .zero, size: frame.size),
			initialHooksStatus: snapshot,
			availableCodexPets: petImportHelper.availableCodexPets(),
			onInstallHooks: { [weak self] in self?.handleInstallHooks() },
			onUninstallHooks: { [weak self] in self?.handleUninstallHooks() },
			onImportPet: { [weak self] petId in self?.handleImportPet(id: petId) }
		)
		content.autoresizingMask = [.width, .height]
		p.contentView = content

		p.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.window = p
		self.contentView = content
	}

	private func handleInstallHooks() {
		contentView?.setHooksWorking(message: "Installing…")
		let controller = settingsController
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksInstall()
			DispatchQueue.main.async {
				guard let self else { return }
				if let msg = error {
					self.contentView?.setHooksError(msg)
				} else {
					self.contentView?.setHooksSuccess(message: "Installed.")
				}
			}
		}
	}

	private func handleUninstallHooks() {
		contentView?.setHooksWorking(message: "Uninstalling…")
		let controller = settingsController
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = controller.runHooksUninstall()
			DispatchQueue.main.async {
				guard let self else { return }
				if let msg = error {
					self.contentView?.setHooksError(msg)
				} else {
					self.contentView?.setHooksSuccess(message: "Uninstalled.")
				}
			}
		}
	}

	private func handleImportPet(id: String) {
		do {
			try petImportHelper.importPet(id: id)
			contentView?.setPetImportSuccess(petId: id)
		} catch {
			contentView?.setPetImportError(String(describing: error))
		}
	}
}

// MARK: - SettingsContentView

/// Full programmatic AppKit view — three sections stacked vertically in a scroll view.
private final class SettingsContentView: NSView {
	private let scrollView = NSScrollView()
	private let stackView = NSStackView()

	// Hooks section controls
	private let hooksStatusLabel = NSTextField(wrappingLabelWithString: "")
	private let installButton = NSButton(title: "Install", target: nil, action: nil)
	private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
	private let hooksFeedbackLabel = NSTextField(wrappingLabelWithString: "")

	// Pet section controls
	private let petPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let importButton = NSButton(title: "Import from Codex…", target: nil, action: nil)
	private let petFeedbackLabel = NSTextField(wrappingLabelWithString: "")

	private let onInstallHooks: () -> Void
	private let onUninstallHooks: () -> Void
	private let onImportPet: (String) -> Void
	private var codexPetIds: [String]

	init(
		frame: CGRect,
		initialHooksStatus: HooksStatusSnapshot?,
		availableCodexPets: [String],
		onInstallHooks: @escaping () -> Void,
		onUninstallHooks: @escaping () -> Void,
		onImportPet: @escaping (String) -> Void
	) {
		self.onInstallHooks = onInstallHooks
		self.onUninstallHooks = onUninstallHooks
		self.onImportPet = onImportPet
		self.codexPetIds = availableCodexPets
		super.init(frame: frame)
		setupViews()
		if let snap = initialHooksStatus {
			applyHooksStatus(snap)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	// MARK: - Public state updates

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

	func setPetImportSuccess(petId: String) {
		petFeedbackLabel.stringValue = "Imported \(petId) to ~/.codogotchi/pets/."
		petFeedbackLabel.textColor = .systemGreen
	}

	func setPetImportError(_ message: String) {
		petFeedbackLabel.stringValue = message
		petFeedbackLabel.textColor = .systemRed
	}

	// MARK: - Setup

	private func setupViews() {
		wantsLayer = true

		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scrollView)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		stackView.orientation = .vertical
		stackView.alignment = .leading
		stackView.spacing = 0
		stackView.translatesAutoresizingMaskIntoConstraints = false

		let clipView = scrollView.contentView
		scrollView.documentView = stackView
		NSLayoutConstraint.activate([
			stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
			stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
		])

		stackView.addArrangedSubview(makeHooksSection())
		stackView.addArrangedSubview(makeDivider())
		stackView.addArrangedSubview(makePetSection())
		stackView.addArrangedSubview(makeDivider())
		stackView.addArrangedSubview(makeAliveSection())
	}

	// MARK: - Section builders

	private func makeHooksSection() -> NSView {
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false

		let title = sectionTitle("Hooks")
		container.addSubview(title)

		hooksStatusLabel.isEditable = false
		hooksStatusLabel.isBordered = false
		hooksStatusLabel.backgroundColor = .clear
		hooksStatusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		hooksStatusLabel.textColor = .secondaryLabelColor
		hooksStatusLabel.stringValue = "Loading…"
		hooksStatusLabel.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(hooksStatusLabel)

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
		container.addSubview(buttonRow)

		hooksFeedbackLabel.isEditable = false
		hooksFeedbackLabel.isBordered = false
		hooksFeedbackLabel.backgroundColor = .clear
		hooksFeedbackLabel.font = .systemFont(ofSize: 11)
		hooksFeedbackLabel.textColor = .secondaryLabelColor
		hooksFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(hooksFeedbackLabel)

		let bridgeNote = bodyLabel(
			"Cursor support routes via Claude Code hooks. See README for details."
		)
		container.addSubview(bridgeNote)

		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),

			title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			hooksStatusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
			hooksStatusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			hooksStatusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			buttonRow.topAnchor.constraint(equalTo: hooksStatusLabel.bottomAnchor, constant: 12),
			buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

			hooksFeedbackLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 8),
			hooksFeedbackLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			hooksFeedbackLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			bridgeNote.topAnchor.constraint(equalTo: hooksFeedbackLabel.bottomAnchor, constant: 8),
			bridgeNote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			bridgeNote.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
			bridgeNote.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
		])

		return container
	}

	private func makePetSection() -> NSView {
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false

		let title = sectionTitle("Pet")
		container.addSubview(title)

		let storeNote = bodyLabel("Pets are loaded from ~/.codogotchi/pets/.")
		container.addSubview(storeNote)

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
		container.addSubview(importRow)

		petFeedbackLabel.isEditable = false
		petFeedbackLabel.isBordered = false
		petFeedbackLabel.backgroundColor = .clear
		petFeedbackLabel.font = .systemFont(ofSize: 11)
		petFeedbackLabel.textColor = .secondaryLabelColor
		petFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(petFeedbackLabel)

		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),

			title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			storeNote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			storeNote.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			importRow.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 12),
			importRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

			petFeedbackLabel.topAnchor.constraint(equalTo: importRow.bottomAnchor, constant: 8),
			petFeedbackLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			petFeedbackLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
			petFeedbackLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
		])

		return container
	}

	private func makeAliveSection() -> NSView {
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false

		let title = sectionTitle("Alive (RPG)")
		container.addSubview(title)

		let note = bodyLabel(
			"RPG enrollment links your pet to Convex for XP and status tracking.\n\n"
			+ "To enroll, run in Terminal:\n  codogotchi rpg"
		)
		container.addSubview(note)

		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),

			title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
			title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

			note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
			note.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
			note.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
			note.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
		])

		return container
	}

	private func makeDivider() -> NSView {
		let separator = NSBox()
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		return separator
	}

	// MARK: - Helpers

	private func sectionTitle(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.textColor = .labelColor
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	private func bodyLabel(_ text: String) -> NSTextField {
		let label = NSTextField(wrappingLabelWithString: text)
		label.isEditable = false
		label.isBordered = false
		label.backgroundColor = .clear
		label.font = .systemFont(ofSize: 12)
		label.textColor = .secondaryLabelColor
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
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

	// MARK: - Actions

	@objc private func installTapped() { onInstallHooks() }
	@objc private func uninstallTapped() { onUninstallHooks() }

	@objc private func importPetTapped() {
		let selected = petPopup.titleOfSelectedItem ?? ""
		guard !selected.isEmpty, selected != "No Codex pets found" else { return }
		onImportPet(selected)
	}
}

import AppKit

// MARK: - GeneralTabView (Hooks)

/// General tab — per-platform hook status table, Install/Update/Remove/Copy
/// diagnostics strip directly beneath it, then a single dynamic status panel
/// (idle/stale/new-tool-detected, or in-flight action feedback), then the
/// menu-bar-icon toggle row, all inside one themed card.
final class GeneralTabView: NSView {
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


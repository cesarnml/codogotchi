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
	private let platformChipAnimationSwitch = NSSwitch()

	private let onInstallHooks: () -> Void
	private let onUpdateHooks: () -> Void
	private let onUninstallHooks: () -> Void
	var onMonochromeToggled: ((Bool) -> Void)?
	var onRequirePruneConfirmationToggled: ((Bool) -> Void)?
	var onPlatformChipAnimationToggled: ((Bool) -> Void)?
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
		platformChipAnimationSwitch.state = vm.platformChipAnimationEnabled ? .on : .off
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

		requirePruneConfirmationSwitch.target = self
		requirePruneConfirmationSwitch.action = #selector(requirePruneConfirmationToggleChanged)

		platformChipAnimationSwitch.target = self
		platformChipAnimationSwitch.action = #selector(platformChipAnimationToggleChanged)

		// Toggle strips per the mockup: icon badge + title/subtitle on the left, a
		// switch on the right, each in its own shaded strip stacked at the card's
		// bottom.
		let monoRow = makeToggleRow(
			symbolName: "list.bullet",
			title: "Monochrome menu bar icon",
			subtitle: "Use a monochrome icon in the macOS menu bar.",
			toggle: monochromeSwitch
		)
		let pruneRow = makeToggleRow(
			symbolName: "shield",
			title: "Require Prune Session confirmation",
			subtitle:
				"Show a confirmation dialog before pruning session data. When off, pruning will happen immediately.",
			toggle: requirePruneConfirmationSwitch
		)
		let chipAnimationRow = makeToggleRow(
			symbolName: "sparkles",
			title: "Animate platform logo while working",
			subtitle:
				"Spin the coding tool's logo on the pet's badge while that tool is mid-turn.",
			toggle: platformChipAnimationSwitch
		)
		[monoRow, pruneRow, chipAnimationRow].forEach(card.addSubview)

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
			monoRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

			pruneRow.topAnchor.constraint(equalTo: monoRow.bottomAnchor, constant: 10),
			pruneRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			pruneRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			pruneRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

			chipAnimationRow.topAnchor.constraint(equalTo: pruneRow.bottomAnchor, constant: 10),
			chipAnimationRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			chipAnimationRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			chipAnimationRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
			chipAnimationRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	/// Builds one shaded toggle strip — badge glyph, title, wrapping subtitle, and
	/// a trailing switch. The three General-tab toggles share this shape; the
	/// caller owns the switch (target/action and state) and the row's placement
	/// within the card.
	private func makeToggleRow(
		symbolName: String,
		title: String,
		subtitle: String,
		toggle: NSSwitch
	) -> NSView {
		let row = NSView()
		row.translatesAutoresizingMaskIntoConstraints = false
		row.wantsLayer = true
		row.layer?.cornerRadius = 8
		row.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor

		let badge = NSView()
		badge.translatesAutoresizingMaskIntoConstraints = false
		badge.wantsLayer = true
		badge.layer?.cornerRadius = 6
		badge.layer?.backgroundColor = SettingsTheme.buttonBackground.cgColor
		row.addSubview(badge)

		let glyph = NSImageView()
		glyph.translatesAutoresizingMaskIntoConstraints = false
		glyph.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
		glyph.contentTintColor = .secondaryLabelColor
		glyph.imageScaling = .scaleProportionallyUpOrDown
		badge.addSubview(glyph)

		let titleLabel = NSTextField(labelWithString: title)
		titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(titleLabel)

		let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
		subtitleLabel.font = .systemFont(ofSize: 11)
		subtitleLabel.textColor = .secondaryLabelColor
		subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(subtitleLabel)

		toggle.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(toggle)

		NSLayoutConstraint.activate([
			badge.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
			badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			badge.widthAnchor.constraint(equalToConstant: 28),
			badge.heightAnchor.constraint(equalToConstant: 28),

			glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
			glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
			glyph.widthAnchor.constraint(equalToConstant: 14),
			glyph.heightAnchor.constraint(equalToConstant: 14),

			titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
			titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),

			subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
			subtitleLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
			subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -10),

			toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
			toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
		])
		return row
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
	@objc private func platformChipAnimationToggleChanged() {
		onPlatformChipAnimationToggled?(platformChipAnimationSwitch.state == .on)
	}

	@objc private func copyDiagnosticsTapped() {
		let json = viewModel.diagnosticsJSON()
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(json, forType: .string)
		statusPanel.state = .success("Diagnostics copied to clipboard.")
	}
}

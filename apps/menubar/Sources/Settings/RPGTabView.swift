import AppKit

// MARK: - RPGTabView

/// RPG tab — HUD opt-out toggle and demo mode preview.
final class RPGTabView: NSView {
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

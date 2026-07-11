import AppKit

// MARK: - CustomizationTabView

/// Customization tab — per-platform mode pickers and idle-dismiss TTL.
///
/// Origins are shown in the fixed order defined by `CustomizationTabViewModel.origins`
/// so the UI is stable across sessions regardless of which platforms are active.
final class CustomizationTabView: NSView {
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


import AppKit

// MARK: - SessionsTabView

/// Sessions tab — visualizes every `state.d/` slice bucketed into the three
/// lifecycle tiers `SessionsTabViewModel` computes: Active (rendered or
/// renderable via Show/Hide All Pets), Live (fresh but not currently
/// rendered), and Archived (past the reader's fresh window, short of
/// `SlicePruner`'s deletion horizon). One themed section per tier, scrolled
/// together since the row count is unbounded; `reload(viewModel:)` tears
/// down and rebuilds, mirroring `RPGTabView`'s pattern for viewModel swaps.
final class SessionsTabView: NSView {
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

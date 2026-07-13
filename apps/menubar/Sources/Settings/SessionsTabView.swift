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
		// setupViews() below swaps in a brand-new documentView. Every
		// Show/Hide/Prune action rebuilds via reload(), so without restoring
		// scroll position the view would jerk back to the top of the list on
		// every single action.
		//
		// (P18-QC) contentStack is a `FlippedStackView` (top-down
		// coordinates), so origin.y already measures distance from the top
		// of the document directly — just clamp it to the new document's
		// valid scroll range, since a Prune action can shrink the document
		// height enough that the old origin.y would otherwise point past
		// the end of the (now shorter) content.
		let visibleHeight = scrollView.contentView.bounds.height
		let savedOriginY = scrollView.contentView.bounds.origin.y
		NSLayoutConstraint.deactivate(constraints)
		subviews.forEach { $0.removeFromSuperview() }
		setupViews()
		layoutSubtreeIfNeeded()
		let newDocumentHeight = scrollView.documentView?.frame.height ?? 0
		let newOriginY = min(savedOriginY, max(0, newDocumentHeight - visibleHeight))
		scrollView.contentView.scroll(
			to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: newOriginY))
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

		// A third divider ahead of the top-level "Prune All Sessions" escape
		// hatch, matching ttlDivider's same visual treatment.
		let pruneAllDivider = NSView()
		pruneAllDivider.translatesAutoresizingMaskIntoConstraints = false
		pruneAllDivider.wantsLayer = true
		pruneAllDivider.layer?.backgroundColor = SettingsTheme.cardBorder.cgColor
		NSLayoutConstraint.activate([
			pruneAllDivider.widthAnchor.constraint(equalToConstant: 1),
			pruneAllDivider.heightAnchor.constraint(equalToConstant: 26),
		])

		let pruneAllSessionsButton = ActionButton(
			title: "Prune All Sessions", tint: .systemRed,
			action: { [weak self] in self?.pruneAllSessions() })

		let ttlRow = NSStackView(views: [
			archiveLabel, archiveAfterIdlePicker, ttlDivider, pruneLabel, pruneArchivedPicker,
			pruneAllDivider, pruneAllSessionsButton,
		])
		ttlRow.orientation = .horizontal
		ttlRow.alignment = .centerY
		ttlRow.spacing = 12
		// Generous breathing room on both sides of each divider so every
		// group reads as a separate setting, not one run-on control strip.
		ttlRow.setCustomSpacing(28, after: archiveAfterIdlePicker)
		ttlRow.setCustomSpacing(28, after: ttlDivider)
		ttlRow.setCustomSpacing(28, after: pruneArchivedPicker)
		ttlRow.setCustomSpacing(28, after: pruneAllDivider)
		ttlRow.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(ttlRow)

		// (P18-QC) A plain NSStackView is not flipped, so used directly as
		// documentView its top-down layout renders bottom-anchored: when the
		// stack is shorter than the visible clip area, AppKit pins the
		// stack's bottom to the clip view's bottom, leaving empty space
		// ABOVE the content — the tab looked permanently "collapsed
		// downward," even on first launch before any Show/Hide/Prune ever
		// ran reload(). FlippedStackView (already used by PetTabView for the
		// same reason) fixes this.
		let contentStack = FlippedStackView()
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
			bulkActions: viewModel.activeRows.contains(where: { $0.sessionId != nil })
				? [("Prune All Active", { [weak self] in self?.pruneAllActive() })]
				: [],
			onShow: { [weak self] row in self?.show(row) },
			onHide: { [weak self] row in self?.hide(row) },
			onPrune: { [weak self] row in self?.pruneActive(row) }
		)
		contentStack.addArrangedSubview(activeSection)
		activeSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

		var liveBulkActions: [(title: String, action: () -> Void)] = []
		if !viewModel.liveRows.isEmpty {
			liveBulkActions.append(("Show All Live", { [weak self] in self?.showAllLive() }))
			liveBulkActions.append(("Prune All Live", { [weak self] in self?.pruneAllLive() }))
		}
		let liveSection = SessionTierSectionView(
			title: "Live",
			iconSymbol: "clock.fill",
			tint: .systemYellow,
			rows: viewModel.liveRows,
			emptyText: "No sessions are waiting to be resumed.",
			bulkActions: liveBulkActions,
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
			bulkActions: viewModel.archivedRows.isEmpty
				? []
				: [("Prune All Archived", { [weak self] in self?.pruneAllArchived() })],
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

	private func pruneAllLive() {
		viewModel.pruneAllLive()
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
	/// alert with a "Do not show this warning again." checkbox that persists
	/// the skip. Shared by the single-row Active prune and both bulk
	/// Active-touching actions ("Prune All Active", "Prune All Sessions") —
	/// Live/Archived rows are already non-rendered/idle, so their bulk
	/// actions skip confirmation, matching the pre-existing "Prune All
	/// Archived" affordance.
	private func confirmDestructivePrune(
		messageText: String, informativeText: String, onConfirm: () -> Void
	) {
		guard !PetConfig.resolvedSkipPruneConfirmation() else {
			onConfirm()
			return
		}
		let alert = NSAlert()
		alert.messageText = messageText
		alert.informativeText = informativeText
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
		onConfirm()
	}

	private func pruneActive(_ row: SessionRow) {
		confirmDestructivePrune(
			messageText: "Prune Session",
			informativeText: "This destroys the panel and its session data. This cannot be undone."
		) { [weak self] in
			guard let self else { return }
			viewModel.pruneActive(row: row)
			reload(viewModel: viewModel)
		}
	}

	private func pruneAllActive() {
		confirmDestructivePrune(
			messageText: "Prune All Active Sessions",
			informativeText:
				"This destroys every active session's panel and session data. This cannot be undone."
		) { [weak self] in
			guard let self else { return }
			viewModel.pruneAllActive()
			reload(viewModel: viewModel)
		}
	}

	private func pruneAllSessions() {
		confirmDestructivePrune(
			messageText: "Prune All Sessions",
			informativeText:
				"This destroys every Active, Live, and Archived session's data across every tier. This cannot be undone."
		) { [weak self] in
			guard let self else { return }
			viewModel.pruneAllSessions()
			reload(viewModel: viewModel)
		}
	}
}

/// One tier's card: icon badge + title + count pill + optional bulk-action
/// button in the header, then one `SessionRowView` per row (or an empty-state
/// label when there are none).

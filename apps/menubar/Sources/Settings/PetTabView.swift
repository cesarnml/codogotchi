import AppKit

// MARK: - PetTabView

/// Pet tab — a single flat grid of pet cards. Every pet appears once,
/// deduplicated across the bundled, Codex, and canonical-store sources.
///
/// Installed pets show a portrait thumbnail (raised to align with the pet name)
/// and an Assign icon in the name row that opens a multiselect badge dropdown.
/// Importable pets (present only under `~/.codex/pets/`) show an Import icon
/// centered beneath the thumbnail. Assigned badge pills appear below the
/// description. The Default badge holder carries a blue selection border.
final class PetTabView: NSView, NSSearchFieldDelegate {
	/// View identifiers used by layout tests to locate cards and their
	/// description labels in the rendered hierarchy.
	static let cardIdentifier = NSUserInterfaceItemIdentifier("petCard")
	static let descriptionIdentifier = NSUserInterfaceItemIdentifier("petCardDescription")
	static let badgePillsIdentifier = NSUserInterfaceItemIdentifier("petCardBadgePills")

	private var viewModel: PetTabViewModel
	private let onImportPet: (String) -> Void

	private let searchField = NSSearchField()
	private let openFolderButton = NSButton(title: "Open pet folder", target: nil, action: nil)
	private let gridScrollView = NSScrollView()
	/// Flipped so a short grid (few search results) anchors to the TOP of the
	/// scroll area. A default non-flipped document view sinks short content to
	/// the bottom — the scroll origin sits bottom-left.
	private let gridStack = FlippedStackView()
	private let emptyLabel = NSTextField(labelWithString: "")
	private let footerLabel = NSTextField(labelWithString: "")
	private let feedbackLabel: NSTextField = {
		let label = NSTextField(wrappingLabelWithString: "")
		// `wrappingLabelWithString:` returns a *selectable* field; a caption
		// should not show an I-beam or highlight when dragged across.
		label.isSelectable = false
		return label
	}()
	private var feedbackHeightConstraint: NSLayoutConstraint?

	/// Idle-frame thumbnails are sliced once and cached by spritesheet path so
	/// repeated grid rebuilds (resize, assign, search) don't re-decode WebP.
	private var thumbnailCache: [String: NSImage?] = [:]
	/// Column count last laid out — guards `layout()` from rebuilding the grid
	/// on every resize tick, only when the responsive column count changes.
	private var lastColumnCount = 0
	private var currentEntries: [PetCatalogEntry] = []
	private var activeAssignPopover: NSPopover?
	/// Live card chrome keyed by pet id so assign toggles can update logo pills
	/// and the Default border without destroying the popover's anchor button.
	private var cardViewsByPetId: [String: NSView] = [:]
	private var pillsRowsByPetId: [String: NSStackView] = [:]

	private let cardSpacing: CGFloat = 12
	private let minCardWidth: CGFloat = 300
	private let maxColumns = 3
	private let thumbSize: CGFloat = 64

	init(
		viewModel: PetTabViewModel,
		onImportPet: @escaping (String) -> Void
	) {
		self.viewModel = viewModel
		self.onImportPet = onImportPet
		super.init(frame: .zero)
		setupViews()
		reloadEntries()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func setPetImportSuccess(petId: String) {
		setFeedback("Imported \(petId) to ~/.codogotchi/pets/.", color: .systemGreen)
	}

	func setPetImportError(_ message: String) {
		setFeedback(message, color: .systemRed)
	}

	/// Rebuild the grid from the current ViewModel state (after import).
	func refreshPetList(viewModel: PetTabViewModel) {
		self.viewModel = viewModel
		reloadEntries()
	}

	private func setupViews() {
		// Lighter wrapper card with an icon-badge header, matching the Hooks
		// card on General (and the Customization wrapper) so all tabs share one
		// design language.
		let wrapper = NSView()
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.wantsLayer = true
		wrapper.layer?.cornerRadius = 10
		wrapper.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
		wrapper.layer?.borderWidth = 1
		wrapper.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		addSubview(wrapper)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: "pawprint.fill", color: .systemPink)
		wrapper.addSubview(headerBadge)

		let title = settingsSectionTitle("Pet")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		wrapper.addSubview(title)

		let storeNote = settingsBodyLabel(
			"Installed pets live in ~/.codogotchi/pets/. "
				+ "Pets in ~/.codex/pets/ show an Import action."
		)
		wrapper.addSubview(storeNote)

		searchField.placeholderString = "Search pets…"
		searchField.delegate = self
		searchField.sendsWholeSearchString = false
		searchField.sendsSearchStringImmediately = true
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		wrapper.addSubview(searchField)

		openFolderButton.bezelStyle = .rounded
		openFolderButton.target = self
		openFolderButton.action = #selector(openPetFolder)
		openFolderButton.translatesAutoresizingMaskIntoConstraints = false
		openFolderButton.setContentHuggingPriority(.required, for: .horizontal)
		wrapper.addSubview(openFolderButton)

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
		wrapper.addSubview(gridScrollView)

		NSLayoutConstraint.activate([
			gridStack.widthAnchor.constraint(equalTo: gridScrollView.contentView.widthAnchor),
		])

		emptyLabel.font = .systemFont(ofSize: 12)
		emptyLabel.textColor = .secondaryLabelColor
		emptyLabel.alignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(emptyLabel)

		footerLabel.font = .systemFont(ofSize: 11)
		footerLabel.textColor = .tertiaryLabelColor
		footerLabel.alignment = .center
		footerLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(footerLabel)

		feedbackLabel.isEditable = false
		feedbackLabel.isBordered = false
		feedbackLabel.backgroundColor = .clear
		feedbackLabel.font = .systemFont(ofSize: 11)
		feedbackLabel.textColor = .secondaryLabelColor
		feedbackLabel.isHidden = true
		feedbackLabel.identifier = NSUserInterfaceItemIdentifier("petTabFeedback")
		feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(feedbackLabel)
		feedbackHeightConstraint = feedbackLabel.heightAnchor.constraint(equalToConstant: 0)
		feedbackHeightConstraint?.isActive = true

		NSLayoutConstraint.activate([
			wrapper.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			wrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			wrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			wrapper.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),

			title.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 18),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),

			searchField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			searchField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
			searchField.widthAnchor.constraint(equalToConstant: 200),

			openFolderButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openFolderButton.trailingAnchor.constraint(
				equalTo: searchField.leadingAnchor, constant: -8),
			openFolderButton.leadingAnchor.constraint(
				greaterThanOrEqualTo: title.trailingAnchor, constant: 16),

			storeNote.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
			storeNote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
			storeNote.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			feedbackLabel.topAnchor.constraint(equalTo: storeNote.bottomAnchor, constant: 8),
			feedbackLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			feedbackLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			gridScrollView.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 8),
			gridScrollView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			gridScrollView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),

			emptyLabel.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),

			footerLabel.topAnchor.constraint(equalTo: gridScrollView.bottomAnchor, constant: 8),
			footerLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			footerLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
			footerLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
		])
	}

	/// NSTabView sizes its selected item view by frame-setting, which does not
	/// reliably schedule a constraint layout pass on this view. Without this,
	/// the first (and only) `layout()` can run while the view is still zero-
	/// sized: the grid stays in its initial 1-column build and descriptions
	/// render single-line at full width.
	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsLayout = true
	}

	override func layout() {
		super.layout()
		// `super.layout()` positions only direct subviews; the scroll view is
		// nested inside the wrapper card, so on a one-shot pass its frame can
		// still be zero here. Resolve the wrapper's subtree before sampling the
		// width the column count depends on.
		gridScrollView.superview?.layoutSubtreeIfNeeded()
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
		cardViewsByPetId.removeAll(keepingCapacity: true)
		pillsRowsByPetId.removeAll(keepingCapacity: true)
		for view in gridStack.arrangedSubviews {
			gridStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		let entries = filteredEntries
		if entries.isEmpty {
			let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
			emptyLabel.stringValue =
				query.isEmpty ? "No pets available." : "No pets match \"\(query)\"."
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
			// All real cards in the row adopt the height of the tallest card.
			let realCount = slice.count
			if realCount > 1 {
				for i in 1..<realCount {
					rowViews[i].heightAnchor.constraint(equalTo: rowViews[0].heightAnchor).isActive =
						true
				}
			}
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
		card.layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		card.layer?.borderWidth = entry.isDefault ? 2 : 1
		card.layer?.borderColor =
			(entry.isDefault ? NSColor.controlAccentColor : SettingsTheme.cardBorder).cgColor
		card.identifier = PetTabView.cardIdentifier
		card.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true

		// Thumbnail — left column, raised to align with the pet name row.
		let thumb = NSImageView()
		thumb.translatesAutoresizingMaskIntoConstraints = false
		thumb.imageScaling = .scaleProportionallyUpOrDown
		thumb.image = thumbnail(for: entry)
		thumb.wantsLayer = true
		thumb.layer?.cornerRadius = 10
		thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
		thumb.layer?.masksToBounds = true
		card.addSubview(thumb)

		NSLayoutConstraint.activate([
			thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
			thumb.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
			thumb.widthAnchor.constraint(equalToConstant: thumbSize),
			thumb.heightAnchor.constraint(equalToConstant: thumbSize),
		])

		// Import icon — centered beneath thumbnail, only for importable pets.
		var leftBottomAnchor: NSLayoutYAxisAnchor = thumb.bottomAnchor
		var leftBottomConstant: CGFloat = 14
		if entry.state == .importable {
			let importBtn = makeImportIconButton(for: entry)
			card.addSubview(importBtn)
			NSLayoutConstraint.activate([
				importBtn.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 6),
				importBtn.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
			])
			leftBottomAnchor = importBtn.bottomAnchor
			leftBottomConstant = 12
		}

		// Name label — truncates tail when the name is long.
		let nameLabel = NSTextField(labelWithString: entry.displayName)
		nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		// Assign icon — right-aligned in the name row, only for installed pets.
		let nameRowViews: [NSView]
		if entry.state == .installed {
			let assignBtn = makeAssignButton(for: entry)
			nameRowViews = [nameLabel, assignBtn]
		} else {
			nameRowViews = [nameLabel]
		}

		let nameRow = NSStackView(views: nameRowViews)
		nameRow.orientation = .horizontal
		nameRow.spacing = 6
		nameRow.alignment = .top
		nameRow.distribution = .fill
		nameRow.translatesAutoresizingMaskIntoConstraints = false
		// Cards with no assignBtn have a shorter intrinsic nameRow (~17pt vs 20pt).
		// A minimum height normalises the gap so descLabel always starts at the same Y.
		nameRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

		// Description — full-width in the right column, wraps up to 5 lines.
		let descLabel = NSTextField(wrappingLabelWithString: entry.description)
		descLabel.isSelectable = false
		descLabel.font = .systemFont(ofSize: 12)
		descLabel.textColor = .secondaryLabelColor
		descLabel.maximumNumberOfLines = 5
		descLabel.lineBreakMode = .byWordWrapping
		descLabel.cell?.truncatesLastVisibleLine = true
		descLabel.identifier = PetTabView.descriptionIdentifier
		descLabel.translatesAutoresizingMaskIntoConstraints = false
		descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		// Prevent the label from stretching below its intrinsic height.
		// When equal-height constraints force a shorter card to match a taller sibling,
		// the preferRight anchor (card.bottom = descLabel.bottom + 14, .defaultHigh)
		// would otherwise pull descLabel's bottom down to fill the extra space.
		descLabel.setContentHuggingPriority(.required, for: .vertical)

		card.addSubview(nameRow)
		card.addSubview(descLabel)

		NSLayoutConstraint.activate([
			nameRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
			nameRow.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 14),
			nameRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

			descLabel.topAnchor.constraint(equalTo: nameRow.bottomAnchor, constant: 4),
			descLabel.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor),
			descLabel.trailingAnchor.constraint(equalTo: nameRow.trailingAnchor),
		])

		// Badge pills — always present (zero-height "invisible pill" when this pet holds no
		// badges) so every card's right column ends on the same anchor. The top gap is a
		// `>=` minimum, not a fixed offset: when the equal-height row constraint forces a
		// shorter card taller, the slack must open up here (between description and pills)
		// rather than stretching descLabel or leaving pills floating high above the bottom.
		let entryBadges = viewModel.badges(for: entry.id)
		let pillsRow = makeBadgePillsRow(badges: entryBadges)
		pillsRow.identifier = PetTabView.badgePillsIdentifier
		card.addSubview(pillsRow)
		NSLayoutConstraint.activate([
			pillsRow.topAnchor.constraint(greaterThanOrEqualTo: descLabel.bottomAnchor, constant: 6),
			pillsRow.leadingAnchor.constraint(equalTo: descLabel.leadingAnchor),
			pillsRow.trailingAnchor.constraint(
				lessThanOrEqualTo: card.trailingAnchor, constant: -16),
		])
		let rightBottomAnchor: NSLayoutYAxisAnchor = pillsRow.bottomAnchor
		let rightBottomConstant: CGFloat = 14

		// Card bottom is driven by the taller of the two columns.
		// The `.defaultHigh` equality tracks the right column exactly; the
		// required `>=` from the left column overrides upward when taller.
		let leftBottom = card.bottomAnchor.constraint(
			greaterThanOrEqualTo: leftBottomAnchor, constant: leftBottomConstant)
		let rightBottom = card.bottomAnchor.constraint(
			greaterThanOrEqualTo: rightBottomAnchor, constant: rightBottomConstant)
		let preferRight = card.bottomAnchor.constraint(
			equalTo: rightBottomAnchor, constant: rightBottomConstant)
		preferRight.priority = .defaultHigh
		NSLayoutConstraint.activate([leftBottom, rightBottom, preferRight])

		cardViewsByPetId[entry.id] = card
		pillsRowsByPetId[entry.id] = pillsRow
		return card
	}

	// MARK: - Card sub-views

	/// Small icon button in the pet name row. Tapping opens the badge dropdown.
	private func makeAssignButton(for entry: PetCatalogEntry) -> NSButton {
		let btn = NSButton()
		btn.isBordered = false
		btn.imagePosition = .imageOnly
		btn.imageScaling = .scaleProportionallyUpOrDown
		btn.image = NSImage(
			systemSymbolName: "person.badge.plus",
			accessibilityDescription: "Assign platform badge")
		btn.contentTintColor = .secondaryLabelColor
		btn.toolTip = "Assign Pet to a Platform"
		btn.translatesAutoresizingMaskIntoConstraints = false
		btn.setContentHuggingPriority(.required, for: .horizontal)
		NSLayoutConstraint.activate([
			btn.widthAnchor.constraint(equalToConstant: 20),
			btn.heightAnchor.constraint(equalToConstant: 20),
		])
		btn.target = self
		btn.action = #selector(assignButtonTapped(_:))
		objc_setAssociatedObject(btn, &assignBtnKey, entry.id, .OBJC_ASSOCIATION_RETAIN)
		return btn
	}

	/// Small icon button centered beneath the thumbnail for importable pets.
	private func makeImportIconButton(for entry: PetCatalogEntry) -> NSButton {
		let btn = NSButton()
		btn.isBordered = false
		btn.imagePosition = .imageOnly
		btn.imageScaling = .scaleProportionallyUpOrDown
		btn.image = NSImage(
			systemSymbolName: "square.and.arrow.down",
			accessibilityDescription: "Import pet")
		btn.contentTintColor = .secondaryLabelColor
		btn.toolTip = "Import Codex Pet"
		btn.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			btn.widthAnchor.constraint(equalToConstant: 20),
			btn.heightAnchor.constraint(equalToConstant: 20),
		])
		btn.target = self
		btn.action = #selector(importIconTapped(_:))
		objc_setAssociatedObject(btn, &importBtnKey, entry.id, .OBJC_ASSOCIATION_RETAIN)
		return btn
	}

	/// Horizontal row of compact icon-only badge pills for all badges held by this pet.
	private func makeBadgePillsRow(badges: Set<String>) -> NSStackView {
		let sorted = ASSIGNMENT_BADGE_KEYS.filter { badges.contains($0) }
		let pills = sorted.map { key -> NSView in makePlatformIconPill(key: key) }
		let row = NSStackView(views: pills)
		row.orientation = .horizontal
		row.spacing = 4
		row.alignment = .centerY
		row.translatesAutoresizingMaskIntoConstraints = false
		return row
	}

	/// Replace arranged pill views to match the current assignment set without
	/// rebuilding the whole card (keeps the assign-popover anchor intact).
	private func replaceBadgePills(in row: NSStackView, badges: Set<String>) {
		for view in row.arrangedSubviews {
			row.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		let sorted = ASSIGNMENT_BADGE_KEYS.filter { badges.contains($0) }
		for key in sorted {
			row.addArrangedSubview(makePlatformIconPill(key: key))
		}
	}

	/// Update logo pills + Default selection border from the live assignment map
	/// while an assign popover may still be open.
	func refreshAssignmentChrome() {
		for (petId, pillsRow) in pillsRowsByPetId {
			replaceBadgePills(in: pillsRow, badges: viewModel.badges(for: petId))
		}
		for (petId, card) in cardViewsByPetId {
			let isDefault = viewModel.badges(for: petId).contains("default")
			card.layer?.borderWidth = isDefault ? 2 : 1
			card.layer?.borderColor =
				(isDefault ? NSColor.controlAccentColor : SettingsTheme.cardBorder).cgColor
		}
		sizeDocumentToFit()
	}

	private func makePlatformIconPill(key: String) -> NSView {
		let tint = platformIconTint(forBadgeKey: key)
		let container = NSView()
		container.wantsLayer = true
		container.layer?.cornerRadius = 5
		container.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
		container.translatesAutoresizingMaskIntoConstraints = false

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attr = platformAttribution(forBadgeKey: key) {
			iconView.image = NSImage(named: attr.assetName)
		}
		iconView.contentTintColor = tint

		container.addSubview(iconView)
		NSLayoutConstraint.activate([
			iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 12),
			iconView.heightAnchor.constraint(equalToConstant: 12),
			container.widthAnchor.constraint(equalToConstant: 22),
			container.heightAnchor.constraint(equalToConstant: 18),
		])
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

	/// Opens a persistent badge popover for `sender`'s associated pet.
	/// The popover stays open while the user toggles platforms and dismisses on outside click.
	@objc private func assignButtonTapped(_ sender: NSButton) {
		guard let petId = objc_getAssociatedObject(sender, &assignBtnKey) as? String else { return }
		activeAssignPopover?.close()
		activeAssignPopover = nil

		let vc = PetAssignPopoverController(petId: petId, viewModel: viewModel)
		vc.onAssignmentToggled = { [weak self] in
			self?.refreshAssignmentChrome()
		}
		let popover = NSPopover()
		popover.contentViewController = vc
		popover.behavior = .transient
		popover.delegate = self
		popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
		activeAssignPopover = popover
	}

	private func setAssignmentPersistenceError() {
		setFeedback(
			"Couldn’t save assignment. Check Codogotchi folder permissions.",
			color: .systemRed)
	}

	private func setFeedback(_ message: String, color: NSColor) {
		feedbackLabel.stringValue = message
		feedbackLabel.textColor = color
		feedbackLabel.isHidden = false
		feedbackHeightConstraint?.isActive = false
	}

	private func clearFeedback() {
		feedbackLabel.stringValue = ""
		feedbackLabel.isHidden = true
		feedbackHeightConstraint?.isActive = true
	}

	/// Import icon tapped for an importable pet.
	@objc private func importIconTapped(_ sender: NSButton) {
		guard let petId = objc_getAssociatedObject(sender, &importBtnKey) as? String else { return }
		onImportPet(petId)
	}
}

extension PetTabView: NSPopoverDelegate {
	func popoverDidClose(_ notification: Notification) {
		// Rebuild the grid so badge pills reflect any toggles made in the popover.
		reloadEntries()
		activeAssignPopover = nil
	}
}

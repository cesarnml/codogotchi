import AppKit

final class SessionTierSectionView: NSView {
	init(
		title: String,
		iconSymbol: String,
		tint: NSColor,
		rows: [SessionRow],
		emptyText: String,
		bulkActions: [(title: String, action: () -> Void)],
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setup(
			title: title, iconSymbol: iconSymbol, tint: tint, rows: rows, emptyText: emptyText,
			bulkActions: bulkActions, onShow: onShow, onHide: onHide, onPrune: onPrune)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setup(
		title: String,
		iconSymbol: String,
		tint: NSColor,
		rows: [SessionRow],
		emptyText: String,
		bulkActions: [(title: String, action: () -> Void)],
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.backgroundColor = SettingsTheme.tableBackground.cgColor
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor

		let badge = settingsHeaderIconBadge(symbolName: iconSymbol, color: tint, side: 24)
		addSubview(badge)

		let titleLabel = settingsSectionTitle("\(title) (\(rows.count))")
		addSubview(titleLabel)

		// A section may offer more than one bulk action (e.g. Live's "Show
		// All Live" + "Prune All Live"), laid out as a trailing horizontal
		// row of buttons rather than the single trailing button earlier
		// sections (Archived) used alone.
		var bulkActionsStack: NSStackView?
		if !bulkActions.isEmpty {
			let buttons = bulkActions.map { entry in
				ActionButton(title: entry.title, tint: tint, action: entry.action)
			}
			let stack = NSStackView(views: buttons)
			stack.orientation = .horizontal
			stack.spacing = 8
			stack.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stack)
			bulkActionsStack = stack
		}

		let rowsStack = NSStackView()
		rowsStack.orientation = .vertical
		rowsStack.spacing = 0
		rowsStack.alignment = .leading
		rowsStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(rowsStack)

		if rows.isEmpty {
			let empty = settingsBodyLabel(emptyText)
			rowsStack.addArrangedSubview(empty)
			empty.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
		} else {
			for (index, row) in rows.enumerated() {
				let rowView = SessionRowView(
					row: row, showsDivider: index < rows.count - 1,
					onShow: onShow, onHide: onHide, onPrune: onPrune)
				rowsStack.addArrangedSubview(rowView)
				rowView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
			}
		}

		NSLayoutConstraint.activate([
			badge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
			badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

			titleLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
			titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),

			rowsStack.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 10),
			rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
			rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
		])

		if let bulkActionsStack {
			NSLayoutConstraint.activate([
				bulkActionsStack.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
				bulkActionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
				titleLabel.trailingAnchor.constraint(
					lessThanOrEqualTo: bulkActionsStack.leadingAnchor, constant: -12),
			])
		}
	}
}

/// One session row: platform icon, display label, a relative-age caption, and
/// up to two trailing action buttons (Show/Hide, and Prune for Live/Archived
/// rows).

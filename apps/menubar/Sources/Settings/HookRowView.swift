import AppKit

// MARK: - HookRowView

/// One row in the Hooks table: platform icon + name, a colored status pill,
/// and a short descriptor. Replaces the old single monospaced status-line
/// blob with a per-row rendering of `PlatformRow.statusPresentation` — no new
/// data, just a richer display of the same fields.
final class HookRowView: NSView {
	init(row: GeneralTabViewModel.PlatformRow, showsDivider: Bool) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setupViews(row: row, showsDivider: showsDivider)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews(row: GeneralTabViewModel.PlatformRow, showsDivider: Bool) {
		let presentation = row.statusPresentation

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attribution = platformAttribution(forBadgeKey: row.originKey) {
			iconView.image = NSImage(named: attribution.assetName)
		}
		iconView.contentTintColor = platformIconTint(forBadgeKey: row.originKey)

		let nameLabel = NSTextField(labelWithString: row.name)
		nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
		nameLabel.translatesAutoresizingMaskIntoConstraints = false

		let pill = makeStatusPill(presentation)

		let descriptorLabel = NSTextField(labelWithString: presentation.descriptor)
		descriptorLabel.font = .systemFont(ofSize: 11)
		descriptorLabel.textColor = .secondaryLabelColor
		descriptorLabel.lineBreakMode = .byTruncatingTail
		descriptorLabel.translatesAutoresizingMaskIntoConstraints = false

		addSubview(iconView)
		addSubview(nameLabel)
		addSubview(pill)
		addSubview(descriptorLabel)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 40),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 26),
			iconView.heightAnchor.constraint(equalToConstant: 26),

			nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
			nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			nameLabel.widthAnchor.constraint(equalToConstant: 130),

			pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 330),
			pill.centerYAnchor.constraint(equalTo: centerYAnchor),

			// Column 3 sits at a fixed offset from the row's leading edge — not
			// `pill.trailingAnchor` — so it lines up across rows regardless of how
			// wide any one row's pill text ("Update available" vs "Installed") is.
			descriptorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 640),
			descriptorLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: trailingAnchor, constant: -14),
			descriptorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
		])

		if showsDivider {
			let divider = NSView()
			divider.translatesAutoresizingMaskIntoConstraints = false
			divider.wantsLayer = true
			divider.layer?.backgroundColor = SettingsTheme.rowDivider.cgColor
			addSubview(divider)
			NSLayoutConstraint.activate([
				divider.leadingAnchor.constraint(equalTo: leadingAnchor),
				divider.trailingAnchor.constraint(equalTo: trailingAnchor),
				divider.bottomAnchor.constraint(equalTo: bottomAnchor),
				divider.heightAnchor.constraint(equalToConstant: 1),
			])
		}
	}

	private func makeStatusPill(
		_ presentation: GeneralTabViewModel.PlatformRow.StatusPresentation
	) -> NSView {
		let tint: NSColor
		switch presentation.pill {
		case .installed: tint = .systemGreen
		case .updateAvailable: tint = .systemYellow
		case .detectedNotInstalled: tint = .secondaryLabelColor
		case .notInstalled, .notSupported: tint = .tertiaryLabelColor
		}

		let container = NSView()
		container.wantsLayer = true
		container.layer?.cornerRadius = 5
		container.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
		container.translatesAutoresizingMaskIntoConstraints = false

		let label = NSTextField(labelWithString: presentation.pillTitle)
		label.font = .systemFont(ofSize: 11, weight: .semibold)
		label.textColor = tint
		label.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(label)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
			label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
			label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
			label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
		])
		return container
	}
}

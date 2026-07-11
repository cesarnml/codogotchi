import AppKit

final class HUDElementRowView: NSView {
	init(icon: NSView, title: String, subtitle: String, value: String? = nil, valueView: NSView? = nil, footer: NSView? = nil) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor
		layer?.backgroundColor = SettingsTheme.windowBackground.withAlphaComponent(0.45).cgColor

		let titleLabel = settingsSectionTitle(title)
		titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		let subtitleLabel = settingsBodyLabel(subtitle)
		let valueLabel = value.map { text -> NSTextField in
			let label = settingsSectionTitle(text)
			label.font = .systemFont(ofSize: 15, weight: .bold)
			label.alignment = .right
			return label
		}

		for view in [icon, titleLabel, subtitleLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		if let valueLabel {
			addSubview(valueLabel)
		}
		if let valueView {
			valueView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(valueView)
		}
		if let footer {
			footer.translatesAutoresizingMaskIntoConstraints = false
			addSubview(footer)
		}

		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14),
			icon.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),

			titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
			titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

			subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
		])

		if let valueLabel {
			NSLayoutConstraint.activate([
				valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
				valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -16),
			])
		}
		if let valueView {
			NSLayoutConstraint.activate([
				valueView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
				valueView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueView.leadingAnchor, constant: -16),
			])
		}
		if let footer {
			NSLayoutConstraint.activate([
				footer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
				footer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
				footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
				footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
			])
		} else {
			// Minimum only (not equality): an external equal-height constraint
			// (Hearts/Level pinned to XP Ring's taller height, in
			// makeHudElementsPanel) stretches this row past its intrinsic
			// content height, and a required equality here would conflict with
			// that at required priority.
			bottomAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.bottomAnchor, constant: 14)
				.isActive = true
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}


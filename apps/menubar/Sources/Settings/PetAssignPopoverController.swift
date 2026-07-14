import AppKit

// MARK: - Assign popover

/// A persistent popover listing all assignable platforms for one pet.
/// Rows toggle without closing the popover; clicking outside dismisses it.
final class PetAssignPopoverController: NSViewController {
	private let petId: String
	private let viewModel: PetTabViewModel
	private var rowViews: [String: BadgeRowView] = [:]

	init(petId: String, viewModel: PetTabViewModel) {
		self.petId = petId
		self.viewModel = viewModel
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	override func loadView() {
		let stack = NSStackView()
		stack.orientation = .vertical
		stack.spacing = 1
		stack.translatesAutoresizingMaskIntoConstraints = false

		for key in ASSIGNMENT_BADGE_KEYS {
			let row = makePlatformRow(for: key)
			rowViews[key] = row
			stack.addArrangedSubview(row)
		}

		let wrapper = NSView()
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
			stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
			stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
			wrapper.widthAnchor.constraint(equalToConstant: 200),
		])
		view = wrapper
	}

	private func makePlatformRow(for key: String) -> BadgeRowView {
		let badges = viewModel.badges(for: petId)
		let isChecked = badges.contains(key)
		let isDefaultHeld = key == "default" && isChecked
		let row = BadgeRowView(isDisabled: isDefaultHeld)
		row.translatesAutoresizingMaskIntoConstraints = false
		row.heightAnchor.constraint(equalToConstant: 32).isActive = true

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attr = platformAttribution(forBadgeKey: key) {
			iconView.image = NSImage(named: attr.assetName)
		}
		iconView.contentTintColor = platformIconTint(forBadgeKey: key)

		let label = NSTextField(labelWithString: badgeDisplayName(key))
		label.font = .systemFont(ofSize: 13)
		label.translatesAutoresizingMaskIntoConstraints = false

		let check = NSImageView()
		check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
		check.contentTintColor = .controlAccentColor
		check.isHidden = !isChecked
		check.translatesAutoresizingMaskIntoConstraints = false
		row.checkmark = check

		row.addSubview(iconView)
		row.addSubview(label)
		row.addSubview(check)

		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
			iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 16),
			iconView.heightAnchor.constraint(equalToConstant: 16),
			label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
			label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -4),
			check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
			check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			check.widthAnchor.constraint(equalToConstant: 12),
			check.heightAnchor.constraint(equalToConstant: 12),
		])

		row.onTap = { [weak self] in self?.toggleBadge(key) }
		return row
	}

	private func toggleBadge(_ key: String) {
		let isChecked = viewModel.badges(for: petId).contains(key)
		if isChecked {
			_ = viewModel.unassign(badge: key, from: petId)
		} else {
			try? viewModel.assign(badge: key, to: petId)
		}
		// Refresh all rows — e.g. assigning Default moves it off the previous holder.
		let updated = viewModel.badges(for: petId)
		for (k, row) in rowViews {
			let nowChecked = updated.contains(k)
			row.update(isChecked: nowChecked, isDisabled: k == "default" && nowChecked)
		}
	}
}

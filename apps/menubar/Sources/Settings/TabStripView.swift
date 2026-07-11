import AppKit

// MARK: - TabStripView

/// Custom icon + label tab strip replacing native `NSTabViewItem` tabs, which
/// only render plain labels in `.topTabsBezelBorder` style (`.image` is a
/// segmented/toolbar-tab-only behavior). Drives `NSTabView` selection via
/// `onSelect`; the owning controller keeps `setSelected` in sync with
/// programmatic and delegate-driven selection changes.
final class TabStripView: NSView {
	private var buttons: [SettingsTab: NSButton] = [:]
	private var pills: [SettingsTab: NSView] = [:]
	var onSelect: ((SettingsTab) -> Void)?

	init(tabs: [SettingsTab]) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false

		let stack = NSStackView()
		stack.orientation = .horizontal
		stack.spacing = 4
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		for tab in tabs {
			let button = NSButton(
				title: tab.title, target: self, action: #selector(tabTapped(_:)))
			button.tag = tab.rawValue
			button.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
			button.imagePosition = .imageLeading
			button.isBordered = false
			button.font = .systemFont(ofSize: 13, weight: .medium)

			// The pill background lives on a wrapper view, not the button itself,
			// so horizontal padding is real layout (leading/trailing constraints)
			// rather than literal spaces baked into the title string.
			let pill = NSView()
			pill.translatesAutoresizingMaskIntoConstraints = false
			pill.wantsLayer = true
			pill.layer?.cornerRadius = 6
			button.translatesAutoresizingMaskIntoConstraints = false
			pill.addSubview(button)
			NSLayoutConstraint.activate([
				pill.heightAnchor.constraint(equalToConstant: 32),
				button.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
				button.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
				button.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
				button.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
			])
			stack.addArrangedSubview(pill)
			buttons[tab] = button
			pills[tab] = pill
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	@objc private func tabTapped(_ sender: NSButton) {
		guard let tab = SettingsTab(rawValue: sender.tag) else { return }
		onSelect?(tab)
		setSelected(tab)
	}

	func setSelected(_ tab: SettingsTab) {
		for (t, pill) in pills {
			let isSelected = t == tab
			pill.layer?.backgroundColor =
				isSelected ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
			buttons[t]?.contentTintColor = isSelected ? .white : .secondaryLabelColor
		}
	}
}

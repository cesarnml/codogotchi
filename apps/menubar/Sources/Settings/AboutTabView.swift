import AppKit

// MARK: - AboutTabView

/// About tab — app version, bundled hook-binary version, and product links.
final class AboutTabView: NSView {
	private let viewModel: AboutViewModel

	init(viewModel: AboutViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.about.symbolName, color: .systemBlue)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("About")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		let appVersionLabel = settingsBodyLabel("Codogotchi \(viewModel.appVersion)")
		card.addSubview(appVersionLabel)

		let hookVersionLabel = settingsBodyLabel("Bundled hook binary: \(viewModel.hookVersion)")
		card.addSubview(hookVersionLabel)

		let links = NSStackView(views: [
			linkButton(title: "Website", urlString: "https://codogotchi.app"),
			linkButton(title: "GitHub", urlString: "https://github.com/cesarnml/codogotchi"),
			linkButton(
				title: "Documentation",
				urlString: "https://github.com/cesarnml/codogotchi#readme"
			),
			linkButton(title: "Dev Guide", urlString: "https://codogotchifordummies.vercel.app/"),
		])
		links.orientation = .horizontal
		links.spacing = 12
		links.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(links)

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.centerYAnchor.constraint(equalTo: headerBadge.centerYAnchor),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),
			title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			appVersionLabel.topAnchor.constraint(equalTo: headerBadge.bottomAnchor, constant: 12),
			appVersionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			appVersionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			hookVersionLabel.topAnchor.constraint(equalTo: appVersionLabel.bottomAnchor, constant: 6),
			hookVersionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			hookVersionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			links.topAnchor.constraint(equalTo: hookVersionLabel.bottomAnchor, constant: 16),
			links.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			links.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	private func linkButton(title: String, urlString: String) -> NSButton {
		let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
		button.bezelStyle = .inline
		button.isBordered = false
		button.contentTintColor = .linkColor
		button.toolTip = urlString
		button.identifier = NSUserInterfaceItemIdentifier(urlString)
		return button
	}

	@objc private func openLink(_ sender: NSButton) {
		guard
			let urlString = sender.identifier?.rawValue,
			let url = URL(string: urlString)
		else { return }
		NSWorkspace.shared.open(url)
	}
}

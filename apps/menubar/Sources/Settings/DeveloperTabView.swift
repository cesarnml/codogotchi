import AppKit

// MARK: - DeveloperTabView

/// Developer tab — read-only observability. Shows state.json, gate.json,
/// last 5 transitions, schema version, hooks summary, and platform attribution note.
final class DeveloperTabView: NSView {
	private var viewModel: DeveloperTabViewModel
	private let scrollView = NSScrollView()
	private let textView = NSTextView()
	private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
	private let openDataButton = NSButton(title: "Open data folder", target: nil, action: nil)

	init(viewModel: DeveloperTabViewModel) {
		self.viewModel = viewModel
		super.init(frame: .zero)
		setupViews()
		renderContent()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		let card = settingsThemedCard()
		addSubview(card)

		let headerBadge = settingsHeaderIconBadge(
			symbolName: SettingsTab.developer.symbolName, color: .systemOrange)
		card.addSubview(headerBadge)

		let title = settingsSectionTitle("Developer")
		title.font = .systemFont(ofSize: 15, weight: .semibold)
		card.addSubview(title)

		refreshButton.bezelStyle = .rounded
		refreshButton.target = self
		refreshButton.action = #selector(refresh)
		refreshButton.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(refreshButton)

		openDataButton.bezelStyle = .rounded
		openDataButton.target = self
		openDataButton.action = #selector(openDataFolder)
		openDataButton.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(openDataButton)

		textView.isEditable = false
		textView.isSelectable = true
		textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
		textView.backgroundColor = SettingsTheme.tableBackground
		textView.textContainerInset = NSSize(width: 8, height: 8)
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		scrollView.borderType = .noBorder
		scrollView.wantsLayer = true
		scrollView.layer?.cornerRadius = 8
		scrollView.layer?.borderWidth = 1
		scrollView.layer?.borderColor = SettingsTheme.cardBorder.cgColor
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(scrollView)

		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

			headerBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
			headerBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),

			title.centerYAnchor.constraint(equalTo: headerBadge.centerYAnchor),
			title.leadingAnchor.constraint(equalTo: headerBadge.trailingAnchor, constant: 12),

			refreshButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			refreshButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

			openDataButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
			openDataButton.trailingAnchor.constraint(
				equalTo: refreshButton.leadingAnchor, constant: -8),

			scrollView.topAnchor.constraint(equalTo: headerBadge.bottomAnchor, constant: 10),
			scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
		])
	}

	private func renderContent() {
		var lines: [String] = []

		// Schema version
		let sv = viewModel.stateSchemaVersion
		let rv = viewModel.rendererSchemaVersion
		let mismatch = viewModel.schemaVersionMismatch
		lines.append("=== Schema ===")
		lines.append("state.d/ (latest): v\(sv == 0 ? "?" : "\(sv)")   renderer: v\(rv)")
		if mismatch {
			lines.append("⚠️ VERSION MISMATCH — schema v\(sv) is not v\(rv). Update the app or reinstall the hook.")
		}
		lines.append("")

		// Hooks summary
		if let summary = viewModel.hooksPresentSummary {
			lines.append("=== Hooks ===")
			lines.append(summary)
			lines.append("")
		}

		// Last 5 transitions
		lines.append("=== Last 5 Transitions ===")
		let transitions = viewModel.last5Transitions
		if transitions.isEmpty {
			lines.append("(no transitions recorded)")
		} else {
			for t in transitions {
				var parts = [t.ts, "→ \(t.state)"]
				if let p = t.prev { parts.append("(was: \(p))") }
				if let o = t.sourceOrigin { parts.append("via: \(o)") }
				if let k = t.sourceKind { parts.append("[\(k)]") }
				if let n = t.sourceName { parts.append(n) }
				lines.append(parts.joined(separator: "  "))
			}
		}
		lines.append("")

		// Which platform last drove the pet.
		if let origin = viewModel.lastSeenSourceOrigin {
			lines.append("=== Platform attribution ===")
			let name = viewModel.lastSeenSourceName ?? "(unknown tool)"
			if origin == "cursor" {
				lines.append("Last seen from Cursor (\(name)).")
			} else if origin == "claude_code" {
				lines.append("Last seen from Claude Code (\(name)).")
			} else {
				lines.append("Last seen from \(origin) (\(name)).")
			}
			lines.append("")
		}

		// latest slice from state.d/
		lines.append("=== state.d/ (latest slice) ===")
		lines.append(viewModel.stateJsonPretty)
		lines.append("")

		// gate.json (per-origin state.d/ slice when present, else the legacy flat file)
		if let gatePretty = viewModel.gateJsonPretty {
			lines.append("=== \(viewModel.gateJsonSourceLabel) (latest) ===")
			lines.append(gatePretty)
			lines.append("")
		}

		// delivery-context.json (per-origin state.d/ slice when present, else the legacy flat file)
		if let deliveryContextPretty = viewModel.deliveryContextPretty {
			lines.append("=== \(viewModel.deliveryContextSourceLabel) (latest) ===")
			lines.append(deliveryContextPretty)
		}

		textView.string = lines.joined(separator: "\n")
	}

	@objc private func refresh() {
		renderContent()
	}

	@objc private func openDataFolder() {
		CodogotchiFolders.reveal(CodogotchiFolders.dataFolderURL())
	}
}


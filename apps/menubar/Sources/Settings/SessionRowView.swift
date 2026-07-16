import AppKit

final class SessionRowView: NSView {
	init(
		row: SessionRow, showsDivider: Bool,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setup(row: row, showsDivider: showsDivider, onShow: onShow, onHide: onHide, onPrune: onPrune)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setup(
		row: SessionRow, showsDivider: Bool,
		onShow: ((SessionRow) -> Void)?,
		onHide: ((SessionRow) -> Void)?,
		onPrune: ((SessionRow) -> Void)?
	) {
		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		if let attribution = platformAttribution(forBadgeKey: row.origin) {
			iconView.image = NSImage(named: attribution.assetName)
		} else {
			iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
		}
		iconView.contentTintColor = Self.iconTint(forOrigin: row.origin)
		addSubview(iconView)

		let label = NSTextField(labelWithString: row.displayLabel)
		label.font = .systemFont(ofSize: 12, weight: .medium)
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)

		let statusLabel = NSTextField(labelWithString: Self.subtitleText(for: row))
		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(statusLabel)

		var trailingButtons: [NSButton] = []
		if row.tier == .active {
			// Gated on `sessionId` (session-keyed window), mirroring the
			// right-click affordance's `hasActiveSessionBadge` gate: a
			// plain-origin/combined row has no session to prune.
			if row.sessionId != nil, let onPrune {
				trailingButtons.append(ActionButton(title: "Prune", tint: .systemRed) { onPrune(row) })
			}
			if row.isShown {
				if let onHide {
					trailingButtons.append(
						ActionButton(title: "Hide", tint: .secondaryLabelColor) { onHide(row) })
				}
			} else if row.canShow, let onShow {
				trailingButtons.append(ActionButton(title: "Show", tint: .systemBlue) { onShow(row) })
			}
		} else {
			if row.canShow, let onShow {
				trailingButtons.append(ActionButton(title: "Show", tint: .systemBlue) { onShow(row) })
			}
			if let onPrune {
				trailingButtons.append(ActionButton(title: "Prune", tint: .systemRed) { onPrune(row) })
			}
		}

		let buttonStack = NSStackView(views: trailingButtons)
		buttonStack.orientation = .horizontal
		buttonStack.spacing = 6
		buttonStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(buttonStack)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 36),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 20),
			iconView.heightAnchor.constraint(equalToConstant: 20),

			label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
			label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),

			statusLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
			statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),

			buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
			buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			buttonStack.leadingAnchor.constraint(
				greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
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

	private static func iconTint(forOrigin origin: String) -> NSColor {
		switch origin {
		case "claude_code": return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
		case "codex": return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)
		case "vscode": return NSColor(srgbRed: 0.00, green: 0.48, blue: 0.80, alpha: 1)
		case "cursor": return NSColor(calibratedWhite: 0.78, alpha: 1)
		case "antigravity": return NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1)
		default: return .labelColor
		}
	}

	private static func relativeAge(_ seconds: TimeInterval) -> String {
		let minutes = Int(seconds / 60)
		if minutes < 1 { return "just now" }
		if minutes < 60 { return "\(minutes)m ago" }
		let hours = Int(seconds / 3600)
		if hours < 24 { return "\(hours)h ago" }
		let days = Int(seconds / 86400)
		return "\(days)d ago"
	}

	/// Builds a row's status line: the tier's existing base text (`Shown`/
	/// `Hidden` for Active, `Idle <age>` for Live, `Quiet <age>` for Archived)
	/// plus a `Started <age>` fragment appended when `row.sessionStartedAt`
	/// is present and parses — combined onto the same line rather than a
	/// second row (P20.03). Omits the Started fragment entirely, leaving the
	/// base text unchanged, when the stamp is missing or unparseable: never
	/// fabricated from `updated_at`.
	static func subtitleText(for row: SessionRow, now: Date = Date()) -> String {
		let base: String
		switch row.tier {
		case .active: base = row.isShown ? "Shown" : "Hidden"
		case .live: base = "Idle \(relativeAge(row.ageSeconds))"
		case .archived: base = "Quiet \(relativeAge(row.ageSeconds))"
		}
		guard let sessionStartedAt = row.sessionStartedAt,
			let startedDate = StateJsonReader.parseISO8601Date(sessionStartedAt)
		else { return base }
		return "\(base) · Started \(relativeAge(now.timeIntervalSince(startedDate)))"
	}
}

/// Small pill-style text button shared by bulk and per-row session actions —
/// the same borderless-with-tint treatment as the Hooks card's action row,
/// scaled down for inline row use.

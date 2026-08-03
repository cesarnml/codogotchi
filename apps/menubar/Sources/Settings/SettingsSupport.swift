import AppKit

// MARK: - Shared helpers

func settingsSectionTitle(_ text: String) -> NSTextField {
	let label = NSTextField(labelWithString: text)
	label.font = .systemFont(ofSize: 13, weight: .semibold)
	label.textColor = .labelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	return label
}

func settingsBodyLabel(_ text: String) -> NSTextField {
	let label = NSTextField(wrappingLabelWithString: text)
	// `wrappingLabelWithString:` returns a *selectable* field: without this the
	// caption shows an I-beam cursor and click-drag highlights it like a document.
	label.isSelectable = false
	label.isEditable = false
	label.isBordered = false
	label.backgroundColor = .clear
	label.font = .systemFont(ofSize: 12)
	label.textColor = .secondaryLabelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	return label
}

/// Rounded square icon badge used in section headers (the Hooks card treatment,
/// reused by every tab's wrapper card and inner panels to unify the design
/// language). `side` 32 for tab-level headers, 24 for inner panel titles.
func settingsHeaderIconBadge(
	symbolName: String, color: NSColor, side: CGFloat = 32
) -> NSView {
	let badge = NSView()
	badge.translatesAutoresizingMaskIntoConstraints = false
	badge.wantsLayer = true
	badge.layer?.cornerRadius = side / 4
	badge.layer?.backgroundColor = color.cgColor

	let glyph = NSImageView()
	glyph.translatesAutoresizingMaskIntoConstraints = false
	glyph.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
	glyph.contentTintColor = .white
	glyph.imageScaling = .scaleProportionallyUpOrDown
	badge.addSubview(glyph)

	NSLayoutConstraint.activate([
		badge.widthAnchor.constraint(equalToConstant: side),
		badge.heightAnchor.constraint(equalToConstant: side),
		glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
		glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
		glyph.widthAnchor.constraint(equalToConstant: side / 2),
		glyph.heightAnchor.constraint(equalToConstant: side / 2),
	])
	return badge
}

/// Themed card container matching the General tab's Hooks card, so every
/// tab's content sits in the same navy panel treatment.
func settingsThemedCard() -> NSView {
	let card = NSView()
	card.translatesAutoresizingMaskIntoConstraints = false
	card.wantsLayer = true
	card.layer?.cornerRadius = 10
	card.layer?.backgroundColor = SettingsTheme.cardBackground.cgColor
	card.layer?.borderWidth = 1
	card.layer?.borderColor = SettingsTheme.cardBorder.cgColor
	return card
}

/// Small caps-style column header, used above per-platform table rows
/// (Platform Settings card).
func settingsColumnHeader(_ text: String) -> NSTextField {
	let label = NSTextField(labelWithString: text)
	label.font = .systemFont(ofSize: 11, weight: .semibold)
	label.textColor = .secondaryLabelColor
	label.translatesAutoresizingMaskIntoConstraints = false
	// Callers that pass an embedded "\n" (e.g. a two-line "Enable\nSessions"
	// header squeezed into a narrow column) need actual line breaks, not a
	// single-line label that ignores them.
	label.maximumNumberOfLines = 0
	label.lineBreakMode = .byWordWrapping
	return label
}

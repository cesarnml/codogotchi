import AppKit

/// Inline notice explaining why the platform-logo animation is not running, and
/// offering the way out of the conflict.
///
/// Design notes, since several of these were deliberate rather than incidental:
///
/// - **Attached, not global.** It sits directly under the toggle it describes
///   with tighter spacing than the gap between rows, so it reads as part of that
///   control rather than a page-level alert. Proximity is what tells the user
///   which setting is affected.
/// - **Only when actionable.** Shown solely when the user has actually asked for
///   the animation. Someone running Reduce Motion with the toggle off is not in
///   conflict with anything and must never see this.
/// - **Informational, not an error.** Reduce Motion working correctly is not a
///   failure, so the strip is neutral — no warning tint, no red, no triangle, no
///   modal. An earlier revision tinted it orange; that read as the app
///   complaining about the user's accessibility setting.
/// - **Announced, not just drawn.** The whole point is to explain an
///   accessibility conflict, so it posts to VoiceOver rather than relying on the
///   user visually noticing a strip appear below a switch.
/// - **It never animates.** Sliding or fading in a panel whose subject is
///   "you asked for less motion" would be self-defeating; it appears at once.
/// - **Both directions are one click.** The override is reversible from the same
///   spot it was granted, so the user is never left having to remember which
///   app they told to ignore a system setting.
final class ReduceMotionNoticeView: NSView {
	/// The user chose to animate despite the system setting.
	var onAnimateAnyway: (() -> Void)?
	/// The user withdrew that choice.
	var onRespectReduceMotion: (() -> Void)?

	private let glyph = NSImageView()
	private let messageLabel = NSTextField(wrappingLabelWithString: "")
	private let actionButton = NSButton(title: "", target: nil, action: nil)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		// One group, so VoiceOver reads the explanation and its action as a single
		// related unit instead of three loose siblings.
		setAccessibilityRole(.group)

		glyph.translatesAutoresizingMaskIntoConstraints = false
		glyph.imageScaling = .scaleProportionallyUpOrDown
		glyph.image = NSImage(
			systemSymbolName: "figure.walk.motion", accessibilityDescription: nil)
		// Decorative only — it duplicates the message, so exposing it just makes
		// VoiceOver read the notice as two unrelated items.
		glyph.setAccessibilityElement(false)
		addSubview(glyph)

		messageLabel.font = .systemFont(ofSize: 11)
		messageLabel.isSelectable = false
		messageLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(messageLabel)

		// Borderless link-style button: this is a secondary, in-context choice,
		// not a primary action competing with the toggle beside it. The title is
		// styled through an attributed string rather than `contentTintColor` —
		// that property tints template images and bezels, not a plain title, so
		// the label would otherwise draw in ordinary text colour and read as
		// static caption copy rather than something you can click.
		actionButton.translatesAutoresizingMaskIntoConstraints = false
		actionButton.isBordered = false
		actionButton.bezelStyle = .inline
		actionButton.target = self
		actionButton.action = #selector(actionTapped)
		actionButton.setAccessibilityRole(.link)
		addSubview(actionButton)

		NSLayoutConstraint.activate([
			glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			glyph.topAnchor.constraint(equalTo: topAnchor, constant: 9),
			glyph.widthAnchor.constraint(equalToConstant: 13),
			glyph.heightAnchor.constraint(equalToConstant: 13),

			messageLabel.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 8),
			messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			messageLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),

			actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			actionButton.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),

			bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private var state: GeneralTabViewModel.ReduceMotionNotice = .none

	/// Link-coloured, underlined title. See the note at the button's setup for
	/// why `contentTintColor` cannot do this job.
	private func linkTitle(_ text: String) -> NSAttributedString {
		NSAttributedString(
			string: text,
			attributes: [
				.foregroundColor: NSColor.linkColor,
				.underlineStyle: NSUnderlineStyle.single.rawValue,
				.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
			])
	}

	func configure(_ state: GeneralTabViewModel.ReduceMotionNotice) {
		let previous = self.state
		self.state = state
		guard state != .none else {
			isHidden = true
			return
		}
		isHidden = false

		switch state {
		case .suppressed:
			// Name the cause, state the effect, and point at the exact pane — the
			// user should not have to guess which of the two switches won, nor go
			// hunting for a setting whose location the app already knows.
			messageLabel.stringValue =
				"Reduce Motion is on in System Settings > Accessibility > Display, "
				+ "so the badge stays still."
			messageLabel.textColor = .secondaryLabelColor
			actionButton.attributedTitle = linkTitle("Animate anyway")
			glyph.contentTintColor = .secondaryLabelColor
		case .overridden:
			// Name the scope: this one switch governs every animation the app gates,
			// not just the toggle it sits under.
			messageLabel.stringValue = "Ignoring Reduce Motion for all Codogotchi animations."
			messageLabel.textColor = .secondaryLabelColor
			actionButton.attributedTitle = linkTitle("Respect Reduce Motion")
			glyph.contentTintColor = .secondaryLabelColor
		case .none:
			break
		}

		// Reduce Motion working correctly is not an error, so the strip stays
		// neutral rather than wearing a warning colour. An earlier revision tinted
		// the suppressed state orange at 10% alpha, which was both invisible
		// against the dark card and the wrong signal — it read as the app
		// complaining about the user's accessibility setting.
		layer?.backgroundColor = SettingsTheme.tableBackground.cgColor

		// The notice and its action are the whole answer to "why did my toggle do
		// nothing", so a VoiceOver user has to be told they exist rather than
		// having to stumble onto them below the switch.
		setAccessibilityLabel(messageLabel.stringValue)
		if state != previous {
			NSAccessibility.post(element: self, notification: .layoutChanged)
			NSAccessibility.post(
				element: NSApp as Any,
				notification: .announcementRequested,
				userInfo: [
					.announcement: messageLabel.stringValue,
					.priority: NSAccessibilityPriorityLevel.medium.rawValue,
				]
			)
		}
	}

	@objc private func actionTapped() {
		switch state {
		case .suppressed: onAnimateAnyway?()
		case .overridden: onRespectReduceMotion?()
		case .none: break
		}
	}
}

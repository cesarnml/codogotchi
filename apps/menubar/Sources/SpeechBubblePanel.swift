import AppKit
import Foundation

/// Renamed from the P15.08 "conflict bubble" (phase-15 advisory-observation
/// triage): the visual identity is a general-purpose "the codogotchi wants to
/// say something" speech bubble, distinct from `AttentionBubblePanel`, which
/// remains reserved for the AI-agent-platform's own `state.json` attention
/// signal. The session-cap conflict is this component's first caller; future
/// codogotchi-initiated notices are expected to reuse the same panel with
/// their own icon/title/message.

// MARK: - Layout

enum SpeechBubbleLayout {
	static let bodyHeight: CGFloat = 72
	static let hPad: CGFloat = 12
	static let vPad: CGFloat = 8
	static let cornerRadius: CGFloat = 10
	static let iconSize: CGFloat = 14
	/// Gap between the header row's bottom and the rule line, and between the
	/// rule line and the message row.
	static let rowGap: CGFloat = 6
	/// Diamond "thought bubble" tail. Only its lower half is ever visible —
	/// the upper half sits behind the body's bottom edge, in the reserved
	/// `tailVisibleHeight` strip below the body.
	static let tailSize: CGFloat = 14
	static var tailVisibleHeight: CGFloat { tailSize / 2 }
	/// Full panel height: the body plus the strip reserved for the tail's
	/// protruding lower half.
	static var height: CGFloat { bodyHeight + tailVisibleHeight }
	/// Vertical distance from the pet frame's top edge down to the tail's
	/// point — sprite cells carry empty headroom above the character, so this
	/// roughly lines the tail up with the character's actual head rather than
	/// the top of the transparent cell.
	static let topGapToCharacter: CGFloat = 8

	/// Horizontally centered on `petFrame`; anchored so the tail's point sits
	/// `topGapToCharacter` above `petFrame`'s top edge — the bubble reads as
	/// floating just above the character's head with its tail pointing down
	/// at it, a thought bubble, not a status card anchored below the pet like
	/// `AttentionBubblePanel`.
	static func frame(relativeTo petFrame: CGRect, visibleFrame: CGRect) -> CGRect {
		let width = AttentionBubbleLayoutMetrics.bubbleWidth(forPetWidth: petFrame.width)
		let x = petFrame.midX - width / 2
		let y = petFrame.maxY - topGapToCharacter
		let rect = CGRect(x: x, y: y, width: width, height: height)
		return clamped(rect, to: visibleFrame)
	}

	private static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
		let margin: CGFloat = 4
		let safe = bounds.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}
}

// MARK: - Panel

/// Borderless floating panel hosting `SpeechBubbleView`. Structurally mirrors
/// `AttentionBubblePanel` (frosted chrome, floating level, non-activating) but
/// is a distinct type so the two bubble kinds never share a field, an
/// instance, or a screen position/shape by construction.
@MainActor
final class SpeechBubblePanel: NSPanel {
	private let bubbleView: SpeechBubbleView

	init() {
		self.bubbleView = SpeechBubbleView(frame: .zero)
		super.init(
			contentRect: .zero,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		level = .floating
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true
		contentView = bubbleView
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	/// Fired when the user clicks the bubble's action affordance.
	var onAction: (() -> Void)? {
		get { bubbleView.onAction }
		set { bubbleView.onAction = newValue }
	}

	/// Configures the session-cap conflict notice. The title names what's
	/// actually happening (the render cap, in Settings' own vocabulary); the
	/// message names the two real user actions — raise the cap, or free a
	/// slot via right-click "Prune Session" — rather than a "pick who stays"
	/// framing Settings can't actually do.
	func configureConflict(origin: String?) {
		bubbleView.configure(
			icon: NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil),
			title: "Session Cap Reached",
			message: "Right-click a panel to Prune a Session, or raise the cap in Settings.",
			actionTitle: "Settings"
		)
	}

	func reposition(relativeTo petFrame: CGRect, visibleFrame: CGRect) {
		let f = SpeechBubbleLayout.frame(relativeTo: petFrame, visibleFrame: visibleFrame)
		setFrame(f, display: true)
		bubbleView.frame = NSRect(origin: .zero, size: f.size)
	}
}

// MARK: - View

private final class SpeechBubbleView: NSView {
	private let effectView = NSVisualEffectView(frame: .zero)
	private let tailView = NSView(frame: .zero)

	private let iconView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let ruleView = NSBox(frame: .zero)
	private let messageLabel = NSTextField(wrappingLabelWithString: "")
	private let actionButton = NSButton(title: "", target: nil, action: nil)

	/// Body content is pinned to this fixed-height region at the top of the
	/// view; the strip below it is reserved for the tail's protruding tip.
	private var bodyBottomConstraint: NSLayoutConstraint!

	var onAction: (() -> Void)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		buildUI()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func buildUI() {
		wantsLayer = true

		// Added before effectView so effectView draws over (hides) the tail
		// diamond's upper half, leaving only its protruding lower point visible.
		tailView.wantsLayer = true
		addSubview(tailView)

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		iconView.contentTintColor = .white
		iconView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(iconView)

		titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
		titleLabel.textColor = .white
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.maximumNumberOfLines = 1
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)

		ruleView.boxType = .separator
		ruleView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(ruleView)

		messageLabel.font = NSFont.systemFont(ofSize: 11)
		messageLabel.textColor = NSColor.white.withAlphaComponent(0.85)
		messageLabel.lineBreakMode = .byWordWrapping
		messageLabel.maximumNumberOfLines = 2
		messageLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(messageLabel)

		actionButton.bezelStyle = .inline
		actionButton.isBordered = false
		actionButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
		actionButton.contentTintColor = NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1.0)
		actionButton.target = self
		actionButton.action = #selector(performAction)
		actionButton.imagePosition = .noImage
		actionButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(actionButton)

		let hPad = SpeechBubbleLayout.hPad
		let vPad = SpeechBubbleLayout.vPad
		let icon = SpeechBubbleLayout.iconSize
		let gap = SpeechBubbleLayout.rowGap

		let bodyBottom = effectView.bottomAnchor.constraint(
			equalTo: bottomAnchor, constant: -SpeechBubbleLayout.tailVisibleHeight)
		bodyBottomConstraint = bodyBottom

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			bodyBottom,

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			iconView.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
			iconView.widthAnchor.constraint(equalToConstant: icon),
			iconView.heightAnchor.constraint(equalToConstant: icon),

			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
			titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			ruleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			ruleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			ruleView.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: gap),

			messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			messageLabel.topAnchor.constraint(equalTo: ruleView.bottomAnchor, constant: gap),

			actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			actionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 2),
			actionButton.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor, constant: -4),
		])

		applyChromeStyle()
	}

	func configure(icon: NSImage?, title: String, message: String, actionTitle: String) {
		icon?.isTemplate = true
		iconView.image = icon
		titleLabel.stringValue = title
		messageLabel.stringValue = message
		actionButton.title = actionTitle
	}

	override func layout() {
		super.layout()
		applyChromeStyle()
		layoutTail()
	}

	private func applyChromeStyle() {
		effectView.layer?.cornerRadius = SpeechBubbleLayout.cornerRadius
		effectView.layer?.masksToBounds = true
		effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		effectView.layer?.borderWidth = 1
		effectView.layer?.shadowColor = NSColor.black.cgColor
		effectView.layer?.shadowOpacity = 0.32
		effectView.layer?.shadowRadius = 8
		effectView.layer?.shadowOffset = CGSize(width: 0, height: -2)

		tailView.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.9).cgColor
		tailView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		tailView.layer?.borderWidth = 1
	}

	/// Diamond (45°-rotated square) centered on the seam between the body's
	/// bottom edge and the reserved tail strip, so its top half sits behind
	/// the body (hidden, since effectView draws on top of it there) and only
	/// its lower point protrudes below — the classic thought-bubble tail.
	private func layoutTail() {
		let size = SpeechBubbleLayout.tailSize
		let seamY = SpeechBubbleLayout.tailVisibleHeight
		tailView.frame = NSRect(
			x: bounds.midX - size / 2,
			y: seamY - size / 2,
			width: size,
			height: size
		)
		tailView.layer?.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		bounds.contains(point) ? super.hitTest(point) : nil
	}

	@objc private func performAction() {
		onAction?()
	}
}

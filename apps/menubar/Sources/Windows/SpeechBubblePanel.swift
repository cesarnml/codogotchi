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
	/// Must fit the header row, rule, a *two-line* wrapped message, and the
	/// action link at `minBubbleWidth` — any shorter and the vertical chain is
	/// unsatisfiable at narrow widths, so the solver breaks a constraint and
	/// the action link draws on top of the message's last line.
	static let bodyHeight: CGFloat = 86
	static let hPad: CGFloat = 12
	static let vPad: CGFloat = 8
	static let cornerRadius: CGFloat = 10
	static let iconSize: CGFloat = 14
	/// Matches `AttentionBubblePanel`'s `closeButtonSize` so the two bubbles'
	/// dismiss affordances read as the same control.
	static let dismissButtonSize: CGFloat = 13
	/// Gap between the header row's bottom and the rule line, and between the
	/// rule line and the message row.
	static let rowGap: CGFloat = 6
	/// Diamond "thought bubble" tail. Only its lower half is ever visible —
	/// the upper half sits behind the body's bottom edge, in the reserved
	/// `tailVisibleHeight` strip below the body.
	static let tailSize: CGFloat = 14
	/// Half the *rotated* diamond's height — its half-diagonal, not half its
	/// side. Reserving only `tailSize / 2` clipped ~3pt off the tail's point
	/// at the window's bottom edge, blunting it.
	static var tailVisibleHeight: CGFloat { tailSize / 2 * 2.0.squareRoot() }
	/// Full panel height: the body plus the strip reserved for the tail's
	/// protruding lower half.
	static var height: CGFloat { bodyHeight + tailVisibleHeight }
	/// Own/Combined mode: how far the tail's point dips *inside* the pet
	/// window's top edge. Sprite cells carry empty headroom above the
	/// character, so a tip exactly at `maxY` would float over transparent
	/// pixels — dipping inside lines it up closer to the character's head.
	static let tipInsetIntoPetFrame: CGFloat = 8

	/// Minimalist mode: how far the tail's point dips inside the strip
	/// panel's top edge. The strip panel's frame carries padding above its
	/// drawn chip row, so a tip hovering at the frame's `maxY` visually
	/// floated well above the chrome — dipping inside brings it down to just
	/// above the visible chip.
	static let tipInsetIntoStrip: CGFloat = 8

	/// Own/Combined mode: horizontally centered on the pet window, tail point
	/// dipping `tipInsetIntoPetFrame` inside its top edge — a thought bubble
	/// pointing at the character's head, not a status card anchored below the
	/// pet like `AttentionBubblePanel`.
	static func frame(aboveFloatingPetFrame petFrame: CGRect, visibleFrame: CGRect) -> CGRect {
		frame(
			centeredOn: petFrame,
			tipY: petFrame.maxY - tipInsetIntoPetFrame,
			visibleFrame: visibleFrame)
	}

	/// Minimalist mode: horizontally centered on the strip, tail point
	/// dipping `tipInsetIntoStrip` inside its top edge.
	static func frame(aboveMinimalistStrip stripFrame: CGRect, visibleFrame: CGRect) -> CGRect {
		frame(
			centeredOn: stripFrame,
			tipY: stripFrame.maxY - tipInsetIntoStrip,
			visibleFrame: visibleFrame)
	}

	private static func frame(centeredOn anchorFrame: CGRect, tipY: CGFloat, visibleFrame: CGRect)
		-> CGRect
	{
		let width = AttentionBubbleLayoutMetrics.bubbleWidth(forPetWidth: anchorFrame.width)
		let x = anchorFrame.midX - width / 2
		let rect = CGRect(x: x, y: tipY, width: width, height: height)
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

// MARK: - Copy

/// The session-cap conflict notice's strings, hoisted out of
/// `configureConflict` so tests can assert the message wraps within the
/// two-line budget at `minBubbleWidth`. The message deliberately does NOT end
/// with the word "Settings" — the Settings action link renders directly below
/// it, and a trailing "…in Settings." read as a doubled link.
enum SpeechBubbleConflictCopy {
	static let title = "Session Cap Reached"
	static let message = "Right-click a panel to Prune a Session, or raise the cap."
	static let actionTitle = "Settings"
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
		// One tick above `.floating` (which the gate badge, animation badge,
		// and pet panel all use) so this notice always draws in front of them
		// regardless of order-front call sequencing, instead of z-order being
		// whichever one happened to be shown/reordered most recently.
		level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
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

	/// Fired when the user clicks the X. This bubble never dismisses on its
	/// own (short of the conflict genuinely resolving) — the host must clear
	/// its own conflict state here or its next reposition re-fronts the panel.
	var onDismiss: (() -> Void)? {
		get { bubbleView.onDismiss }
		set { bubbleView.onDismiss = newValue }
	}

	/// Configures the session-cap conflict notice. The title names what's
	/// actually happening (the render cap, in Settings' own vocabulary); the
	/// message names the two real user actions — raise the cap, or free a
	/// slot via right-click "Prune Session" — rather than a "pick who stays"
	/// framing Settings can't actually do.
	func configureConflict(origin: String?) {
		bubbleView.configure(
			icon: NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil),
			title: SpeechBubbleConflictCopy.title,
			message: SpeechBubbleConflictCopy.message,
			actionTitle: SpeechBubbleConflictCopy.actionTitle
		)
	}

	func reposition(aboveFloatingPetFrame petFrame: CGRect, visibleFrame: CGRect) {
		apply(SpeechBubbleLayout.frame(aboveFloatingPetFrame: petFrame, visibleFrame: visibleFrame))
	}

	func reposition(aboveMinimalistStrip stripFrame: CGRect, visibleFrame: CGRect) {
		apply(SpeechBubbleLayout.frame(aboveMinimalistStrip: stripFrame, visibleFrame: visibleFrame))
	}

	private func apply(_ f: CGRect) {
		setFrame(f, display: true)
		bubbleView.frame = NSRect(origin: .zero, size: f.size)
	}
}

// MARK: - View

private final class SpeechBubbleView: NSView {
	private let effectView = NSVisualEffectView(frame: .zero)
	/// Dark overlay layered above the frosted material so nothing behind the
	/// window (desktop, other chrome) shows through — same recipe as
	/// `AnimationBadgeChrome.badgeTint`, reused here so this notice reads with
	/// the same guaranteed-readable dark floor the rest of the chrome has.
	private let tintView = AnimationBadgeChrome.makeTintView()
	private let tailView = NSView(frame: .zero)

	private let iconView = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let ruleView = NSBox(frame: .zero)
	private let messageLabel = NSTextField(wrappingLabelWithString: "")
	private let actionButton = NSButton(title: "", target: nil, action: nil)
	private let dismissButton = NSButton(title: "", target: nil, action: nil)

	/// Body content is pinned to this fixed-height region at the top of the
	/// view; the strip below it is reserved for the tail's protruding tip.
	private var bodyBottomConstraint: NSLayoutConstraint!

	var onAction: (() -> Void)?
	var onDismiss: (() -> Void)?

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
		addSubview(tintView)

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

		// Always visible (unlike `AttentionBubblePanel`'s hover-revealed X):
		// this notice never dismisses on its own, so its only exit must be
		// discoverable without hovering.
		let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold))
		dismissButton.image = xImage
		dismissButton.imagePosition = .imageOnly
		dismissButton.bezelStyle = .regularSquare
		dismissButton.isBordered = false
		dismissButton.focusRingType = .none
		dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.75)
		dismissButton.wantsLayer = true
		dismissButton.target = self
		dismissButton.action = #selector(performDismiss)
		dismissButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(dismissButton)

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

			tintView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
			tintView.topAnchor.constraint(equalTo: effectView.topAnchor),
			tintView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			iconView.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
			iconView.widthAnchor.constraint(equalToConstant: icon),
			iconView.heightAnchor.constraint(equalToConstant: icon),

			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
			titleLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: dismissButton.leadingAnchor, constant: -6),
			titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			dismissButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
			dismissButton.widthAnchor.constraint(
				equalToConstant: SpeechBubbleLayout.dismissButtonSize),
			dismissButton.heightAnchor.constraint(equalTo: dismissButton.widthAnchor),

			ruleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			ruleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			ruleView.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: gap),

			messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			messageLabel.topAnchor.constraint(equalTo: ruleView.bottomAnchor, constant: gap),
			messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: actionButton.topAnchor, constant: -2),

			// The link is pinned to the body's bottom edge, and the message is
			// only allowed to grow down to it — not the other way around
			// (`button.top = message.bottom` chained off a fixed body height),
			// where an over-wrapped message makes the chain unsatisfiable and
			// the solver drops a constraint, drawing the link on top of the
			// message's last line. This way an over-long message compresses at
			// its two-line max instead.
			actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
			actionButton.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -4),
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

		tintView.layer?.cornerRadius = SpeechBubbleLayout.cornerRadius
		tintView.layer?.masksToBounds = true

		// Same circle chrome as `AttentionBubblePanel`'s dismiss button
		// (`BubblePalette.dismissFill`/`dismissBorder`).
		dismissButton.layer?.cornerRadius = SpeechBubbleLayout.dismissButtonSize / 2
		dismissButton.layer?.masksToBounds = true
		dismissButton.layer?.borderWidth = 1
		dismissButton.layer?.borderColor =
			NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.46, alpha: 1.0).cgColor
		dismissButton.layer?.backgroundColor =
			NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1.0).cgColor

		// Fully opaque (not the frosted body's translucent border alpha) so
		// nothing behind the window shows through the tail's protruding tip —
		// matches the opaque dark floor `tintView` now guarantees for the body.
		tailView.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
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
		// Rotate via the view-level `frameCenterRotation`, NOT by setting
		// `layer?.transform`: AppKit owns a layer-backed view's layer geometry
		// and clobbers a hand-set transform on its next sync — which is exactly
		// how the tail rendered as an unrotated square in Own mode. Reset to 0
		// first so the frame is assigned in unrotated coordinates.
		tailView.frameCenterRotation = 0
		tailView.frame = NSRect(
			x: bounds.midX - size / 2,
			y: seamY - size / 2,
			width: size,
			height: size
		)
		tailView.frameCenterRotation = 45
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		bounds.contains(point) ? super.hitTest(point) : nil
	}

	@objc private func performAction() {
		onAction?()
	}

	@objc private func performDismiss() {
		onDismiss?()
	}
}

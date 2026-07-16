import AppKit

final class GateBadgeView: NSView {
	/// Dark-navy tint for the ticket token — keeps a blue hue but much darker
	/// than the old bright blue, layered over the frosted material.
	private static let ticketTint = NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.33, alpha: 0.90)

	/// Forwards a right-click anywhere on the ticket/gate stack up to
	/// `GateBadgePanel`, which converts it to a screen anchor.
	var onRightMouseDown: ((NSEvent) -> Void)?

	override func rightMouseDown(with event: NSEvent) {
		onRightMouseDown?(event)
	}

	/// Forwards a left-click-drag anywhere on the ticket/gate stack up to
	/// `GateBadgePanel`, which routes it into moving whichever panel owns the
	/// badge (the pet panel in Own/Combined mode, the badge strip in
	/// Minimalist mode) — this badge is always wrapped in its own floating
	/// `GateBadgePanel`, so unlike `AnimationBadgeView` there is no bubbling
	/// fallback case to preserve.
	var onDragBegan: (() -> Void)?
	var onDragChanged: (() -> Void)?
	var onDragEnded: (() -> Void)?

	override func mouseDown(with event: NSEvent) {
		onDragBegan?()
	}

	override func mouseDragged(with event: NSEvent) {
		onDragChanged?()
	}

	override func mouseUp(with event: NSEvent) {
		onDragEnded?()
	}

	private let stackView = NSStackView()
	private let ticketBadge = GateBadgeTokenView(
		tintColor: GateBadgeView.ticketTint,
		textColor: .white,
		weight: .semibold
	)
	private let gateBadge = GateBadgeTokenView(
		tintColor: nil,
		textColor: NSColor(calibratedWhite: 0.95, alpha: 1.0),
		weight: .medium
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		// Vertical: ticket token on top, gate token below. `configure(...)`
		// sets the real alignment per mode; `.centerX` here is just the
		// pre-`configure` initial value.
		stackView.orientation = .vertical
		stackView.alignment = .centerX
		stackView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stackView)
		stackView.addArrangedSubview(ticketBadge)
		stackView.addArrangedSubview(gateBadge)
		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	/// `tokenAlignment` picks how the ticket token stacks over the gate token:
	/// `.centerX` (the default, Own mode) centers each on the stack's midline,
	/// symmetric with the badge itself being centered on the pet sprite.
	/// `.leading` (Minimalist mode) instead lines up both tokens' left edges —
	/// matching `GateBadgePanel`'s Minimalist-mode panel placement, which
	/// left-aligns the whole badge to the platform chip rather than centering
	/// it on the strip.
	func configure(
		content: GateBadgeContent, metrics: GateBadgeLayout.Metrics,
		tokenAlignment: NSLayoutConstraint.Attribute = .centerX
	) {
		stackView.alignment = tokenAlignment
		stackView.spacing = metrics.interBadgeSpacing
		ticketBadge.configure(text: content.ticketId, metrics: metrics)
		gateBadge.configure(text: GateBadgeView.gateLabel(content.gate), metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	var preferredSize: CGSize {
		layoutSubtreeIfNeeded()
		return stackView.fittingSize
	}

	/// Human-readable, concise gate label. Reuses `ActivityState.displayLabel`
	/// (the gate states map 1:1 to activity states), falling back to the raw
	/// string for any unknown gate.
	static func gateLabel(_ rawGate: String) -> String {
		ActivityState(rawValue: rawGate)?.displayLabel ?? rawGate
	}
}


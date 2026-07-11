import AppKit

/// Frosted pill shown on right-click; matches the Codex “Close pet” control.
final class FloatingPetHidePromptView: NSView {
	private let onActivate: () -> Void
	private var trackingArea: NSTrackingArea?
	private var isHighlighted = false

	private let effectView = NSVisualEffectView(frame: .zero)
	private let tintView = FloatingPetHidePromptTintView(frame: .zero)
	private let label: NSTextField

	init(frame frameRect: NSRect, title: String = FloatingPetHidePrompt.title, onActivate: @escaping () -> Void) {
		self.onActivate = onActivate
		self.label = NSTextField(labelWithString: title)
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.isEmphasized = false
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		tintView.wantsLayer = true
		tintView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tintView)

		label.font = FloatingPetHidePrompt.font
		label.textColor = .white
		label.alignment = .center
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		label.layer?.zPosition = 2
		addSubview(label)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
			tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
			tintView.topAnchor.constraint(equalTo: topAnchor),
			tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyChromeStyles()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		nil
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea {
			removeTrackingArea(trackingArea)
		}
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) {
		setHighlighted(true)
	}

	override func mouseExited(with event: NSEvent) {
		setHighlighted(false)
	}

	override func layout() {
		super.layout()
		let radius = bounds.height / 2
		effectView.layer?.cornerRadius = radius
		effectView.layer?.masksToBounds = true
		tintView.layer?.cornerRadius = radius
		tintView.layer?.masksToBounds = true
		applyChromeStyles()
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		// `point` arrives in our SUPERVIEW's coordinate system; convert to our own
		// bounds before testing. When this row is a stacked subview (frame origin
		// != 0,0 — e.g. the top "Force Idle" row) comparing the raw superview-space
		// point against local `bounds` misses entirely, so the click falls through
		// to the container and nothing fires. This bug only spared the bottom row,
		// whose origin happens to be (0,0).
		let local = superview.map { convert(point, from: $0) } ?? point
		return bounds.contains(local) ? self : nil
	}

	override func mouseDown(with event: NSEvent) {
		activate()
	}

	func setHighlighted(_ highlighted: Bool) {
		guard isHighlighted != highlighted else { return }
		isHighlighted = highlighted
		applyChromeStyles()
	}

	func activate() {
		onActivate()
	}

	private func applyChromeStyles() {
		let radius = bounds.height / 2
		layer?.cornerRadius = radius
		effectView.isEmphasized = isHighlighted
		if isHighlighted {
			// Codex hover: solid blue, fully opaque.
			tintView.setGradient(
				top: NSColor(calibratedRed: 0.19, green: 0.44, blue: 0.98, alpha: 0.98),
				bottom: NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.92, alpha: 0.98)
			)
			layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
			layer?.shadowOpacity = 0.38
		} else {
			// Codex idle: dark charcoal over vibrancy so the pet blurs but the pill reads clearly.
			tintView.setGradient(
				top: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.19, alpha: 0.92),
				bottom: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 0.90)
			)
			layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
			layer?.shadowOpacity = 0.28
		}
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowRadius = 6
		layer?.shadowOffset = CGSize(width: 0, height: -2)
	}
}


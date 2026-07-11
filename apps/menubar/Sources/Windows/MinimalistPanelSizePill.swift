import AppKit

/// Layout for the "Panel Size" slider pill. Internal (not file-private) so
/// tests can pin the pill's slider range staying in lockstep with the
/// Customization tab's slider.
enum MinimalistPanelSizePill {
	/// Fixed pill size: the slider row with "Small"/"Large" captions beneath
	/// its endpoints, mirroring the Customization tab's badge-scale control.
	static let size = CGSize(width: 260, height: 48)
	static let cornerRadius: CGFloat = 12
	/// Vertical gap between the strip's bottom edge and the pill's top edge.
	static let gapBelowStrip: CGFloat = 6
	/// Slider range — identical to the Customization tab's badge-scale slider,
	/// which is the whole point: both controls drive the same global setting.
	static let minScale = Double(GateBadgeLayout.achievableMinScale)
	static let maxScale = Double(GateBadgeLayout.achievableMaxScale)
}

/// Slider that tracks from the first click even while its borderless,
/// non-activating host panel is not (and can never become) key.
private final class FirstMouseSlider: NSSlider {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Frosted pill hosting the "Panel Size" slider, shown when the user
/// activates the right-click "Panel Size…" affordance on a Minimalist strip.
/// Mirrors `FloatingPetHidePromptPanel`'s chrome (material, level, collection
/// behavior) and the Customization tab's control layout ("Small" — slider —
/// "Large"); the slider drives the same global `minimalist_badge_scale` the
/// Customization tab writes, so the change applies to every Minimalist
/// platform, not just the clicked strip.
final class MinimalistPanelSizePillPanel: NSPanel {
	private let slider = FirstMouseSlider()
	/// Fires on every slider tick with the new scale; `isFinal` is true on the
	/// mouse-up tick that ends the drag (or on a single click), so the caller
	/// can live-apply per tick but defer once-per-gesture work (the Settings
	/// re-sync notification) to the end of the gesture.
	var onScaleChanged: ((Double, Bool) -> Void)?

	init(frame: CGRect, initialScale: Double) {
		super.init(
			contentRect: frame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		// Same level rationale as FloatingPetHidePromptPanel: pet chrome is
		// re-fronted every poll tick and would bury a `.floating` pill.
		level = .popUpMenu
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true

		let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
		container.autoresizingMask = [.width, .height]

		let effectView = NSVisualEffectView()
		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.isEmphasized = false
		effectView.layer?.cornerRadius = MinimalistPanelSizePill.cornerRadius
		effectView.layer?.masksToBounds = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(effectView)

		let smallLabel = NSTextField(labelWithString: "Small")
		let largeLabel = NSTextField(labelWithString: "Large")
		for label in [smallLabel, largeLabel] {
			label.font = .systemFont(ofSize: 11)
			label.textColor = .white
			label.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(label)
		}

		slider.minValue = MinimalistPanelSizePill.minScale
		slider.maxValue = MinimalistPanelSizePill.maxScale
		slider.doubleValue = initialScale
		slider.isContinuous = true
		slider.target = self
		slider.action = #selector(sliderChanged(_:))
		slider.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(slider)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			effectView.topAnchor.constraint(equalTo: container.topAnchor),
			effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			// Slider spans the full pill width; the captions sit beneath its
			// endpoints, mirroring the Customization tab's Small/Large row.
			slider.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
			slider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
			slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
			smallLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
			smallLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
			largeLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
			largeLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
		])
		contentView = container
	}

	@objc private func sliderChanged(_ sender: NSSlider) {
		// A continuous slider fires this per drag tick; the tick delivered on
		// mouse-up marks the end of the gesture.
		let isFinal = NSApp.currentEvent.map { $0.type == .leftMouseUp } ?? true
		onScaleChanged?(sender.doubleValue, isFinal)
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}


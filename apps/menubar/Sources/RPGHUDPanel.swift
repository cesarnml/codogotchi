import AppKit
import QuartzCore

// MARK: - Layout

enum RPGHUDLayout {
	/// Fixed padding inside the HUD panel chrome.
	static let innerPadding: CGFloat = 6
	/// Horizontal gap between heart symbols.
	static let heartSpacing: CGFloat = 3
	/// Heart symbol side length.
	static let heartSize: CGFloat = 14
	/// XP ring diameter.
	static let ringDiameter: CGFloat = 28
	/// Gap between heart row and ring.
	static let heartRingGap: CGFloat = 6
	/// Corner radius for the HUD pill.
	static let cornerRadius: CGFloat = 8

	static func panelSize() -> CGSize {
		let w =
			innerPadding * 2
			+ heartSize * 3 + heartSpacing * 2
			+ heartRingGap
			+ ringDiameter
		let h = innerPadding * 2 + ringDiameter
		return CGSize(width: ceil(w), height: ceil(h))
	}

	/// Position the HUD panel centered horizontally over the pet, in the upper
	/// quarter of the frame, so it overlaps the sprite without covering the feet.
	static func frame(
		hudSize: CGSize,
		relativeTo petFrame: CGRect,
		visibleFrame: CGRect
	) -> CGRect {
		let x = petFrame.midX - hudSize.width / 2
		let y = petFrame.maxY - petFrame.height * 0.30 - hudSize.height / 2
		let rect = CGRect(x: x, y: y, width: hudSize.width, height: hudSize.height)
		let safe = visibleFrame.insetBy(dx: 4, dy: 4)
		let cx = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let cy = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: cx, y: cy, width: rect.width, height: rect.height)
	}
}

// MARK: - Heart subview

/// Renders one heart slot: full (red fill), half (left-fill dimmed right), or
/// empty (white 20% outline). Uses SF Symbols available on macOS 13+.
final class RPGHeartView: NSView {
	private let imageView = NSImageView()
	private var state: HeartState = .full

	override init(frame: NSRect) {
		super.init(frame: frame)
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
			imageView.topAnchor.constraint(equalTo: topAnchor),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(_ newState: HeartState) {
		guard newState != state else { return }
		state = newState
		refresh()
	}

	private func refresh() {
		let cfg = NSImage.SymbolConfiguration(scale: .small)
		switch state {
		case .full:
			imageView.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
				.withSymbolConfiguration(cfg)
			imageView.contentTintColor = NSColor.systemRed
		case .half:
			let sym =
				NSImage(systemSymbolName: "heart.lefthalf.fill", accessibilityDescription: nil)
				?? NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)
			imageView.image = sym?.withSymbolConfiguration(cfg)
			imageView.contentTintColor = NSColor.systemPink
		case .empty:
			imageView.image = NSImage(systemSymbolName: "heart", accessibilityDescription: nil)?
				.withSymbolConfiguration(cfg)
			imageView.contentTintColor = NSColor(calibratedWhite: 1.0, alpha: 0.35)
		}
	}

	func flash(isInjured: Bool) {
		let color = isInjured ? NSColor.systemRed : NSColor.systemGreen
		let anim = CABasicAnimation(keyPath: "backgroundColor")
		anim.fromValue = color.withAlphaComponent(0.55).cgColor
		anim.toValue = NSColor.clear.cgColor
		anim.duration = 0.35
		anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
		wantsLayer = true
		layer?.add(anim, forKey: "heartFlash")
	}
}

// MARK: - Ring subview

/// Circular XP ring: dark track + colored arc (fill = levelFraction) + centered
/// level label. Milestone flashes pulse the ring border gold.
final class RPGRingView: NSView {
	private var ringFraction: Double = 0
	private var level: Int = 1
	private let label = NSTextField(labelWithString: "")

	override init(frame: NSRect) {
		super.init(frame: frame)
		label.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
		label.font = NSFont.boldSystemFont(ofSize: 9)
		label.alignment = .center
		label.isBordered = false
		label.drawsBackground = false
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		NSLayoutConstraint.activate([
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(ringFraction: Double, level: Int) {
		let changed = ringFraction != self.ringFraction || level != self.level
		self.ringFraction = ringFraction
		self.level = level
		label.stringValue = "\(level)"
		if changed { needsDisplay = true }
	}

	override func draw(_ dirtyRect: NSRect) {
		let inset: CGFloat = 3
		let rect = bounds.insetBy(dx: inset, dy: inset)
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let radius = min(rect.width, rect.height) / 2

		// Track
		let track = NSBezierPath()
		track.appendArc(
			withCenter: center,
			radius: radius,
			startAngle: 0,
			endAngle: 360,
			clockwise: false
		)
		track.lineWidth = 3
		NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
		track.stroke()

		// Arc fill
		guard ringFraction > 0 else { return }
		let startDeg: CGFloat = 90
		let endDeg = startDeg - CGFloat(ringFraction) * 360
		let arc = NSBezierPath()
		arc.appendArc(
			withCenter: center,
			radius: radius,
			startAngle: startDeg,
			endAngle: endDeg,
			clockwise: true
		)
		arc.lineWidth = 3
		arc.lineCapStyle = .round
		NSColor.systemBlue.setStroke()
		arc.stroke()
	}

	func flash(isLevelUp: Bool, isMilestone: Bool) {
		let color = isMilestone ? NSColor.systemYellow : NSColor.systemCyan
		let anim = CABasicAnimation(keyPath: "borderColor")
		anim.fromValue = color.withAlphaComponent(0.9).cgColor
		anim.toValue = NSColor.clear.cgColor
		anim.duration = isMilestone ? 0.7 : 0.4
		anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
		wantsLayer = true
		layer?.add(anim, forKey: "ringFlash")
		if isMilestone {
			fireMilestoneBurst()
		}
	}

	private func fireMilestoneBurst() {
		let burst = CAEmitterLayer()
		burst.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
		burst.emitterSize = CGSize(width: bounds.width * 0.5, height: bounds.height * 0.5)
		burst.emitterShape = .circle
		let cell = CAEmitterCell()
		cell.birthRate = 80
		cell.lifetime = 0.6
		cell.velocity = 40
		cell.velocityRange = 20
		cell.scale = 0.04
		cell.scaleRange = 0.02
		cell.alphaSpeed = -1.5
		cell.color = NSColor.systemYellow.cgColor
		cell.contents = sparkleImage()
		burst.emitterCells = [cell]
		wantsLayer = true
		layer?.addSublayer(burst)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
			burst.birthRate = 0
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			burst.removeFromSuperlayer()
		}
	}

	private func sparkleImage() -> CGImage? {
		let sz: CGFloat = 4
		let img = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { _ in
			let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: sz, height: sz))
			NSColor.white.setFill()
			path.fill()
			return true
		}
		var rect = CGRect(origin: .zero, size: img.size)
		return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
	}
}

// MARK: - Content view

/// Hosts heart row + XP ring; drives flash effects.
final class RPGHUDContentView: NSView {
	private let heartViews: [RPGHeartView]
	private let ringView = RPGRingView(frame: .zero)
	private let effectView: NSVisualEffectView

	override init(frame: NSRect) {
		effectView = NSVisualEffectView(frame: frame)
		heartViews = (0..<3).map { _ in RPGHeartView(frame: .zero) }
		super.init(frame: frame)

		wantsLayer = true
		layer?.masksToBounds = false

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.layer?.cornerRadius = RPGHUDLayout.cornerRadius
		effectView.layer?.masksToBounds = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		layer?.cornerRadius = RPGHUDLayout.cornerRadius
		layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		layer?.borderWidth = 0.5
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0.30
		layer?.shadowRadius = 6
		layer?.shadowOffset = CGSize(width: 0, height: -1)

		let hStack = NSStackView()
		hStack.orientation = .horizontal
		hStack.alignment = .centerY
		hStack.spacing = RPGHUDLayout.heartSpacing
		hStack.translatesAutoresizingMaskIntoConstraints = false

		for hv in heartViews {
			hv.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				hv.widthAnchor.constraint(equalToConstant: RPGHUDLayout.heartSize),
				hv.heightAnchor.constraint(equalToConstant: RPGHUDLayout.heartSize),
			])
			hStack.addArrangedSubview(hv)
		}

		ringView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			ringView.widthAnchor.constraint(equalToConstant: RPGHUDLayout.ringDiameter),
			ringView.heightAnchor.constraint(equalToConstant: RPGHUDLayout.ringDiameter),
		])

		let outerStack = NSStackView(views: [hStack, ringView])
		outerStack.orientation = .horizontal
		outerStack.alignment = .centerY
		outerStack.spacing = RPGHUDLayout.heartRingGap
		outerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(outerStack)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			outerStack.leadingAnchor.constraint(
				equalTo: leadingAnchor, constant: RPGHUDLayout.innerPadding),
			outerStack.trailingAnchor.constraint(
				equalTo: trailingAnchor, constant: -RPGHUDLayout.innerPadding),
			outerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func update(hearts: [HeartState], ringFraction: Double, level: Int) {
		for (idx, hv) in heartViews.enumerated() {
			hv.configure(idx < hearts.count ? hearts[idx] : .empty)
		}
		ringView.configure(ringFraction: ringFraction, level: level)
	}

	func flash(_ event: RPGFlashEvent) {
		switch event {
		case .heartInjured:
			heartViews.forEach { $0.flash(isInjured: true) }
		case .heartHealed:
			heartViews.forEach { $0.flash(isInjured: false) }
		case .levelUp:
			ringView.flash(isLevelUp: true, isMilestone: false)
		case .milestoneBurst:
			ringView.flash(isLevelUp: true, isMilestone: true)
		}
	}
}

// MARK: - Panel

/// Floating NSPanel overlay that shows the RPG HUD on pet hover.
@MainActor
final class RPGHUDPanel: NSPanel {
	private let contentHUD: RPGHUDContentView

	init() {
		let size = RPGHUDLayout.panelSize()
		contentHUD = RPGHUDContentView(frame: CGRect(origin: .zero, size: size))
		super.init(
			contentRect: CGRect(origin: .zero, size: size),
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
		ignoresMouseEvents = true
		contentView = contentHUD
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func reposition(
		hearts: [HeartState],
		ringFraction: Double,
		level: Int,
		relativeTo petFrame: CGRect,
		visibleFrame: CGRect
	) {
		contentHUD.update(hearts: hearts, ringFraction: ringFraction, level: level)
		let size = RPGHUDLayout.panelSize()
		let frame = RPGHUDLayout.frame(
			hudSize: size,
			relativeTo: petFrame,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		contentHUD.frame = NSRect(origin: .zero, size: frame.size)
	}

	func flash(_ event: RPGFlashEvent) {
		contentHUD.flash(event)
	}
}

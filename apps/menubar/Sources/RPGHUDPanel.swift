import AppKit
import QuartzCore

// MARK: - Layout

/// Geometry for the RPG HUD. The HUD anchors to the **top-left inside** the
/// floating pet frame and scales with the pet so it stays proportional and does
/// not cover the sprite body. There is intentionally no background chrome — the
/// hearts and XP ring float directly over the pet, matching the design mockup.
enum RPGHUDLayout {
	/// Pet width that maps to scale 1.0. Mirrors `GateBadgeLayout`.
	static let baselinePetWidth: CGFloat = 220

	// Base (scale = 1.0) dimensions.
	static let heartHeight: CGFloat = 16
	/// Heart artwork aspect (width / height) — from the 208×192 source SVG.
	static let heartAspect: CGFloat = 208.0 / 192.0
	static let heartSpacing: CGFloat = 2
	/// Vertical gap between the heart row and the XP ring.
	static let rowGap: CGFloat = 3
	static let ringDiameter: CGFloat = 44
	/// Inset of the HUD's content corner from the pet frame's top-left corner.
	static let inset: CGFloat = 8
	/// HUD size scale clamp relative to `baselinePetWidth`.
	static let maxScale: CGFloat = 1.5
	static let minScale: CGFloat = 0.75
	/// Horizontal gap between the HUD and the pet's opaque left edge, as a
	/// fraction of the pet's opaque width — keeps a proportionally consistent gap
	/// at every frame size. Tuned so the max frame reads ~20pt.
	static let gapFraction: CGFloat = 0.12
	/// Extra padding baked into the panel so the heart damage/heal glow (which
	/// the flash SVGs render outside the heart core) is not clipped.
	static let glowPadBase: CGFloat = 8

	struct Metrics: Equatable {
		let scale: CGFloat
		let heartHeight: CGFloat
		let heartWidth: CGFloat
		let heartSpacing: CGFloat
		let rowGap: CGFloat
		let ringDiameter: CGFloat
		let inset: CGFloat
		let glowPad: CGFloat

		var heartsRowWidth: CGFloat { heartWidth * 3 + heartSpacing * 2 }
		var contentWidth: CGFloat { max(heartsRowWidth, ringDiameter) }
		var contentHeight: CGFloat { heartHeight + rowGap + ringDiameter }
	}

	static func metrics(for petFrame: CGRect) -> Metrics {
		let scale = max(minScale, min(maxScale, petFrame.width / baselinePetWidth))
		let hh = round(heartHeight * scale)
		return Metrics(
			scale: scale,
			heartHeight: hh,
			heartWidth: round(hh * heartAspect),
			heartSpacing: max(1, round(heartSpacing * scale)),
			rowGap: max(1, round(rowGap * scale)),
			ringDiameter: round(ringDiameter * scale),
			inset: round(inset * scale),
			glowPad: round(glowPadBase * scale)
		)
	}

	static func panelSize(_ m: Metrics) -> CGSize {
		CGSize(
			width: ceil(m.contentWidth + m.glowPad * 2),
			height: ceil(m.contentHeight + m.glowPad * 2)
		)
	}

	/// Position the HUD panel near the pet's top-left.
	///
	/// When `spriteAnchor` (the pet's opaque silhouette in global coordinates) is
	/// provided, the HUD's content right edge sits a proportional gap to the left
	/// of the sprite's true left edge — so the gap stays visually consistent at
	/// every frame size and the HUD never floats over the pet, regardless of the
	/// transparent padding in the artwork. Without an anchor it falls back to the
	/// pet frame's top-left inset. Vertical placement tracks the frame top in
	/// both cases. The panel extends `glowPad` beyond the content; clamped
	/// on-screen.
	static func frame(
		hudSize: CGSize,
		metrics m: Metrics,
		relativeTo petFrame: CGRect,
		spriteAnchor: CGRect?,
		visibleFrame: CGRect
	) -> CGRect {
		let y = petFrame.maxY - m.inset - hudSize.height + m.glowPad
		let x: CGFloat
		if let anchor = spriteAnchor, anchor.width > 0 {
			let gap = round(anchor.width * gapFraction)
			let contentRight = anchor.minX - gap
			x = contentRight - m.contentWidth - m.glowPad
		} else {
			x = petFrame.minX + m.inset - m.glowPad
		}
		let safe = visibleFrame.insetBy(dx: 2, dy: 2)
		let cx = max(safe.minX, min(safe.maxX - hudSize.width, x))
		let cy = max(safe.minY, min(safe.maxY - hudSize.height, y))
		return CGRect(x: cx, y: cy, width: hudSize.width, height: hudSize.height)
	}

	/// Death-marker (tombstone) geometry: a `ringDiameter`-sized square placed to
	/// the **right** of the pet, vertically centered on the HUD's XP ring. Mirrors
	/// the HUD's anchor/scale/gap mechanics but offsets right instead of left, so
	/// it never smashes into the pet. Clamped on-screen.
	static func tombstoneFrame(
		relativeTo petFrame: CGRect,
		spriteAnchor: CGRect?,
		visibleFrame: CGRect
	) -> CGRect {
		let m = metrics(for: petFrame)
		let side = m.ringDiameter
		// The HUD's XP ring sits at the bottom of its content box; this is its
		// center in global y (derived from `frame`'s vertical placement).
		let ringCenterY = petFrame.maxY - m.inset - m.heartHeight - m.rowGap - m.ringDiameter / 2
		let y = ringCenterY - side / 2
		let x: CGFloat
		if let anchor = spriteAnchor, anchor.width > 0 {
			let gap = round(anchor.width * gapFraction)
			x = anchor.maxX + gap
		} else {
			x = petFrame.maxX - m.inset - side
		}
		let safe = visibleFrame.insetBy(dx: 2, dy: 2)
		let cx = max(safe.minX, min(safe.maxX - side, x))
		let cy = max(safe.minY, min(safe.maxY - side, y))
		return CGRect(x: cx, y: cy, width: side, height: side)
	}
}

// MARK: - Heart subview

/// Renders one heart slot from the bundled pixel-art SVGs (full / half / empty).
/// On a half-heart loss or gain the affected slot briefly swaps in the
/// damage-flash / health-restored glow artwork, then settles to the new state.
final class RPGHeartView: NSView {
	/// How far the flash overlay extends past the heart cell so the glow that the
	/// flash SVGs render around the heart core lands fully inside the overlay.
	private static let flashGrow: CGFloat = 0.42

	private let base = NSImageView()
	private let flash = NSImageView()
	private var state: HeartState?

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		layer?.masksToBounds = false

		for v in [base, flash] {
			v.imageScaling = .scaleProportionallyUpOrDown
			v.translatesAutoresizingMaskIntoConstraints = false
			v.wantsLayer = true
			addSubview(v)
		}
		flash.alphaValue = 0

		NSLayoutConstraint.activate([
			base.leadingAnchor.constraint(equalTo: leadingAnchor),
			base.trailingAnchor.constraint(equalTo: trailingAnchor),
			base.topAnchor.constraint(equalTo: topAnchor),
			base.bottomAnchor.constraint(equalTo: bottomAnchor),

			flash.centerXAnchor.constraint(equalTo: centerXAnchor),
			flash.centerYAnchor.constraint(equalTo: centerYAnchor),
			flash.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1 + Self.flashGrow),
			flash.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1 + Self.flashGrow),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	/// Set the resting artwork for this slot. Idempotent.
	func setState(_ newState: HeartState) {
		guard newState != state else { return }
		state = newState
		base.image = Self.restingImage(newState)
	}

	/// Briefly pulse the damage-flash glow. `priorFull` picks the full vs half
	/// flash art based on what the slot looked like before it was hit.
	func playDamage(priorFull: Bool) {
		flash.image = NSImage(named: priorFull ? "heart_damage_flash" : "half_heart_damage_flash")
		pulse()
	}

	/// Briefly pulse the health-restored glow. `nowFull` picks the full vs half
	/// flash art based on what the slot looks like after healing.
	func playHeal(nowFull: Bool) {
		flash.image = NSImage(named: nowFull ? "heart_health_restored" : "half_heart_health_restored")
		pulse()
	}

	private func pulse() {
		let anim = CAKeyframeAnimation(keyPath: "opacity")
		anim.values = [0.0, 1.0, 1.0, 0.0]
		anim.keyTimes = [0.0, 0.18, 0.55, 1.0]
		anim.duration = 0.6
		anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		flash.layer?.add(anim, forKey: "heartFlash")
	}

	static func restingImage(_ s: HeartState) -> NSImage? {
		switch s {
		case .full: return NSImage(named: "heart_full_health")
		case .half: return NSImage(named: "heart_half_health")
		case .empty: return NSImage(named: "heart_empty")
		}
	}
}

// MARK: - Ring subview

/// Circular XP ring: a dark track with a continuous gold gradient arc filled to
/// the level fraction, the `lvl` wordmark, and the level number centered inside.
/// Level-ups pop the ring; milestones add a sparkle burst.
final class RPGRingView: NSView {
	private let trackLayer = CAShapeLayer()
	private let gradientLayer = CAGradientLayer()
	private let arcMaskLayer = CAShapeLayer()
	/// Frosted disc filling the ring interior so application text behind the HUD
	/// is blurred out and the level label stays readable on any background.
	private let blurView = NSVisualEffectView()
	/// Subtle dark tint over the frost to guarantee white-text contrast.
	private let discTintLayer = CALayer()
	private let lvlView = NSImageView()
	private let numberLabel = NSTextField(labelWithString: "")

	private var fraction: Double = 0
	private var level: Int = 1
	private var ringDiameter: CGFloat = RPGHUDLayout.ringDiameter

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		layer?.masksToBounds = false

		trackLayer.fillColor = NSColor.clear.cgColor
		trackLayer.strokeColor = NSColor(srgbRed: 0x58 / 255, green: 0x58 / 255, blue: 0x57 / 255, alpha: 1).cgColor
		layer?.addSublayer(trackLayer)

		// Gold vertical gradient (matches the ring SVG stops), revealed only along
		// the arc via the mask layer's stroked path.
		gradientLayer.colors = [
			NSColor(srgbRed: 0xFF / 255, green: 0xD2 / 255, blue: 0x3A / 255, alpha: 1).cgColor,
			NSColor(srgbRed: 0xFB / 255, green: 0xB8 / 255, blue: 0x1F / 255, alpha: 1).cgColor,
			NSColor(srgbRed: 0xF7 / 255, green: 0xA2 / 255, blue: 0x0D / 255, alpha: 1).cgColor,
		]
		gradientLayer.locations = [0.0, 0.5, 1.0]
		gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
		gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
		arcMaskLayer.fillColor = NSColor.clear.cgColor
		arcMaskLayer.strokeColor = NSColor.black.cgColor
		arcMaskLayer.lineCap = .round
		gradientLayer.mask = arcMaskLayer
		layer?.addSublayer(gradientLayer)

		// Frosted interior (blurs whatever is behind the panel) + dark tint, both
		// inside the ring, below the labels.
		blurView.material = .hudWindow
		blurView.blendingMode = .behindWindow
		blurView.state = .active
		blurView.appearance = NSAppearance(named: .darkAqua)
		blurView.wantsLayer = true
		blurView.layer?.masksToBounds = true
		addSubview(blurView)

		discTintLayer.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
		blurView.layer?.addSublayer(discTintLayer)

		// `lvl` wordmark + number are positioned manually in `relayoutRing` so they
		// stay centered as a group regardless of ring scale.
		lvlView.image = NSImage(named: "lvl")
		lvlView.imageScaling = .scaleProportionallyUpOrDown
		lvlView.wantsLayer = true
		applyTextShadow(to: lvlView)
		addSubview(lvlView)

		numberLabel.textColor = .white
		numberLabel.alignment = .center
		numberLabel.isBordered = false
		numberLabel.drawsBackground = false
		numberLabel.wantsLayer = true
		applyTextShadow(to: numberLabel)
		addSubview(numberLabel)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func applyTextShadow(to view: NSView) {
		view.shadow = {
			let s = NSShadow()
			s.shadowColor = NSColor.black.withAlphaComponent(0.8)
			s.shadowBlurRadius = 1.5
			s.shadowOffset = .zero
			return s
		}()
	}

	func configure(fraction: Double, level: Int, ringDiameter: CGFloat) {
		let changed =
			fraction != self.fraction || level != self.level || ringDiameter != self.ringDiameter
		self.fraction = max(0, min(1, fraction))
		self.level = level
		self.ringDiameter = ringDiameter
		numberLabel.stringValue = "\(level)"
		numberLabel.font = .systemFont(ofSize: max(8, round(ringDiameter * 0.32)), weight: .heavy)
		if changed {
			needsLayout = true
			relayoutRing()
		}
	}

	override func layout() {
		super.layout()
		relayoutRing()
	}

	private func relayoutRing() {
		let lineWidth = max(2.5, ringDiameter * 0.15)
		let inset = lineWidth / 2 + 0.5
		let rect = bounds.insetBy(dx: inset, dy: inset)
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let radius = min(rect.width, rect.height) / 2
		// Frosted/tinted disc fills the interior up to the inner edge of the stroke.
		let discR = max(0, radius - lineWidth / 2 + 0.5)

		let circle = CGMutablePath()
		circle.addArc(
			center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		trackLayer.frame = bounds
		trackLayer.path = circle
		trackLayer.lineWidth = lineWidth

		gradientLayer.frame = bounds
		arcMaskLayer.frame = bounds
		arcMaskLayer.lineWidth = lineWidth

		// Arc starts at top (12 o'clock) and grows clockwise.
		let arc = CGMutablePath()
		let start: CGFloat = .pi / 2
		let end = start - CGFloat(fraction) * 2 * .pi
		arc.addArc(
			center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
		arcMaskLayer.path = arc
		// Hide the gold entirely when there is no progress (round cap would
		// otherwise draw a stray dot at the 12 o'clock origin).
		gradientLayer.isHidden = fraction <= 0

		blurView.frame = NSRect(
			x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2)
		blurView.layer?.cornerRadius = discR
		discTintLayer.frame = blurView.bounds
		discTintLayer.cornerRadius = discR
		CATransaction.commit()

		// Center the "LVL" wordmark (top) over the level number (below) as a group,
		// nudged slightly down so "LVL" does not kiss the top of the ring.
		let lvlH = max(5, round(ringDiameter * 0.17))
		let lvlW = round(lvlH * 210 / 104)
		let numSize = numberLabel.fittingSize
		let gap = max(1, round(ringDiameter * 0.03))
		let nudge = round(ringDiameter * 0.05)
		let total = lvlH + gap + numSize.height
		let bottomY = bounds.midY - total / 2 - nudge
		numberLabel.frame = NSRect(
			x: round(bounds.midX - numSize.width / 2),
			y: round(bottomY),
			width: ceil(numSize.width),
			height: ceil(numSize.height))
		lvlView.frame = NSRect(
			x: round(bounds.midX - lvlW / 2),
			y: round(bottomY + numSize.height + gap),
			width: lvlW,
			height: lvlH)
	}

	func flash(isLevelUp: Bool, isMilestone: Bool) {
		let pop = CAKeyframeAnimation(keyPath: "transform.scale")
		pop.values = [1.0, 1.18, 1.0]
		pop.keyTimes = [0.0, 0.4, 1.0]
		pop.duration = isMilestone ? 0.6 : 0.4
		pop.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		wantsLayer = true
		layer?.add(pop, forKey: "ringPop")
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

/// Hosts the heart row (top) and the XP ring (below), both flush to the
/// content's top-left. Drives per-slot heart flashes by diffing successive
/// heart arrays, and forwards level events to the ring.
final class RPGHUDContentView: NSView {
	private let heartViews: [RPGHeartView]
	private let ringView = RPGRingView(frame: .zero)
	private var metrics = RPGHUDLayout.metrics(for: CGRect(x: 0, y: 0, width: 220, height: 220))
	private var lastHearts: [HeartState]?

	override init(frame: NSRect) {
		heartViews = (0..<3).map { _ in RPGHeartView(frame: .zero) }
		super.init(frame: frame)
		wantsLayer = true
		layer?.masksToBounds = false
		heartViews.forEach { addSubview($0) }
		addSubview(ringView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func update(hearts: [HeartState], ringFraction: Double, level: Int, metrics: RPGHUDLayout.Metrics) {
		self.metrics = metrics
		relayout()

		for (idx, hv) in heartViews.enumerated() {
			let newState = idx < hearts.count ? hearts[idx] : .empty
			let prev = (lastHearts.flatMap { idx < $0.count ? $0[idx] : nil }) ?? newState
			hv.setState(newState)
			if let last = lastHearts, idx < last.count, prev != newState {
				playHeartDelta(on: hv, from: prev, to: newState)
			}
		}
		lastHearts = hearts

		ringView.configure(fraction: ringFraction, level: level, ringDiameter: metrics.ringDiameter)
	}

	private func playHeartDelta(on hv: RPGHeartView, from prev: HeartState, to next: HeartState) {
		if next.rank < prev.rank {
			hv.playDamage(priorFull: prev == .full)
		} else if next.rank > prev.rank {
			hv.playHeal(nowFull: next == .full)
		}
	}

	private func relayout() {
		let pad = metrics.glowPad
		// Ring sits at the bottom-left of the content box (visually below the
		// heart row, since NSViews are y-up).
		ringView.frame = NSRect(
			x: pad, y: pad, width: metrics.ringDiameter, height: metrics.ringDiameter)

		let heartY = pad + metrics.ringDiameter + metrics.rowGap
		for (idx, hv) in heartViews.enumerated() {
			let x = pad + CGFloat(idx) * (metrics.heartWidth + metrics.heartSpacing)
			hv.frame = NSRect(x: x, y: heartY, width: metrics.heartWidth, height: metrics.heartHeight)
		}
	}

	func flash(_ event: RPGFlashEvent) {
		switch event {
		case .heartInjured, .heartHealed:
			// Per-slot heart animation is driven by the diff in `update`.
			break
		case .levelUp:
			ringView.flash(isLevelUp: true, isMilestone: false)
		case .milestoneBurst:
			ringView.flash(isLevelUp: true, isMilestone: true)
		}
	}
}

extension HeartState {
	/// Ordered fill rank for delta comparison: empty < half < full.
	fileprivate var rank: Int {
		switch self {
		case .empty: return 0
		case .half: return 1
		case .full: return 2
		}
	}
}

// MARK: - Panel

/// Floating NSPanel overlay that shows the RPG HUD over the pet. Fully
/// transparent (no chrome) so only the hearts and ring are visible. Visibility
/// is driven by hover (steady) and by transient reveals on animation moments.
@MainActor
final class RPGHUDPanel: NSPanel {
	private let contentHUD = RPGHUDContentView(frame: .zero)

	init() {
		super.init(
			contentRect: CGRect(x: 0, y: 0, width: 60, height: 60),
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
		alphaValue = 0
		contentView = contentHUD
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	/// Update content and reposition relative to the pet. Does not change
	/// visibility (caller controls alpha / ordering).
	func reposition(
		hearts: [HeartState],
		ringFraction: Double,
		level: Int,
		relativeTo petFrame: CGRect,
		spriteAnchor: CGRect? = nil,
		visibleFrame: CGRect
	) {
		let metrics = RPGHUDLayout.metrics(for: petFrame)
		let size = RPGHUDLayout.panelSize(metrics)
		let frame = RPGHUDLayout.frame(
			hudSize: size, metrics: metrics, relativeTo: petFrame, spriteAnchor: spriteAnchor,
			visibleFrame: visibleFrame)
		setFrame(frame, display: true)
		contentHUD.frame = NSRect(origin: .zero, size: frame.size)
		contentHUD.update(
			hearts: hearts, ringFraction: ringFraction, level: level, metrics: metrics)
	}

	func fadeIn() {
		orderFrontRegardless()
		NSAnimationContext.runAnimationGroup { ctx in
			ctx.duration = 0.18
			animator().alphaValue = 1
		}
	}

	/// Ensure the panel is visible without restarting the fade each call — used by
	/// steady reveals (hover, demo) that may fire many times per second.
	func ensureVisible() {
		orderFrontRegardless()
		if alphaValue < 0.99 {
			fadeIn()
		} else {
			alphaValue = 1
		}
	}

	func fadeOut() {
		NSAnimationContext.runAnimationGroup(
			{ ctx in
				ctx.duration = 0.25
				animator().alphaValue = 0
			},
			completionHandler: { [weak self] in
				if (self?.alphaValue ?? 0) <= 0.01 { self?.orderOut(nil) }
			})
	}

	func hideImmediately() {
		alphaValue = 0
		orderOut(nil)
	}

	func flash(_ event: RPGFlashEvent) {
		contentHUD.flash(event)
	}
}

// MARK: - Tombstone panel

/// Persistent floating overlay that marks the pet as dead (0 hearts): a
/// tombstone shown to the right of the pet at the XP-ring's vertical level.
/// Visible whenever the pet is dead, independent of hover. Fully transparent and
/// click-through, matching the other floating chrome panels.
@MainActor
final class TombstonePanel: NSPanel {
	private let imageView = NSImageView()

	init() {
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
		ignoresMouseEvents = true
		imageView.image = NSImage(named: "tombstone")
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.wantsLayer = true
		contentView = imageView
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	/// Reposition to the right of the pet at the XP-ring level. Does not change
	/// visibility (caller controls ordering).
	func reposition(relativeTo petFrame: CGRect, spriteAnchor: CGRect?, visibleFrame: CGRect) {
		let frame = RPGHUDLayout.tombstoneFrame(
			relativeTo: petFrame, spriteAnchor: spriteAnchor, visibleFrame: visibleFrame)
		setFrame(frame, display: true)
		imageView.frame = NSRect(origin: .zero, size: frame.size)
	}
}

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SpriteKit

/// Computes the alpha (non-transparent) bounding box of sprite artwork. Pure and
/// testable; used to anchor the RPG HUD beside the pet's real silhouette rather
/// than the transparent panel frame.
enum SpriteOpaqueBounds {
	/// Normalized (0..1) opaque bounding box of one image in a y-up coordinate
	/// space (origin bottom-left) to match SpriteKit/AppKit. Returns nil when the
	/// image is empty or fully transparent.
	static func normalizedBox(of cgImage: CGImage, alphaThreshold: UInt8 = 10) -> CGRect? {
		let w = cgImage.width
		let h = cgImage.height
		guard w > 0, h > 0 else { return nil }
		let bytesPerRow = w * 4
		var data = [UInt8](repeating: 0, count: bytesPerRow * h)
		return data.withUnsafeMutableBytes { raw -> CGRect? in
			guard let base = raw.baseAddress,
				let ctx = CGContext(
					data: base, width: w, height: h, bitsPerComponent: 8,
					bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
					bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { return nil }
			// CGContext is y-up; the drawn image is upright, so row 0 is the
			// sprite's bottom — matching the panel's y-up space (no flip needed).
			ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
			let bytes = raw.bindMemory(to: UInt8.self)
			var minX = w
			var minY = h
			var maxX = -1
			var maxY = -1
			for y in 0..<h {
				let row = y * bytesPerRow
				for x in 0..<w where bytes[row + x * 4 + 3] > alphaThreshold {
					if x < minX { minX = x }
					if x > maxX { maxX = x }
					if y < minY { minY = y }
					if y > maxY { maxY = y }
				}
			}
			guard maxX >= minX, maxY >= minY else { return nil }
			return CGRect(
				x: CGFloat(minX) / CGFloat(w),
				y: CGFloat(minY) / CGFloat(h),
				width: CGFloat(maxX - minX + 1) / CGFloat(w),
				height: CGFloat(maxY - minY + 1) / CGFloat(h)
			)
		}
	}

	/// Union of the per-frame opaque boxes — a stable box that contains the pet
	/// in every pose of the current animation, so the HUD anchor never overlaps
	/// and never jitters. Nil when no frame has opaque pixels.
	static func unionNormalizedBox(of images: [CGImage]) -> CGRect? {
		var result: CGRect?
		for image in images {
			guard let box = normalizedBox(of: image) else { continue }
			result = result.map { $0.union(box) } ?? box
		}
		return result
	}
}

enum SicknessLevel: Equatable {
	case none
	case warning
	case critical

	init(halfHearts: Int) {
		let clamped = max(0, min(6, halfHearts))
		switch clamped {
		case 1...2:
			self = .critical
		case 3...4:
			self = .warning
		default:
			self = .none
		}
	}
}

@MainActor
final class FloatingPetScene: SKScene {
	private var codexPet: CodexPet
	private var codogotchiPet: CodogotchiPet?
	private let ciContext: CIContext
	private let desaturateFrame: (CodexPet.Frame) -> CGImage?
	/// Test-injected interaction frame override. When nil, interaction frames are
	/// resolved live from `codexPet` so they track `replacePets` pet swaps.
	private let interactionFramesOverride: ((FloatingInteraction) -> [CodexPet.Frame])?

	private let petLayer = SKNode()
	private let overlayLayer = SKNode()
	private let spriteNode = SKSpriteNode()

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	/// When true (pet at 0 hearts), the sprite is rendered grayscale regardless of
	/// `currentMode`. Driven by the RPG path, not the activity-state visual mode.
	private var isGhosted = false
	private var sicknessLevel: SicknessLevel = .none
	private var currentInteraction: FloatingInteraction?
	private var currentFrames: [CodexPet.Frame] = [] {
		didSet { opaqueBoxDirty = true }
	}
	private var currentSource: FloatingFrameSource = .codex
	private var frameIndex: Int = 0
	private var timer: Timer?
	/// Cached normalized (0..1, y-up) opaque box unioned across the current
	/// frame set; recomputed only when the frame set changes so the HUD anchor
	/// doesn't jitter frame-to-frame.
	private var cachedOpaqueImageBox: CGRect?
	private var opaqueBoxDirty = true
	/// When true, frame timer is off (floating panel hidden). State updates still
	/// repaint once so show/hide restores the correct pose without animating.
	private var isAnimationPaused = false
	/// When set, overrides sheet-specific frame intervals (demo mode).
	private let demoFrameInterval: TimeInterval?

	// Idle escalation: while the agent stays continuously idle, the sprite walks
	// idle → impatient → frustrated by elapsed time. Resets on any transition.
	private let idleEscalationConfig: IdleEscalationConfig
	private let clock: () -> Date
	private var idleSince: Date?
	private var currentEscalation: IdleEscalation = .none
	/// Fired when the escalation level changes so the controller can re-label the
	/// animation badge ("Idle" → "Impatient" → "Frustrated") between transitions.
	var onIdleEscalationChange: ((IdleEscalation) -> Void)?

	init(
		size: CGSize,
		codexPet: CodexPet,
		codogotchiPet: CodogotchiPet?,
		demoFrameInterval: TimeInterval? = nil,
		idleEscalationConfig: IdleEscalationConfig = .production,
		initialIdleAge: TimeInterval = 0,
		clock: @escaping () -> Date = Date.init,
		desaturateFrame: ((CodexPet.Frame) -> CGImage?)? = nil,
		interactionFramesProvider: ((FloatingInteraction) -> [CodexPet.Frame])? = nil
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.idleEscalationConfig = idleEscalationConfig
		self.clock = clock
		let context = CIContext(options: nil)
		self.ciContext = context
		self.desaturateFrame = desaturateFrame ?? { frame in
			Self.desaturate(frame, ciContext: context)
		}
		self.interactionFramesOverride = interactionFramesProvider
		self.demoFrameInterval = demoFrameInterval
		// Scene starts in idle, so begin the idle clock immediately — the first
		// `update(state:.idle)` won't be a transition and would otherwise never
		// arm escalation. `initialIdleAge` backdates that clock so the pet can
		// launch already-escalated (the `tcib` idle-bump demo) under production
		// timing instead of waiting out the real escalation windows.
		self.idleSince = clock().addingTimeInterval(-max(0, initialIdleAge))
		super.init(size: size)

		backgroundColor = .clear
		scaleMode = .resizeFill
		petLayer.name = "pet"
		overlayLayer.name = "overlays"
		addChild(petLayer)
		addChild(overlayLayer)
		petLayer.addChild(spriteNode)
		layoutLayers()

		let initialFrames = resolveFrames(for: .idle)
		currentFrames = initialFrames.frames
		currentSource = initialFrames.source
		paintCurrentFrame()
		restartTimer()
	}

	deinit {
		timer?.invalidate()
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError("FloatingPetScene does not support storyboard initialization")
	}

	override var size: CGSize {
		didSet {
			layoutLayers()
			paintCurrentFrame()
		}
	}

	func setSicknessLevel(_ level: SicknessLevel) {
		guard level != sicknessLevel else { return }
		sicknessLevel = level
		refreshSicknessEffect()
	}

	/// Lock the pet to the 0-HP ghost animation: force grayscale (independent of
	/// the activity-state `VisualMode`) and freeze the sprite on the dedicated
	/// ghost row when available. While ghosted the scene ignores activity-state
	/// frame swaps, mouse interactions, and idle escalation until the pet revives.
	func setGhosted(_ ghosted: Bool) {
		guard ghosted != isGhosted else { return }
		isGhosted = ghosted
		if ghosted {
			// Drop any in-flight mouse interaction and idle escalation, then lock to
			// the ghost row. Activity-state changes still reach the badge
			// (panel-owned) but never touch the sprite or the idle clock until
			// revival.
			currentInteraction = nil
			if currentEscalation != .none {
				currentEscalation = .none
				onIdleEscalationChange?(.none)
			}
			let resolved = resolveGhostFrames()
			currentFrames = resolved.frames
			currentSource = resolved.source
			frameIndex = 0
			paintCurrentFrame()
			restartTimer()
		} else {
			// Revived: resume the live activity-state animation, re-arming the idle
			// clock when returning to a resting idle.
			idleSince = (currentState == .idle) ? clock() : nil
			let resolved = currentFramesForState()
			currentFrames = resolved.frames
			currentSource = resolved.source
			frameIndex = 0
			paintCurrentFrame()
			restartTimer()
		}
		refreshSicknessEffect()
	}

	func update(state: ActivityState, visualMode: VisualMode) {
		let stateChanged = state != currentState || currentFrames.isEmpty
		currentState = state
		currentMode = visualMode

		// While ghosted the pet is locked to the 0-HP animation. The latest
		// activity state is still stored — the panel badge reflects it and revival resumes
		// from it — but it never swaps the sprite or arms the idle clock.
		if isGhosted {
			return
		}

		// During an active mouse-reactive interaction the interaction animation
		// owns the sprite — defer the activity-state frame swap until the
		// interaction is cleared. The latest state is still stored so
		// `setInteraction(nil)` resumes from the most recent live/demo state.
		if currentInteraction != nil {
			paintCurrentFrame()
			return
		}

		if stateChanged {
			// A real transition resets idle escalation. Re-arm the idle clock when
			// entering idle; clear it otherwise.
			idleSince = (state == .idle) ? clock() : nil
			if currentEscalation != .none {
				currentEscalation = .none
				onIdleEscalationChange?(.none)
			}
			let resolved = currentIdleFrames()
			currentFrames = resolved.frames
			currentSource = resolved.source
			frameIndex = 0
			refreshSicknessEffect()
		}

		paintCurrentFrame()

		if stateChanged || timer == nil {
			restartTimer()
		}
	}

	/// Apply or clear a transient mouse-reactive interaction overlay
	/// (running-right / running-left / jumping). When `interaction` is non-nil
	/// and the reserved Codex row provides non-empty frames, the scene swaps
	/// to those frames for the duration of the interaction. When the row is
	/// missing (empty frames) the interaction is dropped and the current
	/// activity-state animation remains in place. Passing `nil` restores the
	/// ordinary activity-state animation.
	func setInteraction(_ interaction: FloatingInteraction?) {
		// Mouse interactions are suppressed while ghosted — the pet stays on the
		// ghost animation regardless of drag / click-hold gestures.
		guard !isGhosted else { return }
		guard let interaction else {
			guard currentInteraction != nil else { return }
			currentInteraction = nil
			let resolved = currentFramesForState()
			currentFrames = resolved.frames
			currentSource = resolved.source
			frameIndex = 0
			paintCurrentFrame()
			restartTimer()
			refreshSicknessEffect()
			return
		}

		if currentInteraction == interaction {
			return
		}

		let frames = interactionFrames(interaction)
		// `interactionFrames` resolves from the *current* `codexPet`, so a pet
		// swapped in via `replacePets` (e.g. selecting a different pet in Settings)
		// supplies its own reserved rows — never the launch-time pet's.
		guard !frames.isEmpty else {
			// Missing reserved row: keep current activity frames running so the
			// floating pet does not blank out on a pet whose sheet lacks the
			// reserved row.
			if currentInteraction != nil {
				currentInteraction = nil
				let resolved = currentFramesForState()
				currentFrames = resolved.frames
				currentSource = resolved.source
				frameIndex = 0
				paintCurrentFrame()
				restartTimer()
				refreshSicknessEffect()
			}
			return
		}

		let prior = currentInteraction
		let priorSource = currentSource
		let priorFramesCount = currentFrames.count
		let preserveRunningCycle = Self.isRunningInteraction(prior)
			&& Self.isRunningInteraction(interaction)
		let preserveJumpingToRunningCycle = prior == .jumping
			&& Self.isRunningInteraction(interaction)

		currentInteraction = interaction
		currentFrames = frames
		currentSource = .codexInteraction
		if preserveRunningCycle || preserveJumpingToRunningCycle {
			frameIndex = frameIndex % frames.count
			paintCurrentFrame()
			if priorSource == .codexInteraction, demoFrameInterval == nil, priorFramesCount != frames.count {
				restartTimer()
			}
		} else {
			frameIndex = 0
			paintCurrentFrame()
			if priorSource == .codexInteraction {
				if demoFrameInterval == nil, priorFramesCount != frames.count {
					restartTimer()
				}
			} else {
				restartTimer()
			}
		}
		refreshSicknessEffect()
	}

	/// Resolve reserved-row interaction frames from the current `codexPet`, or the
	/// test override when one was injected.
	private func interactionFrames(_ interaction: FloatingInteraction) -> [CodexPet.Frame] {
		if let override = interactionFramesOverride {
			return override(interaction)
		}
		return codexPet.floatingFrames(forInteraction: interaction)
	}

	private static func isRunningInteraction(_ interaction: FloatingInteraction?) -> Bool {
		interaction == .runningLeft || interaction == .runningRight
	}

	// MARK: - Test access

	var currentStateForTesting: ActivityState { currentState }
	var isGhostedForTesting: Bool { isGhosted }
	var sicknessLevelForTesting: SicknessLevel { sicknessLevel }
	var currentIdleEscalationForTesting: IdleEscalation { currentEscalation }
	var currentInteractionForTesting: FloatingInteraction? { currentInteraction }
	var currentFrameIndexForTesting: Int { frameIndex }
	var currentFramesForTesting: [NSImage] { currentFrames.map(\.image) }
	var currentFrameSourceForTesting: String { currentSource.logLabel }
	var petLayerForTesting: SKNode { petLayer }
	var overlayLayerForTesting: SKNode { overlayLayer }
	var currentTextureForTesting: SKTexture? { spriteNode.texture }
	var currentColorForTesting: NSColor { spriteNode.color }
	var currentColorBlendFactorForTesting: CGFloat { spriteNode.colorBlendFactor }
	var sicknessEffectNodeForTesting: SKNode? { overlayLayer.childNode(withName: "sicknessEffect") }
	var sicknessFlyCountForTesting: Int {
		sicknessEffectNodeForTesting?.children.filter { $0.name?.hasPrefix("sicknessFly") == true }.count ?? 0
	}
	var sicknessMiasmaBirthRateForTesting: CGFloat {
		(sicknessEffectNodeForTesting?.childNode(withName: "sicknessMiasma") as? SKEmitterNode)?
			.particleBirthRate ?? 0
	}

	/// Swap in new pet loaders and immediately repaint the current state.
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		if !supportsIdleEscalation, currentEscalation != .none {
			currentEscalation = .none
			onIdleEscalationChange?(.none)
		}
		let resolved = currentFramesForState()
		currentFrames = resolved.frames
		currentSource = resolved.source
		frameIndex = 0
		paintCurrentFrame()
		restartTimer()
		refreshSicknessEffect()
	}

	func advanceFrameForTesting() {
		tick()
	}

	/// Stop the frame loop while the floating panel is hidden.
	func pauseAnimation() {
		isAnimationPaused = true
		timer?.invalidate()
		timer = nil
	}

	/// Resume the frame loop after `show`. No-op when already running.
	func resumeAnimation() {
		isAnimationPaused = false
		restartTimer()
	}

	var isAnimationPausedForTesting: Bool { isAnimationPaused }

	// MARK: - Internals

	private func restartTimer() {
		guard !isAnimationPaused else { return }
		timer?.invalidate()
		guard !currentFrames.isEmpty else {
			timer = nil
			return
		}

		let interval: TimeInterval
		if let demo = demoFrameInterval {
			interval = demo
		} else {
			switch currentSource {
			case .codogotchi:
				interval = CodogotchiPet.frameInterval
			case .codexInteraction, .codex, .idleFallback:
				interval = CodexPet.animationCycleDuration / Double(max(currentFrames.count, 1))
			}
		}

		let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.tick() }
		}
		RunLoop.main.add(newTimer, forMode: .common)
		timer = newTimer
	}

	private func tick() {
		maybeEscalateIdle()
		guard !currentFrames.isEmpty else {
			return
		}
		frameIndex = (frameIndex + 1) % currentFrames.count
		paintCurrentFrame()
	}

	/// Idle escalation is available only when the Lite-Enhanced sheet is installed.
	private var supportsIdleEscalation: Bool {
		codogotchiPet?.hasLiteEnhancedSheet == true
	}

	/// Recompute idle escalation from elapsed time. Runs on the frame timer
	/// (idle always animates, so this fires regularly while idle). No-op unless
	/// the agent is continuously idle and not mid-interaction.
	private func maybeEscalateIdle() {
		// No idle → impatient → frustrated progression while the pet is ghosted.
		guard !isGhosted else { return }
		guard currentState == .idle, currentInteraction == nil else {
			return
		}
		guard supportsIdleEscalation, let since = idleSince else {
			applyIdleEscalation(.none)
			return
		}
		let level = idleEscalationConfig.escalation(forElapsed: clock().timeIntervalSince(since))
		applyIdleEscalation(level)
	}

	/// Step the idle escalation down by one level (frustrated→impatient→none).
	/// Called when the user holds a click for ≥5 s while the pet is escalated.
	/// No-op when already at `.none` or when not in the idle state.
	func decrementIdleEscalation() {
		guard currentState == .idle else { return }
		let next: IdleEscalation
		switch currentEscalation {
		case .frustrated: next = .impatient
		case .impatient: next = .none
		case .none: return
		}
		// Re-anchor the idle clock to the floor of the level we just stepped down
		// to, so the elapsed-time recompute on the next frame tick agrees with
		// `next` instead of demoting further. Anchoring to `clock()` (zero
		// elapsed) is what made frustrated→impatient land back on plain idle: the
		// very next tick re-derived `.none`. From this floor the timer naturally
		// re-escalates after the remaining time.
		idleSince = clock().addingTimeInterval(-idleEscalationConfig.elapsedFloor(for: next))
		applyIdleEscalation(next)
	}

	private func applyIdleEscalation(_ level: IdleEscalation) {
		guard level != currentEscalation else { return }
		currentEscalation = level
		onIdleEscalationChange?(level)
		guard currentState == .idle, currentInteraction == nil else { return }
		let resolved = currentIdleFrames()
		currentFrames = resolved.frames
		currentSource = resolved.source
		frameIndex = 0
		paintCurrentFrame()
		restartTimer()
	}

	/// Idle frame selection that honors the current escalation level: the
	/// impatient/frustrated lite rows when escalated and available, else the
	/// plain idle resolution (which also covers non-idle states).
	private func currentIdleFrames() -> (frames: [CodexPet.Frame], source: FloatingFrameSource) {
		if currentState == .idle, currentEscalation != .none {
			let escalated = codogotchiPet?.floatingFrames(forIdleEscalation: currentEscalation) ?? []
			if !escalated.isEmpty { return (escalated, .codogotchi) }
		}
		return resolveFrames(for: currentState)
	}

	private func currentFramesForState() -> (frames: [CodexPet.Frame], source: FloatingFrameSource) {
		currentState == .idle ? currentIdleFrames() : resolveFrames(for: currentState)
	}

	/// Frames for the 0-HP ghost presentation. Prefer the dedicated Lite-Basic
	/// ghost row; if absent, fall back to the Codex idle row.
	private func resolveGhostFrames() -> (frames: [CodexPet.Frame], source: FloatingFrameSource) {
		let liteGhost = codogotchiPet?.floatingGhostFrames() ?? []
		if !liteGhost.isEmpty { return (liteGhost, .codogotchi) }
		return (codexPet.floatingFrames(for: .idle), .idleFallback)
	}

	private func resolveFrames(for state: ActivityState) -> (frames: [CodexPet.Frame], source: FloatingFrameSource) {
		// CodogotchiPet covers SoA gate states and Lite-Basic hook states.
		let codogotchiFrames = codogotchiPet?.floatingFrames(for: state) ?? []
		if !codogotchiFrames.isEmpty { return (codogotchiFrames, .codogotchi) }

		// Codex sheet: hook-animation fallback for unknown/artless states.
		let codexFrames = codexPet.floatingFrames(for: state)
		if !codexFrames.isEmpty { return (codexFrames, .codex) }

		return (codexPet.floatingFrames(for: .idle), .idleFallback)
	}

	private func paintCurrentFrame() {
		guard !currentFrames.isEmpty else {
			spriteNode.texture = nil
			return
		}

		let frame = currentFrames[frameIndex % currentFrames.count]
		let textureImage: CGImage
		let colorBlendFactor: CGFloat
		// 0 HP forces grayscale regardless of the activity-state mode,
		// matching the failure-mode desaturation path.
		if isGhosted || currentMode == .desaturated {
			if let desaturated = desaturateFrame(frame) {
				textureImage = desaturated
				colorBlendFactor = 0
			} else {
				NSLog("FloatingPetScene: desaturate skipped - using gray failure fallback")
				textureImage = frame.cgImage
				colorBlendFactor = 1
			}
		} else {
			textureImage = frame.cgImage
			colorBlendFactor = 0
		}

		let texture = SKTexture(cgImage: textureImage)
		texture.filteringMode = .nearest
		spriteNode.texture = texture
		spriteNode.color = .gray
		spriteNode.colorBlendFactor = colorBlendFactor
		let spriteSize = fittedSpriteSize(for: frame.image.size)
		spriteNode.size = spriteSize
	}

	private func fittedSpriteSize(for imageSize: CGSize) -> CGSize {
		FloatingFramePolicy.fittedSpriteSize(imageSize: imageSize, panelSize: size)
	}

	/// Opaque (non-transparent) bounds of the current sprite, in the scene/panel
	/// coordinate space (origin bottom-left, y-up, 0..size). Accounts for the
	/// aspect-fit + centered placement of the sprite within the panel and the
	/// artwork's alpha bounding box (unioned across the current animation's
	/// frames, cached). Returns nil when no frame is loaded or all are
	/// transparent. Used to anchor the RPG HUD beside the pet's real silhouette.
	func currentSpriteOpaqueRect() -> CGRect? {
		guard !currentFrames.isEmpty else { return nil }
		if opaqueBoxDirty {
			cachedOpaqueImageBox = SpriteOpaqueBounds.unionNormalizedBox(
				of: currentFrames.map(\.cgImage))
			opaqueBoxDirty = false
		}
		guard let box = cachedOpaqueImageBox else { return nil }
		let imageSize = currentFrames[frameIndex % currentFrames.count].image.size
		return Self.opaqueRectInPanel(normalizedBox: box, imageSize: imageSize, panelSize: size)
	}

	/// Map a normalized (0..1, y-up) opaque box in image space to panel-local
	/// coordinates, honoring the aspect-fit + centered sprite placement. Pure +
	/// testable.
	static func opaqueRectInPanel(normalizedBox box: CGRect, imageSize: CGSize, panelSize: CGSize)
		-> CGRect?
	{
		guard imageSize.width > 0, imageSize.height > 0, panelSize.width > 0, panelSize.height > 0
		else { return nil }
		let drawn = FloatingFramePolicy.fittedSpriteSize(imageSize: imageSize, panelSize: panelSize)
		let originX = (panelSize.width - drawn.width) / 2
		let originY = (panelSize.height - drawn.height) / 2
		return CGRect(
			x: originX + box.minX * drawn.width,
			y: originY + box.minY * drawn.height,
			width: box.width * drawn.width,
			height: box.height * drawn.height
		)
	}

	private func layoutLayers() {
		let center = CGPoint(x: size.width / 2, y: size.height / 2)
		petLayer.position = center
		overlayLayer.position = center
		spriteNode.position = .zero
		refreshSicknessEffect()
	}

	// MARK: - Level-up effect (prototype)

	/// Cached, lazily-built effect textures. Generated once and reused so each
	/// level-up doesn't re-rasterize gradients.
	private var levelUpGlowTexture: SKTexture?
	private var levelUpSparkTexture: SKTexture?
	private var sicknessWarningGlowTexture: SKTexture?
	private var sicknessCriticalGlowTexture: SKTexture?
	private var sicknessFlyTexture: SKTexture?

	/// Gold tones for the level-up burst.
	private static let levelUpGold = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.45, alpha: 1.0)
	private static let levelUpWhiteGold = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.78, alpha: 1.0)
	private static let sicknessWarningGlow = NSColor(
		calibratedRed: 0.48,
		green: 0.95,
		blue: 0.42,
		alpha: 1.0
	)
	private static let sicknessCriticalGlow = NSColor(
		calibratedRed: 0.62,
		green: 1.0,
		blue: 0.32,
		alpha: 1.0
	)
	private static let sicknessFlyTint = NSColor(
		calibratedRed: 0.22,
		green: 0.28,
		blue: 0.10,
		alpha: 1.0
	)

	private func refreshSicknessEffect() {
		overlayLayer.childNode(withName: "sicknessEffect")?.removeFromParent()
		guard !isGhosted, sicknessLevel != .none else { return }

		let glowColor = sicknessLevel == .critical ? Self.sicknessCriticalGlow : Self.sicknessWarningGlow
		let glowTex: SKTexture
		if sicknessLevel == .critical {
			let cached = sicknessCriticalGlowTexture ?? Self.makeRadialGlowTexture(color: glowColor)
			sicknessCriticalGlowTexture = cached
			glowTex = cached
		} else {
			let cached = sicknessWarningGlowTexture ?? Self.makeRadialGlowTexture(color: glowColor)
			sicknessWarningGlowTexture = cached
			glowTex = cached
		}
		let flyTex = sicknessFlyTexture ?? Self.makeRadialGlowTexture(
			color: Self.sicknessFlyTint,
			diameter: 24
		)
		sicknessFlyTexture = flyTex

		let petRect = currentSpriteOpaqueRect()
			?? CGRect(
				x: size.width * 0.3,
				y: size.height * 0.15,
				width: size.width * 0.4,
				height: size.height * 0.7
			)
		let halfW = size.width / 2
		let halfH = size.height / 2
		let petCenter = CGPoint(x: petRect.midX - halfW, y: petRect.midY - halfH)
		let container = SKNode()
		container.name = "sicknessEffect"

		let aura = SKSpriteNode(texture: glowTex)
		aura.name = "sicknessAura"
		aura.position = CGPoint(x: petCenter.x, y: petCenter.y - petRect.height * 0.06)
		aura.blendMode = .add
		aura.zPosition = 1
		aura.alpha = sicknessLevel == .critical ? 0.34 : 0.18
		let auraScale: CGFloat = sicknessLevel == .critical ? 1.55 : 1.3
		aura.size = CGSize(width: petRect.width * auraScale, height: petRect.height * auraScale)
		let pulseOutAlpha: CGFloat = sicknessLevel == .critical ? 0.48 : 0.24
		let pulseOutScale: CGFloat = sicknessLevel == .critical ? 1.1 : 1.05
		let pulseDuration: TimeInterval = sicknessLevel == .critical ? 0.9 : 1.5
		aura.run(
			.repeatForever(
				.sequence([
					.group([
						.fadeAlpha(to: pulseOutAlpha, duration: pulseDuration),
						.scale(to: pulseOutScale, duration: pulseDuration),
					]),
					.group([
						.fadeAlpha(to: sicknessLevel == .critical ? 0.3 : 0.16, duration: pulseDuration),
						.scale(to: 1.0, duration: pulseDuration),
					]),
				])
			)
		)
		container.addChild(aura)

		let miasma = SKEmitterNode()
		miasma.name = "sicknessMiasma"
		miasma.particleTexture = glowTex
		miasma.position = CGPoint(x: petCenter.x, y: petRect.minY - halfH + petRect.height * 0.18)
		miasma.zPosition = 2
		miasma.particleBirthRate = sicknessLevel == .critical ? 32 : 14
		miasma.particleLifetime = sicknessLevel == .critical ? 2.2 : 1.8
		miasma.particleLifetimeRange = 0.6
		miasma.emissionAngle = .pi / 2
		miasma.emissionAngleRange = .pi / 4
		miasma.particleSpeed = sicknessLevel == .critical ? 32 : 24
		miasma.particleSpeedRange = sicknessLevel == .critical ? 18 : 10
		miasma.yAcceleration = sicknessLevel == .critical ? 18 : 10
		miasma.particlePositionRange = CGVector(dx: petRect.width * 0.55, dy: petRect.height * 0.18)
		miasma.particleAlpha = sicknessLevel == .critical ? 0.22 : 0.12
		miasma.particleAlphaRange = 0.08
		miasma.particleAlphaSpeed = sicknessLevel == .critical ? -0.08 : -0.05
		miasma.particleScale = sicknessLevel == .critical ? 0.48 : 0.32
		miasma.particleScaleRange = 0.12
		miasma.particleScaleSpeed = sicknessLevel == .critical ? 0.03 : 0.015
		miasma.particleColor = glowColor
		miasma.particleColorBlendFactor = 1.0
		miasma.particleBlendMode = .add
		container.addChild(miasma)

		let flyCount = sicknessLevel == .critical ? 4 : 2
		let flyDuration: TimeInterval = sicknessLevel == .critical ? 1.6 : 2.5
		let flyBase = CGPoint(x: petCenter.x + petRect.width * 0.18, y: petCenter.y + petRect.height * 0.18)
		for index in 0..<flyCount {
			let fly = SKSpriteNode(texture: flyTex)
			fly.name = "sicknessFly\(index)"
			fly.zPosition = 3
			fly.blendMode = .alpha
			fly.color = Self.sicknessFlyTint
			fly.colorBlendFactor = 1.0
			fly.alpha = sicknessLevel == .critical ? 0.75 : 0.55
			let flySize = sicknessLevel == .critical ? petRect.width * 0.06 : petRect.width * 0.05
			fly.size = CGSize(width: flySize, height: flySize)
			fly.position = flyBase
			let radiusX = petRect.width * (sicknessLevel == .critical ? 0.17 : 0.12) + CGFloat(index) * 3
			let radiusY = petRect.height * (sicknessLevel == .critical ? 0.11 : 0.08) + CGFloat(index) * 2
			let points = stride(from: 0.0, through: Double.pi * 2, by: Double.pi / 8).map { angle in
				CGPoint(
					x: flyBase.x + CGFloat(cos(angle + Double(index) * 0.7)) * radiusX,
					y: flyBase.y + CGFloat(sin(angle + Double(index) * 0.5)) * radiusY
				)
			}
			let path = CGMutablePath()
			if let first = points.first {
				path.move(to: first)
				for point in points.dropFirst() {
					path.addLine(to: point)
				}
				path.closeSubpath()
			}
			fly.run(
				.repeatForever(
					.sequence([
						.wait(forDuration: Double(index) * 0.18),
						.follow(path, asOffset: false, orientToPath: false, duration: flyDuration),
					])
				)
			)
			container.addChild(fly)
		}

		overlayLayer.addChild(container)
	}

	/// Play a transient level-up celebration: a bloom flash and rising spark
	/// fountain at the pet's feet, plus two radial "firework" bursts beside the
	/// pet — one low on the left (hip height), then a slightly delayed one high on
	/// the right (shoulder height). The fireworks stay clear of the panel edges.
	/// Additive-blended in the overlay layer, self-removing after ~2s. Safe to
	/// call repeatedly; an in-flight effect is replaced.
	func playLevelUpEffect() {
		overlayLayer.childNode(withName: "levelUpEffect")?.removeFromParent()

		// Work in overlay-local coordinates (overlayLayer sits at panel center).
		let halfW = size.width / 2
		let halfH = size.height / 2
		let petRect = currentSpriteOpaqueRect()
			?? CGRect(x: size.width * 0.3, y: size.height * 0.15,
					  width: size.width * 0.4, height: size.height * 0.7)
		let petCenterX = petRect.midX - halfW
		let petBottom = petRect.minY - halfH
		let petW = petRect.width
		let petH = petRect.height

		// Burst radius, plus clamps that keep each burst's glow off the box edges.
		let radius = max(min(size.width, size.height) * 0.17, 20)
		let pad: CGFloat = 4
		func clampX(_ x: CGFloat) -> CGFloat { min(max(x, -halfW + radius + pad), halfW - radius - pad) }
		func clampY(_ y: CGFloat) -> CGFloat { min(max(y, -halfH + radius + pad), halfH - radius - pad) }

		let sideOffset = max(petW * 0.5, radius * 0.9)
		let leftPos = CGPoint(
			x: clampX(petCenterX - sideOffset),
			y: clampY(petBottom + petH * 0.42))   // hip height, left
		let rightPos = CGPoint(
			x: clampX(petCenterX + sideOffset),
			y: clampY(petBottom + petH * 0.72))   // shoulder height, right

		let glowTex = levelUpGlowTexture ?? Self.makeRadialGlowTexture(color: Self.levelUpWhiteGold)
		levelUpGlowTexture = glowTex
		let sparkTex = levelUpSparkTexture ?? Self.makeRadialGlowTexture(color: Self.levelUpGold)
		levelUpSparkTexture = sparkTex

		let container = SKNode()
		container.name = "levelUpEffect"

		// Bottom animation: a bloom flash at the pet's feet and a rising fountain
		// of sparks, layered behind the two side fireworks.
		let basePoint = CGPoint(x: petCenterX, y: petBottom)

		let bloom = SKSpriteNode(texture: glowTex)
		bloom.blendMode = .add
		bloom.zPosition = 0
		bloom.position = basePoint
		let bloomSide = max(petW * 1.6, size.width * 0.7)
		bloom.size = CGSize(width: bloomSide, height: bloomSide)
		bloom.alpha = 0
		bloom.setScale(0.4)
		bloom.run(.sequence([
			.group([.fadeAlpha(to: 0.9, duration: 0.22), .scale(to: 1.0, duration: 0.22)]),
			.wait(forDuration: 0.18),
			.group([.fadeOut(withDuration: 0.7), .scale(to: 1.5, duration: 0.7)]),
		]))
		container.addChild(bloom)

		let fountainWidth = max(petW * 0.6, 30)
		let fountain = SKEmitterNode()
		fountain.particleTexture = sparkTex
		fountain.zPosition = 2
		fountain.position = basePoint
		fountain.particleBirthRate = 220
		fountain.particleLifetime = 1.0
		fountain.particleLifetimeRange = 0.5
		fountain.emissionAngle = .pi / 2          // straight up
		fountain.emissionAngleRange = .pi / 3
		fountain.particleSpeed = 110
		fountain.particleSpeedRange = 55
		fountain.yAcceleration = -40              // gentle slowdown as they rise
		fountain.particlePositionRange = CGVector(dx: fountainWidth, dy: 8)
		fountain.particleAlpha = 0.95
		fountain.particleAlphaSpeed = -0.85
		fountain.particleScale = 0.18
		fountain.particleScaleRange = 0.12
		fountain.particleScaleSpeed = -0.08
		fountain.particleColor = Self.levelUpGold
		fountain.particleColorBlendFactor = 1.0
		fountain.particleBlendMode = .add
		fountain.run(.sequence([
			.wait(forDuration: 0.55),
			.run { [weak fountain] in fountain?.particleBirthRate = 0 },
		]))
		container.addChild(fountain)

		spawnFirework(at: leftPos, radius: radius, delay: 0.0,
					  glowTex: glowTex, sparkTex: sparkTex, in: container)
		spawnFirework(at: rightPos, radius: radius, delay: 0.18,
					  glowTex: glowTex, sparkTex: sparkTex, in: container)

		overlayLayer.addChild(container)
		container.run(.sequence([.wait(forDuration: 2.0), .removeFromParent()]))
	}

	/// One firework: a quick central flash that scales up and fades, plus a short
	/// radial burst of sparks flying outward. `radius` bounds both so it stays
	/// inside the panel. `delay` staggers this burst relative to its sibling.
	private func spawnFirework(
		at position: CGPoint,
		radius: CGFloat,
		delay: TimeInterval,
		glowTex: SKTexture,
		sparkTex: SKTexture,
		in container: SKNode
	) {
		// Central flash.
		let flash = SKSpriteNode(texture: glowTex)
		flash.blendMode = .add
		flash.zPosition = 5
		flash.position = position
		flash.size = CGSize(width: radius * 2, height: radius * 2)
		flash.alpha = 0
		flash.setScale(0.25)
		flash.run(.sequence([
			.wait(forDuration: delay),
			.group([.fadeAlpha(to: 0.95, duration: 0.10), .scale(to: 1.0, duration: 0.16)]),
			.group([.fadeOut(withDuration: 0.4), .scale(to: 1.25, duration: 0.4)]),
			.removeFromParent(),
		]))
		container.addChild(flash)

		// Radial spark burst — emits a fixed number then stops. Speed × lifetime
		// keeps the spark reach near `radius` so it doesn't punch through the edges.
		let emitter = SKEmitterNode()
		emitter.particleTexture = sparkTex
		emitter.zPosition = 6
		emitter.position = position
		emitter.numParticlesToEmit = 34
		emitter.particleBirthRate = 0          // gated on by the delay action below
		emitter.particleLifetime = 0.5
		emitter.particleLifetimeRange = 0.2
		emitter.emissionAngle = 0
		emitter.emissionAngleRange = .pi * 2   // full circle
		emitter.particleSpeed = radius * 2.0
		emitter.particleSpeedRange = radius * 0.8
		emitter.particleAlpha = 0.95
		emitter.particleAlphaSpeed = -1.4
		emitter.particleScale = 0.12
		emitter.particleScaleRange = 0.07
		emitter.particleScaleSpeed = -0.12
		emitter.particleColor = Self.levelUpGold
		emitter.particleColorBlendFactor = 1.0
		emitter.particleBlendMode = .add
		emitter.run(.sequence([
			.wait(forDuration: delay),
			.run { [weak emitter] in emitter?.particleBirthRate = 1400 },
		]))
		container.addChild(emitter)
	}

	/// Soft radial gradient (opaque center → transparent edge) for the bloom and
	/// the spark particle. Premultiplied so additive blending reads cleanly.
	private static func makeRadialGlowTexture(color: NSColor, diameter: Int = 128) -> SKTexture {
		let image = renderImage(width: diameter, height: diameter) { ctx in
			let cs = CGColorSpaceCreateDeviceRGB()
			let rgb = color.usingColorSpace(.deviceRGB) ?? color
			let colors = [
				rgb.withAlphaComponent(1.0).cgColor,
				rgb.withAlphaComponent(0.0).cgColor,
			] as CFArray
			guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else {
				return
			}
			let c = CGPoint(x: diameter / 2, y: diameter / 2)
			ctx.drawRadialGradient(
				grad, startCenter: c, startRadius: 0, endCenter: c,
				endRadius: CGFloat(diameter) / 2, options: [])
		}
		let texture = image.map(SKTexture.init(cgImage:)) ?? SKTexture()
		return texture
	}

	/// Render into a fresh premultiplied-RGBA bitmap context and return the image.
	private static func renderImage(
		width: Int, height: Int, _ draw: (CGContext) -> Void
	) -> CGImage? {
		let cs = CGColorSpaceCreateDeviceRGB()
		guard let ctx = CGContext(
			data: nil, width: width, height: height, bitsPerComponent: 8,
			bytesPerRow: 0, space: cs,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
		else { return nil }
		draw(ctx)
		return ctx.makeImage()
	}

	private static func desaturate(_ frame: CodexPet.Frame, ciContext: CIContext) -> CGImage? {
		let ci = CIImage(cgImage: frame.cgImage)
		let filter = CIFilter.colorControls()
		filter.inputImage = ci
		filter.saturation = 0
		guard let output = filter.outputImage else { return nil }
		return ciContext.createCGImage(output, from: output.extent)
	}

	private enum FloatingFrameSource {
		case codex
		case codogotchi
		case idleFallback
		case codexInteraction

		var logLabel: String {
			switch self {
			case .codex:
				return "codex"
			case .codogotchi:
				return "codogotchi"
			case .idleFallback:
				return "idle-fallback"
			case .codexInteraction:
				return "codex-interaction"
			}
		}
	}
}

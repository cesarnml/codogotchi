import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SpriteKit

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
	private var currentInteraction: FloatingInteraction?
	private var currentFrames: [CodexPet.Frame] = []
	private var currentSource: FloatingFrameSource = .codex
	private var frameIndex: Int = 0
	private var timer: Timer?
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
		// arm escalation.
		self.idleSince = clock()
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

	func update(state: ActivityState, visualMode: VisualMode) {
		let stateChanged = state != currentState || currentFrames.isEmpty
		currentState = state
		currentMode = visualMode

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
		guard let interaction else {
			guard currentInteraction != nil else { return }
			currentInteraction = nil
			let resolved = currentFramesForState()
			currentFrames = resolved.frames
			currentSource = resolved.source
			frameIndex = 0
			paintCurrentFrame()
			restartTimer()
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

	/// Lite sheet only — Codex-only pets stay on row-0 idle without Impatient/Frustrated.
	private var supportsIdleEscalation: Bool {
		codogotchiPet?.hasLiteSheet == true
	}

	/// Recompute idle escalation from elapsed time. Runs on the frame timer
	/// (idle always animates, so this fires regularly while idle). No-op unless
	/// the agent is continuously idle and not mid-interaction.
	private func maybeEscalateIdle() {
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

	private func resolveFrames(for state: ActivityState) -> (frames: [CodexPet.Frame], source: FloatingFrameSource) {
		// CodogotchiPet covers SoA gate states (soaRowMap) and hook/lite states (liteRowMap).
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
		switch currentMode {
		case .normal:
			textureImage = frame.cgImage
			colorBlendFactor = 0
		case .desaturated:
			if let desaturated = desaturateFrame(frame) {
				textureImage = desaturated
				colorBlendFactor = 0
			} else {
				NSLog("FloatingPetScene: desaturate skipped - using gray failure fallback")
				textureImage = frame.cgImage
				colorBlendFactor = 1
			}
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

	private func layoutLayers() {
		let center = CGPoint(x: size.width / 2, y: size.height / 2)
		petLayer.position = center
		overlayLayer.position = center
		spriteNode.position = .zero
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

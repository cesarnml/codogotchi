import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SpriteKit

@MainActor
final class FloatingPetScene: SKScene {
	private let codexPet: MaliPet
	private let codogotchiPet: CodogotchiPet?
	private let ciContext: CIContext
	private let desaturateFrame: (MaliPet.Frame) -> CGImage?
	private let interactionFrames: (FloatingInteraction) -> [MaliPet.Frame]

	private let petLayer = SKNode()
	private let overlayLayer = SKNode()
	private let spriteNode = SKSpriteNode()

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentInteraction: FloatingInteraction?
	private var currentFrames: [MaliPet.Frame] = []
	private var frameIndex: Int = 0

	init(
		size: CGSize,
		codexPet: MaliPet,
		codogotchiPet: CodogotchiPet?,
		desaturateFrame: ((MaliPet.Frame) -> CGImage?)? = nil,
		interactionFramesProvider: ((FloatingInteraction) -> [MaliPet.Frame])? = nil
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		let context = CIContext(options: nil)
		self.ciContext = context
		self.desaturateFrame = desaturateFrame ?? { frame in
			Self.desaturate(frame, ciContext: context)
		}
		self.interactionFrames = interactionFramesProvider ?? { interaction in
			codexPet.frames(forInteraction: interaction)
		}
		super.init(size: size)

		backgroundColor = .clear
		scaleMode = .resizeFill
		petLayer.name = "pet"
		overlayLayer.name = "overlays"
		addChild(petLayer)
		addChild(overlayLayer)
		petLayer.addChild(spriteNode)
		layoutLayers()

		currentFrames = resolveFrames(for: .idle)
		paintCurrentFrame()
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
			currentFrames = resolveFrames(for: state)
			frameIndex = 0
		}

		paintCurrentFrame()
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
			currentFrames = resolveFrames(for: currentState)
			frameIndex = 0
			paintCurrentFrame()
			return
		}

		let frames = interactionFrames(interaction)
		guard !frames.isEmpty else {
			// Missing reserved row: keep current activity frames running so the
			// floating pet does not blank out on a pet whose sheet lacks the
			// reserved row.
			if currentInteraction != nil {
				currentInteraction = nil
				currentFrames = resolveFrames(for: currentState)
				frameIndex = 0
				paintCurrentFrame()
			}
			return
		}

		currentInteraction = interaction
		currentFrames = frames
		frameIndex = 0
		paintCurrentFrame()
	}

	// MARK: - Test access

	var currentStateForTesting: ActivityState { currentState }
	var currentInteractionForTesting: FloatingInteraction? { currentInteraction }
	var currentFrameIndexForTesting: Int { frameIndex }
	var currentFramesForTesting: [NSImage] { currentFrames.map(\.image) }
	var petLayerForTesting: SKNode { petLayer }
	var overlayLayerForTesting: SKNode { overlayLayer }
	var currentTextureForTesting: SKTexture? { spriteNode.texture }
	var currentColorForTesting: NSColor { spriteNode.color }
	var currentColorBlendFactorForTesting: CGFloat { spriteNode.colorBlendFactor }

	func advanceFrameForTesting() {
		advanceFrame()
	}

	// MARK: - Internals

	private func resolveFrames(for state: ActivityState) -> [MaliPet.Frame] {
		let codexFrames = codexPet.frames(for: state)
		if !codexFrames.isEmpty { return codexFrames }

		let codogotchiFrames = codogotchiPet?.frames(for: state) ?? []
		if !codogotchiFrames.isEmpty { return codogotchiFrames }

		return codexPet.frames(for: .idle)
	}

	private func advanceFrame() {
		guard !currentFrames.isEmpty else { return }
		frameIndex = (frameIndex + 1) % currentFrames.count
		paintCurrentFrame()
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

		spriteNode.texture = SKTexture(cgImage: textureImage)
		spriteNode.color = .gray
		spriteNode.colorBlendFactor = colorBlendFactor
		spriteNode.size = fittedSpriteSize(for: frame.image.size)
	}

	private func fittedSpriteSize(for imageSize: CGSize) -> CGSize {
		guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
			return imageSize
		}
		let scale = min(size.width / imageSize.width, size.height / imageSize.height)
		return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
	}

	private func layoutLayers() {
		let center = CGPoint(x: size.width / 2, y: size.height / 2)
		petLayer.position = center
		overlayLayer.position = center
		spriteNode.position = .zero
	}

	private static func desaturate(_ frame: MaliPet.Frame, ciContext: CIContext) -> CGImage? {
		let ci = CIImage(cgImage: frame.cgImage)
		let filter = CIFilter.colorControls()
		filter.inputImage = ci
		filter.saturation = 0
		guard let output = filter.outputImage else { return nil }
		return ciContext.createCGImage(output, from: output.extent)
	}
}

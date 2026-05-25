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

	private let petLayer = SKNode()
	private let overlayLayer = SKNode()
	private let spriteNode = SKSpriteNode()

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentFrames: [MaliPet.Frame] = []
	private var frameIndex: Int = 0

	init(
		size: CGSize,
		codexPet: MaliPet,
		codogotchiPet: CodogotchiPet?
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.ciContext = CIContext(options: nil)
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

		if stateChanged {
			currentFrames = resolveFrames(for: state)
			frameIndex = 0
		}

		paintCurrentFrame()
	}

	// MARK: - Test access

	var currentStateForTesting: ActivityState { currentState }
	var currentFrameIndexForTesting: Int { frameIndex }
	var currentFramesForTesting: [NSImage] { currentFrames.map(\.image) }
	var petLayerForTesting: SKNode { petLayer }
	var overlayLayerForTesting: SKNode { overlayLayer }

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
		switch currentMode {
		case .normal:
			textureImage = frame.cgImage
		case .desaturated:
			textureImage = desaturate(frame) ?? frame.cgImage
		}

		spriteNode.texture = SKTexture(cgImage: textureImage)
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

	private func desaturate(_ frame: MaliPet.Frame) -> CGImage? {
		let ci = CIImage(cgImage: frame.cgImage)
		let filter = CIFilter.colorControls()
		filter.inputImage = ci
		filter.saturation = 0
		guard let output = filter.outputImage else { return nil }
		return ciContext.createCGImage(output, from: output.extent)
	}
}

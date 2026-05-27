import AppKit
import XCTest

@testable import Codogotchi

@MainActor
final class FloatingPetSceneTests: XCTestCase {
	private func maliFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	private func maewFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")
			.path
	}

	private func missingCodogotchiPetDirectory() throws -> String {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("codogotchi-floating-scene-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let manifest = """
			{"id":"maew","display_name":"Maew","spritesheet_path":"missing.webp"}
			"""
		try manifest.write(
			to: root.appendingPathComponent("pet.json"),
			atomically: true,
			encoding: .utf8
		)
		return root.path
	}

	private func makeScene(
		size: CGSize = CGSize(width: 180, height: 140),
		codogotchiPet: CodogotchiPet? = nil,
		desaturateFrame: ((CodexPet.Frame) -> CGImage?)? = nil
	) throws -> FloatingPetScene {
		try FloatingPetScene(
			size: size,
			codexPet: CodexPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: codogotchiPet ?? CodogotchiPet(petDirectory: maewFixtureDirectory()),
			desaturateFrame: desaturateFrame
		)
	}

	func testResolvesIdleFramesFromCodexSheet() throws {
		let scene = try makeScene()

		scene.update(state: .idle, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .idle)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
		XCTAssertLessThanOrEqual(
			scene.currentFramesForTesting.count,
			CodexPet.rowMap[.idle]?.frameCount ?? 8
		)
		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)
		XCTAssertNotNil(scene.petLayerForTesting.parent)
		XCTAssertNotNil(scene.overlayLayerForTesting.parent)
	}

	func testFloatingSceneUsesSourceResolutionCodexTextures() throws {
		let scene = try makeScene(size: CGSize(width: 180, height: 140))

		scene.update(state: .idle, visualMode: .normal)

		let firstFrame = try XCTUnwrap(scene.currentFramesForTesting.first)
		let texture = try XCTUnwrap(scene.currentTextureForTesting)
		XCTAssertEqual(firstFrame.size.height, 208, accuracy: 0.001)
		XCTAssertEqual(texture.size().height, 208, accuracy: 0.001)
		XCTAssertEqual(texture.filteringMode, .nearest)
	}

	func testResolvesCodogotchiSheetStateFrames() throws {
		let scene = try makeScene()

		scene.update(state: .panicking, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .panicking)
		XCTAssertEqual(scene.currentFramesForTesting.count, 24)
	}

	func testFloatingSceneUsesSourceResolutionCodogotchiTextures() throws {
		let scene = try makeScene(size: CGSize(width: 180, height: 140))

		scene.update(state: .panicking, visualMode: .normal)

		let firstFrame = try XCTUnwrap(scene.currentFramesForTesting.first)
		let texture = try XCTUnwrap(scene.currentTextureForTesting)
		XCTAssertEqual(firstFrame.size.height, 208, accuracy: 0.001)
		XCTAssertEqual(texture.size().height, 208, accuracy: 0.001)
		XCTAssertEqual(texture.filteringMode, .nearest)
	}

	func testStateTransitionResetsFrameIndex() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		scene.advanceFrameForTesting()
		scene.advanceFrameForTesting()
		XCTAssertGreaterThan(scene.currentFrameIndexForTesting, 0)

		scene.update(state: .runningTests, visualMode: .normal)

		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)
		XCTAssertEqual(scene.currentFramesForTesting.count, 4)
	}

	func testAnimationTimerAdvancesFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)

		let advanced = expectation(description: "timer advances frame index")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
			advanced.fulfill()
		}
		wait(for: [advanced], timeout: 1.0)

		XCTAssertGreaterThan(
			scene.currentFrameIndexForTesting,
			0,
			"floating pet should advance frames on a repeating timer like MenubarRenderer"
		)
	}

	func testMissingCodogotchiFramesFallBackToIdle() throws {
		let missingPet = try CodogotchiPet(petDirectory: missingCodogotchiPetDirectory())
		let scene = try makeScene(codogotchiPet: missingPet)

		scene.update(state: .panicking, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .panicking)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
		XCTAssertLessThanOrEqual(
			scene.currentFramesForTesting.count,
			CodexPet.rowMap[.idle]?.frameCount ?? 8
		)
	}

	func testSceneSizingHonorsSuppliedFloatingFrameSize() throws {
		let scene = try makeScene(size: CGSize(width: 260, height: 180))

		XCTAssertEqual(scene.size.width, 260)
		XCTAssertEqual(scene.size.height, 180)
		XCTAssertEqual(scene.petLayerForTesting.position, CGPoint(x: 130, y: 90))
		XCTAssertEqual(scene.overlayLayerForTesting.position, CGPoint(x: 130, y: 90))
	}

	func testDesaturationFailureUsesGrayFallback() throws {
		let scene = try makeScene(desaturateFrame: { _ in nil })
		scene.update(state: .idle, visualMode: .normal)
		XCTAssertNotNil(scene.currentTextureForTesting)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 0)

		scene.update(state: .idle, visualMode: .desaturated)

		XCTAssertNotNil(scene.currentTextureForTesting)
		let fallbackColor = try XCTUnwrap(scene.currentColorForTesting.usingColorSpace(.deviceRGB))
		XCTAssertEqual(fallbackColor.redComponent, 0.5, accuracy: 0.001)
		XCTAssertEqual(fallbackColor.greenComponent, 0.5, accuracy: 0.001)
		XCTAssertEqual(fallbackColor.blueComponent, 0.5, accuracy: 0.001)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 1)
	}

	func testNormalModeClearsGrayFallback() throws {
		let scene = try makeScene(desaturateFrame: { _ in nil })
		scene.update(state: .idle, visualMode: .desaturated)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 1)

		scene.update(state: .idle, visualMode: .normal)

		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 0)
	}
}

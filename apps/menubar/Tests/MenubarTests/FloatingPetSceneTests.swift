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

	func testSetDeadRendersGrayscaleAndClearsOnRevive() throws {
		// A desaturate that fails routes the death path to the gray fallback
		// (colorBlendFactor == 1) — a deterministic signal desaturation was asked
		// for, independent of pixel inspection.
		let scene = try makeScene(desaturateFrame: { _ in nil })
		scene.update(state: .idle, visualMode: .normal)
		XCTAssertFalse(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 0)

		scene.setDead(true)
		XCTAssertTrue(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 1)

		scene.setDead(false)
		XCTAssertFalse(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentColorBlendFactorForTesting, 0)
	}

	// MARK: - Death lock

	func testDeadLocksToLiteErroredRowSource() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(scene.currentFrameSourceForTesting, "codogotchi")

		scene.setDead(true)

		// Dead reuses the lite sheet's errored row (interim until a dedicated dead
		// row ships): still a codogotchi source with the full 8-frame loop.
		XCTAssertTrue(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentFrameSourceForTesting, "codogotchi")
		XCTAssertEqual(scene.currentFramesForTesting.count, 8)
	}

	func testActivityStateUpdatesIgnoredWhileDead() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		scene.setDead(true)
		let deadFrames = scene.currentFramesForTesting.map(ObjectIdentifier.init)

		// A live activity change still advances the stored state (the panel badge
		// reads it) but must not swap the locked dead sprite.
		scene.update(state: .thinking, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .thinking)
		XCTAssertEqual(
			scene.currentFramesForTesting.map(ObjectIdentifier.init),
			deadFrames,
			"sprite frames must stay locked to the dead animation while dead"
		)
	}

	func testMouseInteractionsSuppressedWhileDead() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		scene.setDead(true)
		let deadFrames = scene.currentFramesForTesting.map(ObjectIdentifier.init)

		scene.setInteraction(.jumping)

		XCTAssertNil(scene.currentInteractionForTesting)
		XCTAssertEqual(
			scene.currentFramesForTesting.map(ObjectIdentifier.init),
			deadFrames,
			"mouse interactions must not disturb the dead animation"
		)
	}

	func testReviveRestoresActivityAnimation() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		scene.setDead(true)

		scene.setDead(false)

		XCTAssertFalse(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentStateForTesting, .implementing)
		XCTAssertEqual(scene.currentFrameSourceForTesting, "codogotchi")
		XCTAssertEqual(scene.currentFramesForTesting.count, 8)
	}

	func testCodexOnlyPetDeadFallsBackToIdle() throws {
		let missingPet = try CodogotchiPet(petDirectory: missingCodogotchiPetDirectory())
		XCTAssertFalse(missingPet.hasLiteSheet)
		let scene = try makeScene(codogotchiPet: missingPet)
		scene.update(state: .idle, visualMode: .normal)

		scene.setDead(true)

		// No lite sheet → dead falls back to the Codex idle row.
		XCTAssertTrue(scene.isDeadForTesting)
		XCTAssertEqual(scene.currentFrameSourceForTesting, "idle-fallback")
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
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

		scene.update(state: .adversarialReview, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .adversarialReview)
		XCTAssertEqual(scene.currentFramesForTesting.count, 8)
	}

	func testFloatingSceneUsesSourceResolutionCodogotchiTextures() throws {
		let scene = try makeScene(size: CGSize(width: 180, height: 140))

		scene.update(state: .adversarialReview, visualMode: .normal)

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

		scene.update(state: .thinking, visualMode: .normal)

		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)
		// .thinking resolves from the lite sheet (CodogotchiPet first) — 8 frames
		XCTAssertEqual(scene.currentFramesForTesting.count, 8)
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

	func testPauseAnimationStopsFrameTimer() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		let indexBeforePause = scene.currentFrameIndexForTesting

		scene.pauseAnimation()
		XCTAssertTrue(scene.isAnimationPausedForTesting)

		let wait = expectation(description: "paused scene does not advance")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
			wait.fulfill()
		}
		self.wait(for: [wait], timeout: 1.0)

		XCTAssertEqual(scene.currentFrameIndexForTesting, indexBeforePause)

		scene.resumeAnimation()
		XCTAssertFalse(scene.isAnimationPausedForTesting)

		let advanced = expectation(description: "timer resumes after show")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
			advanced.fulfill()
		}
		self.wait(for: [advanced], timeout: 1.0)

		XCTAssertGreaterThan(scene.currentFrameIndexForTesting, indexBeforePause)
	}

	func testMissingCodogotchiFramesFallBackToIdle() throws {
		let missingPet = try CodogotchiPet(petDirectory: missingCodogotchiPetDirectory())
		let scene = try makeScene(codogotchiPet: missingPet)

		scene.update(state: .adversarialReview, visualMode: .normal)

		XCTAssertEqual(scene.currentStateForTesting, .adversarialReview)
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

	// MARK: - Idle escalation

	private func makeEscalationScene(
		clock: @escaping () -> Date,
		impatientAfter: TimeInterval = 60,
		frustratedAfter: TimeInterval = 120,
		initialIdleAge: TimeInterval = 0
	) throws -> FloatingPetScene {
		try FloatingPetScene(
			size: CGSize(width: 180, height: 140),
			codexPet: CodexPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: CodogotchiPet(petDirectory: maewFixtureDirectory()),
			idleEscalationConfig: IdleEscalationConfig(
				impatientAfter: impatientAfter,
				frustratedAfter: frustratedAfter
			),
			initialIdleAge: initialIdleAge,
			clock: clock
		)
	}

	func testInitialIdleAgeLaunchesAlreadyFrustratedThenBumpsNormally() throws {
		// Backdates the idle clock past the frustrated threshold (the `tcib`
		// demo): she starts frustrated, and click-hold de-escalation then behaves
		// under the normal production-shaped timing.
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now }, initialIdleAge: 130)

		scene.update(state: .idle, visualMode: .normal)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)

		// First bump → impatient, stable; second bump → none.
		scene.decrementIdleEscalation()
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
		scene.decrementIdleEscalation()
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)

		// And she re-escalates from zero on the normal cadence afterward.
		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
	}

	func testIdleEscalationFrozenWhileDead() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(130) // past frustratedAfter (120)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)

		// Dying resets escalation to none and emits the change.
		var emitted: [IdleEscalation] = []
		scene.onIdleEscalationChange = { emitted.append($0) }
		scene.setDead(true)
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
		XCTAssertEqual(emitted, [.none])

		// Frame ticks with elapsed idle time must NOT re-escalate while dead —
		// dead means dead until revived.
		now = now.addingTimeInterval(10_000)
		scene.advanceFrameForTesting()
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
		XCTAssertEqual(emitted, [.none])

		// After revival the idle clock re-arms from zero and escalates normally.
		scene.setDead(false)
		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
	}

	func testIdleEscalatesImpatientThenFrustratedByElapsedTime() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })

		scene.update(state: .idle, visualMode: .normal)
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)

		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)

		now = now.addingTimeInterval(60) // 121s total idle
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)
	}

	func testTransitionResetsIdleEscalationAndReArmsOnReturnToIdle() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(130)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)

		// Any real transition clears escalation immediately (last_until_next_transition).
		scene.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)

		// Returning to idle re-arms the clock from zero rather than reusing stale elapsed.
		now = now.addingTimeInterval(10_000)
		scene.update(state: .idle, visualMode: .normal)
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
	}

	func testCodexOnlyPetWithoutLiteSheetDoesNotEscalateIdle() throws {
		let mali = maliFixtureDirectory()
		var now = Date(timeIntervalSince1970: 1_000_000)
		let codogotchiPet = try CodogotchiPet(petDirectory: mali)
		XCTAssertFalse(codogotchiPet.hasLiteSheet)
		let scene = try FloatingPetScene(
			size: CGSize(width: 180, height: 140),
			codexPet: CodexPet(petDirectory: mali),
			codogotchiPet: codogotchiPet,
			idleEscalationConfig: IdleEscalationConfig(
				impatientAfter: 60,
				frustratedAfter: 120
			),
			clock: { now }
		)
		var emitted: [IdleEscalation] = []
		scene.onIdleEscalationChange = { emitted.append($0) }

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(200)
		scene.advanceFrameForTesting()

		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
		XCTAssertTrue(emitted.isEmpty)
	}

	func testDecrementStepsFrustratedToImpatientAndStaysPutAcrossFrameTicks() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(130) // > frustratedAfter (120)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)

		// One bump: frustrated → impatient, and it must survive the next frame
		// tick rather than the elapsed-time recompute demoting it back to idle.
		scene.decrementIdleEscalation()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)

		// Second bump: impatient → none, also stable across a tick.
		scene.decrementIdleEscalation()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .none)
	}

	func testDecrementToImpatientReEscalatesToFrustratedAfterRemainingTime() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(130)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)

		// Bump down to impatient: the clock is re-anchored to the impatient floor,
		// so re-escalation to frustrated takes (frustratedAfter - impatientAfter).
		scene.decrementIdleEscalation()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)

		now = now.addingTimeInterval(59) // still short of the 60s remaining window
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)

		now = now.addingTimeInterval(2) // crosses the frustrated threshold
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .frustrated)
	}

	func testIdleEscalationEmitsLevelChangesToObserver() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let scene = try makeEscalationScene(clock: { now })
		var emitted: [IdleEscalation] = []
		scene.onIdleEscalationChange = { emitted.append($0) }

		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		now = now.addingTimeInterval(60)
		scene.advanceFrameForTesting()

		XCTAssertEqual(emitted, [.impatient, .frustrated])
	}

	func testClearingInteractionRestoresEscalatedIdleFrames() throws {
		var now = Date(timeIntervalSince1970: 1_000_000)
		let codogotchiPet = try CodogotchiPet(petDirectory: maewFixtureDirectory())
		let scene = try FloatingPetScene(
			size: CGSize(width: 180, height: 140),
			codexPet: CodexPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: codogotchiPet,
			idleEscalationConfig: IdleEscalationConfig(
				impatientAfter: 60,
				frustratedAfter: 120
			),
			clock: { now }
		)
		scene.update(state: .idle, visualMode: .normal)
		now = now.addingTimeInterval(61)
		scene.advanceFrameForTesting()
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)

		let impatientFirstFrame = try XCTUnwrap(
			codogotchiPet.floatingFrames(forIdleEscalation: .impatient).first?.image
				.tiffRepresentation
		)
		let plainIdleFirstFrame = try XCTUnwrap(
			codogotchiPet.floatingFrames(for: .idle).first?.image.tiffRepresentation
		)
		XCTAssertNotEqual(
			impatientFirstFrame,
			plainIdleFirstFrame,
			"fixture must distinguish plain and escalated idle rows for this regression test"
		)

		scene.setInteraction(.jumping)
		XCTAssertEqual(scene.currentInteractionForTesting, .jumping)
		scene.setInteraction(nil)

		XCTAssertNil(scene.currentInteractionForTesting)
		XCTAssertEqual(scene.currentIdleEscalationForTesting, .impatient)
		XCTAssertEqual(
			try XCTUnwrap(scene.currentFramesForTesting.first?.tiffRepresentation),
			impatientFirstFrame,
			"ending drag/resize must restore the rendered idle-escalation row, not plain idle"
		)
	}

	// MARK: - Sprite opaque bounds (HUD anchoring)

	/// Build a `width`×`height` RGBA image with an opaque rectangle (in y-up
	/// pixel coords) and everything else transparent.
	private func makeImage(
		width: Int, height: Int, opaque: CGRect
	) -> CGImage {
		let bytesPerRow = width * 4
		var data = [UInt8](repeating: 0, count: bytesPerRow * height)
		let ctx = CGContext(
			data: &data, width: width, height: height, bitsPerComponent: 8,
			bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
		ctx.fill(opaque)
		return ctx.makeImage()!
	}

	func testNormalizedBoxFindsOpaqueRegion() {
		// 10×10 image, opaque 4×4 block at x∈[2,6), y∈[3,7) (y-up).
		let img = makeImage(width: 10, height: 10, opaque: CGRect(x: 2, y: 3, width: 4, height: 4))
		let box = try! XCTUnwrap(SpriteOpaqueBounds.normalizedBox(of: img))
		XCTAssertEqual(box.minX, 0.2, accuracy: 0.001)
		XCTAssertEqual(box.minY, 0.3, accuracy: 0.001)
		XCTAssertEqual(box.width, 0.4, accuracy: 0.001)
		XCTAssertEqual(box.height, 0.4, accuracy: 0.001)
	}

	func testNormalizedBoxReturnsNilForFullyTransparentImage() {
		let img = makeImage(width: 8, height: 8, opaque: .zero)
		XCTAssertNil(SpriteOpaqueBounds.normalizedBox(of: img))
	}

	func testUnionBoxSpansAllFrames() {
		let left = makeImage(width: 10, height: 10, opaque: CGRect(x: 1, y: 1, width: 2, height: 2))
		let right = makeImage(width: 10, height: 10, opaque: CGRect(x: 6, y: 6, width: 3, height: 3))
		let union = try! XCTUnwrap(SpriteOpaqueBounds.unionNormalizedBox(of: [left, right]))
		XCTAssertEqual(union.minX, 0.1, accuracy: 0.001)
		XCTAssertEqual(union.minY, 0.1, accuracy: 0.001)
		XCTAssertEqual(union.maxX, 0.9, accuracy: 0.001)
		XCTAssertEqual(union.maxY, 0.9, accuracy: 0.001)
	}

	/// A portrait sprite in a square panel is letterboxed horizontally; the
	/// mapped opaque rect must account for the centered fit, not the panel edges.
	func testOpaqueRectInPanelHonorsAspectFitLetterbox() {
		// 100×200 image (portrait) in a 200×200 panel → fit scale 1.0, drawn
		// 100×200, centered with 50pt margins left/right.
		let imageSize = CGSize(width: 100, height: 200)
		let panelSize = CGSize(width: 200, height: 200)
		// Opaque box covering the full image.
		let box = CGRect(x: 0, y: 0, width: 1, height: 1)
		let rect = try! XCTUnwrap(
			FloatingPetScene.opaqueRectInPanel(
				normalizedBox: box, imageSize: imageSize, panelSize: panelSize))
		XCTAssertEqual(rect.minX, 50, accuracy: 0.5, "centered horizontally with 50pt margin")
		XCTAssertEqual(rect.width, 100, accuracy: 0.5)
		XCTAssertEqual(rect.minY, 0, accuracy: 0.5, "fills height")
		XCTAssertEqual(rect.height, 200, accuracy: 0.5)
	}
}

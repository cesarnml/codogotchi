import AppKit
import CoreImage
import XCTest

@testable import Codogotchi

/// Behavior contract for `MenubarRenderer` — the `NSStatusItem`-driving
/// renderer that composites Codex-sheet and codogotchi-sheet frames, paints
/// a single static hero frame per active row, and supports a desaturated
/// visual mode used during early failure visuals.
///
/// Tests inject an image-sink closure so they do not require a real
/// `NSStatusItem` or a running `NSApplication` event loop.
@MainActor
final class MenubarRendererTests: XCTestCase {
	// MARK: - Fixture helpers

	private func maliFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	private func maewFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/maew")
			.path
	}

	private func makeCodexPet() throws -> CodexPet {
		try CodexPet(petDirectory: maliFixtureDirectory())
	}

	private func makeCodogotchiPet() throws -> CodogotchiPet {
		try CodogotchiPet(petDirectory: maewFixtureDirectory())
	}

	private func makeRenderer(sink: @escaping MenubarRenderer.ImageSink = { _ in }) throws -> MenubarRenderer {
		try MenubarRenderer(codexPet: makeCodexPet(), codogotchiPet: makeCodogotchiPet(), sink: sink)
	}

	// MARK: - State transitions

	func testNormalModeImplementingSelectsImplementingFrameSource() throws {
		let codexPet = try makeCodexPet()
		let codogotchiPet = try makeCodogotchiPet()
		var lastImage: NSImage?
		let renderer = try MenubarRenderer(codexPet: codexPet, codogotchiPet: codogotchiPet) { image in
			lastImage = image
		}

		renderer.update(state: .implementing, visualMode: .normal)

		XCTAssertEqual(renderer.currentStateForTesting, .implementing)
		XCTAssertEqual(renderer.currentVisualModeForTesting, .normal)
		// P8.06: .implementing resolves from the lite sheet (CodogotchiPet first) — 8 frames
		XCTAssertEqual(
			renderer.currentFramesForTesting.count,
			codogotchiPet.frames(for: .implementing).count,
			"renderer must resolve .implementing from lite sheet (CodogotchiPet first)"
		)
		XCTAssertEqual(renderer.currentFramesForTesting.count, 8)
		XCTAssertNotNil(lastImage, "renderer must push at least one frame to the sink on state change")
	}

	func testStateTransitionLandsOnHeroFrame() throws {
		let codexPet = try makeCodexPet()
		let codogotchiPet = try makeCodogotchiPet()
		let renderer = try MenubarRenderer(codexPet: codexPet, codogotchiPet: codogotchiPet, sink: { _ in })

		renderer.update(state: .implementing, visualMode: .normal)

		// P8.06: .implementing resolves from the lite sheet (8 frames) via CodogotchiPet first.
		let implementingFrames = codogotchiPet.frames(for: .implementing)
		XCTAssertEqual(
			renderer.currentFrameIndexForTesting,
			min(MenubarRenderer.heroFrameIndex, max(implementingFrames.count - 1, 0)),
			"state transition must land on the hero frame index (clamped to row length)"
		)
		XCTAssertEqual(
			renderer.currentFramesForTesting.count,
			implementingFrames.count,
			"renderer must hold the implementing row frame source"
		)

		// Second transition: .ticketCompleted resolves from CodogotchiPet SoA sheet (8 frames),
		// hero index (3) is well within bounds.
		renderer.update(state: .ticketCompleted, visualMode: .normal)
		XCTAssertEqual(renderer.currentStateForTesting, .ticketCompleted)
		XCTAssertEqual(
			renderer.currentFrameIndexForTesting,
			MenubarRenderer.heroFrameIndex,
			"every state transition must land on the hero frame, not just the first"
		)
		XCTAssertEqual(
			renderer.currentFramesForTesting.count,
			codogotchiPet.frames(for: .ticketCompleted).count,
			"ticketCompleted must resolve from the codogotchi sheet"
		)
	}

	func testUpdateWithUnchangedStateAndModeDoesNotRepaint() throws {
		var paintCount = 0
		let renderer = try makeRenderer { _ in paintCount += 1 }

		renderer.update(state: .implementing, visualMode: .normal)
		let paintsAfterFirstChange = paintCount
		XCTAssertGreaterThan(
			paintsAfterFirstChange,
			0,
			"sanity: first update with a real state must paint"
		)

		// Subsequent updates with identical inputs (the 1 Hz polling case)
		// must be no-ops; the menubar is static between state/mode changes.
		renderer.update(state: .implementing, visualMode: .normal)
		renderer.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(
			paintCount,
			paintsAfterFirstChange,
			"unchanged (state, mode) updates must not repaint"
		)

		// A real state change repaints exactly once.
		renderer.update(state: .testing, visualMode: .normal)
		XCTAssertEqual(
			paintCount,
			paintsAfterFirstChange + 1,
			"state change must trigger exactly one repaint"
		)

		// A visual-mode change with the same state repaints exactly once.
		renderer.update(state: .testing, visualMode: .desaturated)
		XCTAssertEqual(
			paintCount,
			paintsAfterFirstChange + 2,
			"visual-mode change must trigger exactly one repaint"
		)
	}

	func testInitialIdleUpdatePaintsEvenWhenStateMatchesDefault() throws {
		var paintCount = 0
		let renderer = try makeRenderer { _ in paintCount += 1 }

		// The renderer's default state is `.idle`. The first `update(.idle, .normal)`
		// must still paint so the placeholder pawprint icon is replaced.
		renderer.update(state: .idle, visualMode: .normal)
		XCTAssertEqual(
			paintCount,
			1,
			"first update after init must paint, even when state matches the default"
		)

		renderer.update(state: .idle, visualMode: .normal)
		XCTAssertEqual(
			paintCount,
			1,
			"second identical update must be a no-op"
		)
	}

	// MARK: - Composite resolution (P8.06: CodogotchiPet first, Codex fallback)

	func testCompositeResolutionThinkingUsesLiteSheet() throws {
		let codexPet = try makeCodexPet()
		let codogotchiPet = try makeCodogotchiPet()
		let renderer = try MenubarRenderer(codexPet: codexPet, codogotchiPet: codogotchiPet, sink: { _ in })

		renderer.update(state: .thinking, visualMode: .normal)

		XCTAssertEqual(
			renderer.currentFramesForTesting.count,
			codogotchiPet.frames(for: .thinking).count,
			".thinking is in liteBasicRowMap — must resolve from lite-basic sheet (CodogotchiPet first)"
		)
		XCTAssertEqual(
			renderer.currentFramesForTesting.count, 8,
			".thinking lite sheet must return 8 frames"
		)
	}

	func testCompositeResolutionAdversarialReviewUsesSoaSheet() throws {
		let codexPet = try makeCodexPet()
		let codogotchiPet = try makeCodogotchiPet()
		let renderer = try MenubarRenderer(codexPet: codexPet, codogotchiPet: codogotchiPet, sink: { _ in })

		renderer.update(state: .adversarialReview, visualMode: .normal)

		XCTAssertEqual(
			renderer.currentFramesForTesting.count,
			codogotchiPet.frames(for: .adversarialReview).count,
			".adversarialReview is in soaRowMap — must resolve from SoA sheet"
		)
		XCTAssertEqual(
			renderer.currentFramesForTesting.count, 8,
			"SoA sheet frames for .adversarialReview must be 8"
		)
	}

	// MARK: - Desaturation

	func testDesaturatedModeProducesGrayscalePixels() throws {
		var lastImage: NSImage?
		let renderer = try makeRenderer { image in
			lastImage = image
		}

		renderer.update(state: .idle, visualMode: .desaturated)

		let image = try XCTUnwrap(lastImage, "renderer must emit a frame after update")
		let cg = try XCTUnwrap(
			image.cgImage(forProposedRect: nil, context: nil, hints: nil),
			"emitted image must back to a CGImage for pixel sampling"
		)

		let samples = sampleOpaquePixels(in: cg, maxSamples: 32)
		XCTAssertFalse(
			samples.isEmpty,
			"fixture frame must contain at least one opaque pixel to sample"
		)
		for (r, g, b) in samples {
			XCTAssertEqual(
				Int(r),
				Int(g),
				accuracy: 2,
				"desaturated pixel R(\(r)) and G(\(g)) must match within tolerance"
			)
			XCTAssertEqual(
				Int(g),
				Int(b),
				accuracy: 2,
				"desaturated pixel G(\(g)) and B(\(b)) must match within tolerance"
			)
		}
	}

	// MARK: - Static mode

	func testStaticModeSuppressesSinkOnUpdate() throws {
		var sinkCallCount = 0
		let renderer = try makeRenderer(sink: { _ in sinkCallCount += 1 })
		renderer.setStaticMode()
		sinkCallCount = 0
		renderer.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(
			sinkCallCount, 0,
			"update must not call sink when static mode is active"
		)
	}

	func testStaticModeDoesNotBlockReplacePets() throws {
		var sinkCallCount = 0
		let renderer = try makeRenderer(sink: { _ in sinkCallCount += 1 })
		renderer.setStaticMode()
		sinkCallCount = 0
		renderer.replacePets(codexPet: try makeCodexPet(), codogotchiPet: try makeCodogotchiPet())
		XCTAssertEqual(
			sinkCallCount, 0,
			"replacePets must also not call sink when static mode is active"
		)
	}

	// MARK: - Pixel sampling helper

	/// Draw `cg` into a normalized 32-bit RGBA buffer and return up to
	/// `maxSamples` pixels with alpha > 0.
	private func sampleOpaquePixels(
		in cg: CGImage,
		maxSamples: Int,
	) -> [(UInt8, UInt8, UInt8)] {
		let width = cg.width
		let height = cg.height
		guard width > 0, height > 0 else { return [] }

		let bytesPerPixel = 4
		let bytesPerRow = width * bytesPerPixel
		var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo =
			CGImageAlphaInfo.premultipliedLast.rawValue
			| CGBitmapInfo.byteOrder32Big.rawValue
		guard
			let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
				guard let base = raw.baseAddress else { return nil }
				return CGContext(
					data: base,
					width: width,
					height: height,
					bitsPerComponent: 8,
					bytesPerRow: bytesPerRow,
					space: colorSpace,
					bitmapInfo: bitmapInfo,
				)
			})
		else {
			return []
		}
		context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

		var out: [(UInt8, UInt8, UInt8)] = []
		out.reserveCapacity(maxSamples)
		let stepX = max(1, width / 8)
		let stepY = max(1, height / 8)
		for y in stride(from: 0, to: height, by: stepY) {
			for x in stride(from: 0, to: width, by: stepX) {
				let offset = (y * width + x) * bytesPerPixel
				let alpha = buffer[offset + 3]
				if alpha > 0 {
					out.append((buffer[offset], buffer[offset + 1], buffer[offset + 2]))
					if out.count >= maxSamples { return out }
				}
			}
		}
		return out
	}
}

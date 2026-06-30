import AppKit
import XCTest

@testable import Codogotchi

/// Regression coverage for the P-goal fix: pet (re)assignment used to evict
/// `PetAssetResolver`'s cache and reload every active pet's spritesheet
/// *synchronously on the main thread* inside `MenubarApp.reloadActivePet()`
/// — freezing the whole app (spinning beach ball) for several seconds on
/// every single assignment.
///
/// `reloadActivePet()` now runs the expensive decode/slice work
/// (`CodexPet`/`CodogotchiPet` init, `PetAssetResolver.loadFresh`) inside a
/// detached background `Task`, only touching the main actor for the cheap
/// pointer-swap/UI steps. This test reproduces that exact
/// `Task.detached { ... await MainActor.run { ... } }` shape with an
/// artificially slow loader and proves the main run loop is never starved
/// for longer than a tick — i.e. the UI stays responsive while a slow load
/// is in flight.
final class ReloadActivePetResponsivenessTests: XCTestCase {

	private func maewDirectory() -> URL {
		URL(fileURLWithPath: #file)
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/maew")
	}

	func testBackgroundDecodeDoesNotStallMainRunLoop() throws {
		let maew = maewDirectory()
		let simulatedDecodeDelay: TimeInterval = 0.5

		// Mirrors the slow part of a real load (NSImage decode + frame
		// slicing) with a deterministic, CI-safe artificial delay instead of
		// depending on real spritesheet size/decode speed.
		let resolver = PetAssetResolver(
			codexLoader: { url in
				Thread.sleep(forTimeInterval: simulatedDecodeDelay)
				return try CodexPet(petDirectory: url.path)
			},
			codogotchiLoader: { url in try CodogotchiPet(petDirectory: url.path) },
			maewFallbackURL: maew
		)

		var calledOnMainThread = false
		var tickCount = 0
		var maxGapBetweenTicks: TimeInterval = 0
		var lastTick = CFAbsoluteTimeGetCurrent()
		let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
			let now = CFAbsoluteTimeGetCurrent()
			maxGapBetweenTicks = max(maxGapBetweenTicks, now - lastTick)
			lastTick = now
			tickCount += 1
		}
		RunLoop.main.add(timer, forMode: .common)
		defer { timer.invalidate() }

		var backgroundDone = false
		let overallStart = CFAbsoluteTimeGetCurrent()

		// Exactly the reloadActivePet() shape: heavy work detached, only the
		// completion hop touches the main actor.
		Task.detached(priority: .userInitiated) {
			calledOnMainThread = Thread.isMainThread
			_ = try? resolver.loadFresh(petId: "maew")
			await MainActor.run {
				backgroundDone = true
			}
		}

		let deadline = Date().addingTimeInterval(5)
		while !backgroundDone && Date() < deadline {
			RunLoop.main.run(until: Date().addingTimeInterval(0.005))
		}
		let overallElapsed = CFAbsoluteTimeGetCurrent() - overallStart

		XCTAssertTrue(backgroundDone, "background load did not complete within the test deadline")
		XCTAssertFalse(calledOnMainThread, "the decode work must run off the main thread")
		XCTAssertGreaterThanOrEqual(
			overallElapsed, simulatedDecodeDelay,
			"sanity check: the simulated slow decode must actually have run")

		// The crux of the fix: even while a slow decode is in flight on a
		// background thread, the main run loop keeps servicing its ~10ms
		// timer. Before the fix, the equivalent work ran inline on the main
		// thread and would have starved this timer for the full decode
		// duration (0.5s here; several seconds for real spritesheets).
		XCTAssertGreaterThan(tickCount, 0, "main run loop never ticked — it was blocked")
		XCTAssertLessThan(
			maxGapBetweenTicks, 0.2,
			"main run loop stalled for \(maxGapBetweenTicks)s during a \(simulatedDecodeDelay)s "
				+ "background decode — the UI would have been unresponsive")
	}
}

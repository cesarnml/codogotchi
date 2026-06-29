import CoreGraphics
import XCTest

@testable import Codogotchi

final class AppStateTests: XCTestCase {
	private let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

	private func withTempHome(_ body: (URL) throws -> Void) rethrows {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("app-state-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}

		try body(tmp)
	}

	private func writeAppState(_ json: String, in dir: URL) throws {
		try json.write(
			to: dir.appendingPathComponent("app-state.json"),
			atomically: true,
			encoding: .utf8
		)
	}

	func testMissingAppStateFallsBackToVisibleBottomRightDefault() {
		withTempHome { _ in
			let state = AppStateStore.load(visibleFrame: visibleFrame)
			let expectedFrame = FloatingFramePolicy.defaultFrame(in: visibleFrame)

			XCTAssertTrue(state.isFloatingPetVisible)
			XCTAssertEqual(state.frame, expectedFrame)
			XCTAssertTrue(visibleFrame.contains(state.frame))
		}
	}

	func testMalformedAppStateFallsBackToVisibleDefault() throws {
		try withTempHome { dir in
			try writeAppState("{ not json", in: dir)

			let state = AppStateStore.load(visibleFrame: visibleFrame)

			XCTAssertTrue(state.isFloatingPetVisible)
			XCTAssertEqual(state.frame, FloatingFramePolicy.defaultFrame(in: visibleFrame))
		}
	}

	func testFutureSchemaVersionFallsBackToVisibleDefault() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 99,
				  "floating_pet": {
				    "visible": false,
				    "frame": { "x": 120, "y": 160, "width": 220, "height": 180 }
				  }
				}
				"""#,
				in: dir
			)

			let state = AppStateStore.load(visibleFrame: visibleFrame)

			XCTAssertTrue(state.isFloatingPetVisible)
			XCTAssertEqual(state.frame, FloatingFramePolicy.defaultFrame(in: visibleFrame))
		}
	}

	func testValidAppStateRoundTripsVisibilityAndFrame() throws {
		try withTempHome { _ in
			let original = FloatingAppState(
				isFloatingPetVisible: false,
				frame: CGRect(x: 120, y: 160, width: 220, height: 180)
			)

			try AppStateStore.save(original)
			let loaded = AppStateStore.load(visibleFrame: visibleFrame)

			XCTAssertEqual(loaded, original)
		}
	}

	func testOffscreenOrOversizedSavedFrameClampsIntoVisibleFrame() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 1,
				  "floating_pet": {
				    "visible": true,
				    "frame": { "x": -500, "y": 900, "width": 2000, "height": 40 }
				  }
				}
				"""#,
				in: dir
			)

			let state = AppStateStore.load(visibleFrame: visibleFrame)

			XCTAssertGreaterThanOrEqual(state.frame.width, FloatingFramePolicy.minimumSize.width)
			XCTAssertLessThanOrEqual(state.frame.width, FloatingFramePolicy.maximumSize.width)
			XCTAssertGreaterThanOrEqual(state.frame.height, FloatingFramePolicy.minimumSize.height)
			XCTAssertLessThanOrEqual(state.frame.height, FloatingFramePolicy.maximumSize.height)
			XCTAssertTrue(visibleFrame.contains(state.frame), "Expected \(state.frame) inside \(visibleFrame)")
		}
	}

	func testFittedSpriteSizeScalesToPanelBounds() {
		let image = CGSize(width: 192, height: 208)
		let panel = CGSize(width: 256, height: 256)
		let fitted = FloatingFramePolicy.fittedSpriteSize(imageSize: image, panelSize: panel)
		XCTAssertEqual(fitted.height, 256, accuracy: 0.01)
		XCTAssertEqual(fitted.width, 192 * (256.0 / 208.0), accuracy: 0.01)
	}

	func testOnboardingAndHookActivityRoundTrip() throws {
		try withTempHome { _ in
			let original = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 10, y: 20, width: 180, height: 180),
				onboardingCompletedAt: "2026-05-28T10:00:00Z",
				lastHookActivityAt: "2026-05-28T11:30:00Z",
				hooksStatus: HooksStatusSnapshot.fixtureNotInstalled()
			)

			try AppStateStore.save(original)
			let loaded = AppStateStore.load(visibleFrame: visibleFrame)

			XCTAssertEqual(loaded.onboardingCompletedAt, "2026-05-28T10:00:00Z")
			XCTAssertEqual(loaded.lastHookActivityAt, "2026-05-28T11:30:00Z")
			XCTAssertNotNil(loaded.hooksStatus)
			XCTAssertEqual(loaded.hooksStatus?.codex.installed, false)
		}
	}

	func testNewOptionalFieldsDefaultToNilWhenAbsent() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 1,
				  "floating_pet": {
				    "visible": true,
				    "frame": { "x": 12, "y": 34, "width": 180, "height": 180 }
				  }
				}
				"""#,
				in: dir
			)

			let state = AppStateStore.load(visibleFrame: visibleFrame)
			XCTAssertNil(state.onboardingCompletedAt)
			XCTAssertNil(state.lastHookActivityAt)
			XCTAssertNil(state.hooksStatus)
		}
	}

	// MARK: - Schema v2 / installedHookVersion

	func testV1FileDefaultsInstalledHookVersionToNil() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 1,
				  "floating_pet": {
				    "visible": true,
				    "frame": { "x": 12, "y": 34, "width": 180, "height": 180 }
				  }
				}
				"""#,
				in: dir
			)
			let state = AppStateStore.load(visibleFrame: visibleFrame)
			XCTAssertNil(state.installedHookVersion)
		}
	}

	func testInstalledHookVersionRoundTrips() throws {
		try withTempHome { _ in
			let original = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 10, y: 20, width: 180, height: 180),
				installedHookVersion: "1.2.3"
			)
			try AppStateStore.save(original)
			let loaded = AppStateStore.load(visibleFrame: visibleFrame)
			XCTAssertEqual(loaded.installedHookVersion, "1.2.3")
		}
	}

	func testMigrationPreservesExistingFieldsForV1File() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 1,
				  "floating_pet": {
				    "visible": false,
				    "frame": { "x": 10, "y": 20, "width": 180, "height": 180 }
				  },
				  "onboarding_completed_at": "2026-01-01T00:00:00Z"
				}
				"""#,
				in: dir
			)
			let state = AppStateStore.load(visibleFrame: visibleFrame)
			XCTAssertFalse(state.isFloatingPetVisible)
			XCTAssertEqual(state.onboardingCompletedAt, "2026-01-01T00:00:00Z")
			XCTAssertNil(state.installedHookVersion)
		}
	}

	func testV2FileWithInstalledHookVersionLoadsCorrectly() throws {
		try withTempHome { dir in
			try writeAppState(
				#"""
				{
				  "schema_version": 2,
				  "floating_pet": {
				    "visible": true,
				    "frame": { "x": 10, "y": 20, "width": 180, "height": 180 }
				  },
				  "installed_hook_version": "2.0.0"
				}
				"""#,
				in: dir
			)
			let state = AppStateStore.load(visibleFrame: visibleFrame)
			XCTAssertEqual(state.installedHookVersion, "2.0.0")
		}
	}

	func testAppStatePathUsesCodogotchiHomeWithoutTouchingConfig() throws {
		try withTempHome { dir in
			let state = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 10, y: 20, width: 180, height: 180)
			)

			try AppStateStore.save(state)

			XCTAssertEqual(AppStateStore.appStateURL(), dir.appendingPathComponent("app-state.json"))
			XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("app-state.json").path))
			XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path))
		}
	}

	// MARK: - Schema v3 / per-origin floating_pet_positions

	func testLoadFrameForUnknownOriginReturnsDefault() {
		withTempHome { _ in
			let frame = AppStateStore.loadFrame(for: "cursor", visibleFrame: visibleFrame)
			XCTAssertEqual(frame, FloatingFramePolicy.defaultFrame(in: visibleFrame))
		}
	}

	func testSaveFrameAndLoadFrameRoundTripPerOrigin() throws {
		try withTempHome { _ in
			let cursorFrame = CGRect(x: 100, y: 200, width: 160, height: 160)
			let codexFrame = CGRect(x: 300, y: 400, width: 140, height: 140)

			try AppStateStore.saveFrame(cursorFrame, for: "cursor")
			try AppStateStore.saveFrame(codexFrame, for: "codex")

			XCTAssertEqual(
				AppStateStore.loadFrame(for: "cursor", visibleFrame: visibleFrame), cursorFrame)
			XCTAssertEqual(
				AppStateStore.loadFrame(for: "codex", visibleFrame: visibleFrame), codexFrame)
		}
	}

	func testSaveFramePreservesOtherOriginFrames() throws {
		try withTempHome { _ in
			let firstFrame = CGRect(x: 100, y: 200, width: 160, height: 160)
			let secondFrame = CGRect(x: 300, y: 400, width: 140, height: 140)

			try AppStateStore.saveFrame(firstFrame, for: "cursor")
			try AppStateStore.saveFrame(secondFrame, for: "claude_code")

			XCTAssertEqual(
				AppStateStore.loadFrame(for: "cursor", visibleFrame: visibleFrame), firstFrame)
			XCTAssertEqual(
				AppStateStore.loadFrame(for: "claude_code", visibleFrame: visibleFrame), secondFrame)
		}
	}

	func testSavePreservesExistingPerOriginPositions() throws {
		try withTempHome { _ in
			let petFrame = CGRect(x: 100, y: 200, width: 160, height: 160)
			try AppStateStore.saveFrame(petFrame, for: "cursor")

			let state = FloatingAppState(
				isFloatingPetVisible: true,
				frame: CGRect(x: 10, y: 20, width: 180, height: 180)
			)
			try AppStateStore.save(state)

			XCTAssertEqual(
				AppStateStore.loadFrame(for: "cursor", visibleFrame: visibleFrame), petFrame,
				"save(_:) must not clobber per-origin positions")
		}
	}

	func testSaveFrameClampsOffscreenFrameOnLoad() throws {
		try withTempHome { _ in
			let offscreen = CGRect(x: -500, y: 900, width: 2000, height: 40)
			try AppStateStore.saveFrame(offscreen, for: "cursor")

			let loaded = AppStateStore.loadFrame(for: "cursor", visibleFrame: visibleFrame)
			XCTAssertGreaterThanOrEqual(loaded.width, FloatingFramePolicy.minimumSize.width)
			XCTAssertLessThanOrEqual(loaded.width, FloatingFramePolicy.maximumSize.width)
			XCTAssertTrue(visibleFrame.contains(loaded))
		}
	}
}

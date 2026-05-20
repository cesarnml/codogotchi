import XCTest

@testable import Menubar

/// Behavior contract for `StateJsonReader`.
///
/// Fixtures live in `apps/menubar/Fixtures/state-json/` and are resolved via
/// `#file` so the tests run cleanly under `xcodebuild ... test` without
/// needing the test bundle to embed the fixture folder. The renderer never
/// loads fixtures at runtime, so the test bundle does not need them either.
final class StateJsonReaderTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func fixtureURL(_ name: String) -> URL {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/state-json")
			.appendingPathComponent(name)
	}

	// MARK: - Floor states

	func testIdleFixtureParsesToIdle() {
		let result = StateJsonReader.read(at: fixtureURL("idle.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
		XCTAssertEqual(snapshot.schemaVersion, 1)
	}

	func testImplementingFixtureParsesToImplementing() {
		let result = StateJsonReader.read(at: fixtureURL("implementing.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .implementing)
	}

	func testRunningTestsFixtureParsesToRunningTests() {
		let result = StateJsonReader.read(at: fixtureURL("running-tests.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .runningTests)
	}

	func testCelebratingFixtureParsesToCelebrating() {
		let result = StateJsonReader.read(at: fixtureURL("celebrating.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .celebrating)
	}

	// MARK: - Unknown-state fallback

	func testUnknownActivityStateFallsBackToIdle() {
		let result = StateJsonReader.read(at: fixtureURL("unknown-state.json").path)
		guard case .success(let snapshot) = result else {
			XCTFail("expected success, got \(result)")
			return
		}
		XCTAssertEqual(snapshot.activityState, .idle)
	}

	// MARK: - Schema policy

	func testNewerSchemaVersionFailsWithSchemaNewer() {
		let result = StateJsonReader.read(at: fixtureURL("schema-newer.json").path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .schemaNewer(let got, let expected) = error else {
			XCTFail("expected schemaNewer, got \(error)")
			return
		}
		XCTAssertEqual(got, 99)
		XCTAssertEqual(expected, 1)
	}

	func testMissingFileReturnsFileNotFound() {
		let result = StateJsonReader.read(
			at: fixtureURL("does-not-exist.json").path
		)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .fileNotFound = error else {
			XCTFail("expected fileNotFound, got \(error)")
			return
		}
	}

	func testMalformedJsonReturnsMalformed() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("malformed-\(UUID().uuidString).json")
		try "{ not json".write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let result = StateJsonReader.read(at: tmp.path)
		guard case .failure(let error) = result else {
			XCTFail("expected failure, got \(result)")
			return
		}
		guard case .malformed = error else {
			XCTFail("expected malformed, got \(error)")
			return
		}
	}
}

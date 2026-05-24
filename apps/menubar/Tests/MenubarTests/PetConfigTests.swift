import XCTest

@testable import Menubar

/// Behavior contract for `PetConfig.resolvedPetName()` — reads `~/.codogotchi/config.json`
/// (or `$CODOGOTCHI_HOME/config.json`) and returns the `pet` key value, falling back
/// to `"maew"` on any read/parse failure.
final class PetConfigTests: XCTestCase {
	// MARK: - Helpers

	private func withTempHome(_ body: (URL) throws -> Void) rethrows {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("pet-config-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}
		try body(tmp)
	}

	private func writeConfig(_ json: String, in dir: URL) throws {
		try json.write(
			to: dir.appendingPathComponent("config.json"),
			atomically: true, encoding: .utf8)
	}

	// MARK: - Default fallback

	func testNoConfigFileFallsBackToMaew() {
		withTempHome { _ in
			// CODOGOTCHI_HOME set to a dir without config.json — must return default.
			XCTAssertEqual(PetConfig.resolvedPetName(), DEFAULT_PET_NAME)
			XCTAssertEqual(PetConfig.resolvedPetName(), "maew")
		}
	}

	// MARK: - Happy path

	func testConfigWithPetKeyReturnsResolvedName() throws {
		try withTempHome { dir in
			try writeConfig(#"{"pet": "alice"}"#, in: dir)
			XCTAssertEqual(PetConfig.resolvedPetName(), "alice")
		}
	}

	// MARK: - Soft degradation

	func testMalformedJsonFallsBackToMaew() throws {
		try withTempHome { dir in
			try writeConfig("{ not valid json }", in: dir)
			XCTAssertEqual(PetConfig.resolvedPetName(), DEFAULT_PET_NAME)
		}
	}

	func testMissingPetKeyFallsBackToMaew() throws {
		try withTempHome { dir in
			try writeConfig("{}", in: dir)
			XCTAssertEqual(PetConfig.resolvedPetName(), DEFAULT_PET_NAME)
		}
	}

	// MARK: - CODOGOTCHI_HOME override

	func testCodogotchiHomeOverridesConfigPath() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("pet-config-home-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let configData = #"{"pet": "bobby"}"#
		try configData.write(
			to: tmp.appendingPathComponent("config.json"),
			atomically: true, encoding: .utf8)

		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}

		XCTAssertEqual(PetConfig.resolvedPetName(), "bobby")
	}

	// MARK: - Loader directory paths

	func testMaliPetDefaultPathUsesResolvedPetName() throws {
		try withTempHome { dir in
			try writeConfig(#"{"pet": "charlie"}"#, in: dir)
			XCTAssertTrue(
				MaliPet.defaultPetDirectoryPath().hasSuffix("/charlie"),
				"MaliPet default path must use resolved pet name, got: \(MaliPet.defaultPetDirectoryPath())"
			)
		}
	}

	func testCodogotchiPetDefaultPathUsesResolvedPetName() throws {
		try withTempHome { dir in
			try writeConfig(#"{"pet": "charlie"}"#, in: dir)
			XCTAssertTrue(
				CodogotchiPet.defaultPetDirectoryPath().hasSuffix("/charlie"),
				"CodogotchiPet default path must use resolved pet name, got: \(CodogotchiPet.defaultPetDirectoryPath())"
			)
		}
	}
}

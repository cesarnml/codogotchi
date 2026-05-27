import XCTest

@testable import Codogotchi

// MARK: - PetStoreSeeder

final class PetStoreSeederTests: XCTestCase {
	// MARK: - Helpers

	/// Path to Fixtures/maew via the test file's location.
	private func maewFixtureDirectory() -> URL {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/maew")
	}

	private func makeTempDir() -> URL {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-seed-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		return tmp
	}

	// MARK: - isCanonicalStoreComplete

	func testStoreCompleteReturnsFalseWhenDirectoryMissing() {
		let missing = "/tmp/codogotchi-no-such-dir-\(UUID().uuidString)"
		XCTAssertFalse(PetStoreSeeder.isCanonicalStoreComplete(at: missing))
	}

	func testStoreCompleteReturnsFalseWhenAssetsMissing() throws {
		let tmp = makeTempDir()
		defer { try? FileManager.default.removeItem(at: tmp) }
		// Directory exists but no asset files.
		XCTAssertFalse(PetStoreSeeder.isCanonicalStoreComplete(at: tmp.path))
	}

	func testStoreCompleteReturnsTrueWhenAllRequiredAssetsPresent() throws {
		let tmp = makeTempDir()
		defer { try? FileManager.default.removeItem(at: tmp) }
		for asset in PetStoreSeeder.requiredAssets {
			let data = Data("placeholder".utf8)
			try data.write(to: tmp.appendingPathComponent(asset))
		}
		XCTAssertTrue(PetStoreSeeder.isCanonicalStoreComplete(at: tmp.path))
	}

	func testStoreCompleteReturnsFalseWhenOnlyPartialAssetsPresent() throws {
		let tmp = makeTempDir()
		defer { try? FileManager.default.removeItem(at: tmp) }
		// Write only the first required asset — incomplete store.
		let asset = PetStoreSeeder.requiredAssets[0]
		try Data("x".utf8).write(to: tmp.appendingPathComponent(asset))
		XCTAssertFalse(PetStoreSeeder.isCanonicalStoreComplete(at: tmp.path))
	}

	// MARK: - seed

	func testSeedCopiesBothSpritesheets() throws {
		let dest = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dest) }
		let source = maewFixtureDirectory()

		try PetStoreSeeder.seed(from: source, into: dest.path)

		for asset in PetStoreSeeder.requiredAssets {
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: dest.appendingPathComponent(asset).path),
				"Expected asset '\(asset)' to be seeded into canonical store"
			)
		}
	}

	func testSeedCreatesMissingDestinationDirectory() throws {
		let dest = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-create-test-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: dest) }
		XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))

		try PetStoreSeeder.seed(from: maewFixtureDirectory(), into: dest.path)

		XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
	}

	func testSeedIsIdempotentExistingFilesNotOverwritten() throws {
		let dest = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dest) }
		let source = maewFixtureDirectory()

		// First seed.
		try PetStoreSeeder.seed(from: source, into: dest.path)

		// Overwrite one file with custom content.
		let sentinel = "sentinel-do-not-overwrite"
		let petJsonPath = dest.appendingPathComponent("pet.json")
		try Data(sentinel.utf8).write(to: petJsonPath)

		// Second seed must not overwrite the existing file.
		try PetStoreSeeder.seed(from: source, into: dest.path)

		let content = try String(contentsOf: petJsonPath, encoding: .utf8)
		XCTAssertEqual(content, sentinel, "Existing pet.json must not be overwritten on re-seed")
	}

	func testSeedStoreIsCompleteAfterSeed() throws {
		let dest = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dest) }

		try PetStoreSeeder.seed(from: maewFixtureDirectory(), into: dest.path)

		XCTAssertTrue(
			PetStoreSeeder.isCanonicalStoreComplete(at: dest.path),
			"Store must report complete after a successful seed"
		)
	}
}

// MARK: - Canonical pet paths

final class CanonicalPetPathTests: XCTestCase {
	private func withTempCodogotchiHome(_ body: (URL) throws -> Void) rethrows {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("codogotchi-path-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"]
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}
		try body(tmp)
	}

	// MARK: - CodexPet canonical default path

	func testCodexPetDefaultPathUsesCanonicalCodogotchiHome() {
		withTempCodogotchiHome { tmp in
			let path = CodexPet.defaultPetDirectoryPath()
			XCTAssertTrue(
				path.hasPrefix(tmp.path),
				"CodexPet.defaultPetDirectoryPath() must respect CODOGOTCHI_HOME — got: \(path)"
			)
		}
	}

	func testCodexPetDefaultPathDoesNotContainDotCodex() {
		withTempCodogotchiHome { _ in
			let path = CodexPet.defaultPetDirectoryPath()
			XCTAssertFalse(
				path.contains(".codex"),
				"CodexPet.defaultPetDirectoryPath() must not reference .codex — got: \(path)"
			)
		}
	}

	func testCodexPetDefaultPathContainsPets() {
		withTempCodogotchiHome { _ in
			let path = CodexPet.defaultPetDirectoryPath()
			XCTAssertTrue(
				path.contains("/pets/"),
				"CodexPet.defaultPetDirectoryPath() must contain /pets/ — got: \(path)"
			)
		}
	}

	// MARK: - Both loaders agree on canonical root

	func testCodexPetAndCodogotchiPetDefaultPathsShareSameRoot() {
		withTempCodogotchiHome { _ in
			let codexPath = CodexPet.defaultPetDirectoryPath()
			let codogotchiPath = CodogotchiPet.defaultPetDirectoryPath()
			// Both must share the same directory (same canonical store).
			XCTAssertEqual(
				codexPath, codogotchiPath,
				"CodexPet and CodogotchiPet must resolve to the same default pet directory"
			)
		}
	}

	// MARK: - Both loaders succeed from seeded canonical store

	func testBothLoadersSucceedFromSeededCanonicalStore() throws {
		let maewFixture = URL(fileURLWithPath: #file)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")

		try withTempCodogotchiHome { tmp in
			let petDir = tmp.appendingPathComponent("pets/maew")
			try FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true)
			try PetStoreSeeder.seed(from: maewFixture, into: petDir.path)

			// CodexPet must load the Codex 8×9 sheet from the canonical store.
			XCTAssertNoThrow(
				try CodexPet(petDirectory: petDir.path),
				"CodexPet must load from seeded canonical store"
			)

			// CodogotchiPet must load (or soft-degrade if sheet absent) from the canonical store.
			XCTAssertNoThrow(
				try CodogotchiPet(petDirectory: petDir.path),
				"CodogotchiPet must load from seeded canonical store"
			)
		}
	}

	// MARK: - Absence of ~/.codex/pets does not block loading

	func testNoCodexPetsDirDoesNotBlockCodexPetLoad() throws {
		// Under a fresh CODOGOTCHI_HOME with no ~/.codex, seeded canonical store
		// must be sufficient for CodexPet to load.
		let maewFixture = URL(fileURLWithPath: #file)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")

		try withTempCodogotchiHome { tmp in
			let petDir = tmp.appendingPathComponent("pets/maew")
			try FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true)
			try PetStoreSeeder.seed(from: maewFixture, into: petDir.path)

			// The canonical store must be sufficient — no ~/.codex/ dependency.
			let pet = try CodexPet(petDirectory: petDir.path)
			XCTAssertEqual(pet.id, "maew")
			XCTAssertFalse(pet.frames(for: .idle).isEmpty, "idle frames must be non-empty from seeded store")
		}
	}
}

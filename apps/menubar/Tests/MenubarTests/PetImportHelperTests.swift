import Foundation
import XCTest

@testable import Codogotchi

final class PetImportHelperTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("PetImportHelperTests-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - importPet

	func testImportCopiesAllFilesFromCodexToCanonical() throws {
		let source = tmp.appendingPathComponent("codex/pets/maew", isDirectory: true)
		try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
		let petFile = source.appendingPathComponent("pet.json")
		try Data("{}".utf8).write(to: petFile)
		let spriteFile = source.appendingPathComponent("spritesheet.webp")
		try Data("fakepng".utf8).write(to: spriteFile)

		let destination = tmp.appendingPathComponent("codogotchi/pets", isDirectory: true)
		let helper = PetImportHelper(
			codexPetsRoot: tmp.appendingPathComponent("codex/pets"),
			canonicalPetsRoot: destination
		)

		try helper.importPet(id: "maew")

		let destPet = destination.appendingPathComponent("maew")
		XCTAssertTrue(FileManager.default.fileExists(atPath: destPet.appendingPathComponent("pet.json").path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: destPet.appendingPathComponent("spritesheet.webp").path))
	}

	func testImportCreatesDestinationDirectoryWhenAbsent() throws {
		let source = tmp.appendingPathComponent("codex/pets/kitty", isDirectory: true)
		try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
		try Data("{}".utf8).write(to: source.appendingPathComponent("pet.json"))

		let destination = tmp.appendingPathComponent("codogotchi/pets", isDirectory: true)
		// destination does not exist yet
		XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

		let helper = PetImportHelper(
			codexPetsRoot: tmp.appendingPathComponent("codex/pets"),
			canonicalPetsRoot: destination
		)
		try helper.importPet(id: "kitty")

		XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("kitty").path))
	}

	func testImportThrowsWhenSourcePetNotFound() {
		let helper = PetImportHelper(
			codexPetsRoot: tmp.appendingPathComponent("codex/pets"),
			canonicalPetsRoot: tmp.appendingPathComponent("codogotchi/pets")
		)
		XCTAssertThrowsError(try helper.importPet(id: "nonexistent"))
	}

	// MARK: - availableCodexPets

	func testAvailableCodexPetsListsDirectories() throws {
		let petsRoot = tmp.appendingPathComponent("codex/pets", isDirectory: true)
		try FileManager.default.createDirectory(
			at: petsRoot.appendingPathComponent("alpha"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(
			at: petsRoot.appendingPathComponent("beta"), withIntermediateDirectories: true)
		// A plain file should not be listed as a pet
		try Data("x".utf8).write(to: petsRoot.appendingPathComponent("README.md"))

		let helper = PetImportHelper(
			codexPetsRoot: petsRoot,
			canonicalPetsRoot: tmp.appendingPathComponent("codogotchi/pets")
		)
		let pets = helper.availableCodexPets()
		XCTAssertEqual(Set(pets), ["alpha", "beta"])
	}

	func testAvailableCodexPetsReturnsEmptyWhenRootAbsent() {
		let helper = PetImportHelper(
			codexPetsRoot: tmp.appendingPathComponent("nonexistent/pets"),
			canonicalPetsRoot: tmp.appendingPathComponent("codogotchi/pets")
		)
		XCTAssertTrue(helper.availableCodexPets().isEmpty)
	}
}

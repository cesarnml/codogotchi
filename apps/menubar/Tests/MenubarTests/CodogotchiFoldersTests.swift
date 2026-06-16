import Foundation
import XCTest

@testable import Codogotchi

/// Canonical folder URLs (Developer "Open data folder" + Pet "Open pet folder")
/// and the create-then-reveal helper.
final class CodogotchiFoldersTests: XCTestCase {
	override func tearDown() {
		unsetenv("CODOGOTCHI_HOME")
		super.tearDown()
	}

	func testDataFolderURLPointsToDotCodogotchi() {
		unsetenv("CODOGOTCHI_HOME")
		XCTAssertTrue(CodogotchiFolders.dataFolderURL().path.hasSuffix("/.codogotchi"))
	}

	func testPetFolderURLPointsToCanonicalPets() {
		unsetenv("CODOGOTCHI_HOME")
		XCTAssertTrue(CodogotchiFolders.petFolderURL().path.hasSuffix("/.codogotchi/pets"))
	}

	func testDataFolderURLRespectsCodogotchiHome() {
		setenv("CODOGOTCHI_HOME", "/custom/home", 1)
		XCTAssertEqual(CodogotchiFolders.dataFolderURL().path, "/custom/home")
	}

	func testPetFolderURLRespectsCodogotchiHome() {
		setenv("CODOGOTCHI_HOME", "/custom/home", 1)
		XCTAssertEqual(CodogotchiFolders.petFolderURL().path, "/custom/home/pets")
	}

	func testRevealCreatesDirectoryThenOpensIt() {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("CodogotchiFoldersTests-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: tmp) }
		let target = tmp.appendingPathComponent("pets")
		XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

		var openedURLs: [URL] = []
		let ok = CodogotchiFolders.reveal(target, open: { openedURLs.append($0); return true })

		XCTAssertTrue(ok)
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: target.path),
			"reveal must create the folder before opening it")
		XCTAssertEqual(openedURLs, [target])
	}
}

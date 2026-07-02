import XCTest

@testable import Codogotchi

final class LegacyStateFileCleanupTests: XCTestCase {

	private func makeTmpDataFolder() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("legacy-cleanup-\(UUID().uuidString)", isDirectory: true)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func write(_ name: String, in dir: URL, contents: String = "{}") {
		try! contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	// MARK: - gate.json / delivery-context.json: unconditional deletion

	func testGateJsonAndDeliveryContextAreAlwaysDeletedWhenPresent() {
		let dir = makeTmpDataFolder()
		defer { try? FileManager.default.removeItem(at: dir) }
		write("gate.json", in: dir)
		write("delivery-context.json", in: dir)

		LegacyStateFileCleanup.run(dataFolderURL: dir)

		XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gate.json").path))
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("delivery-context.json").path))
	}

	func testGateJsonAndDeliveryContextAbsentIsANoOp() {
		let dir = makeTmpDataFolder()
		defer { try? FileManager.default.removeItem(at: dir) }

		// Must not throw or crash when neither file exists.
		LegacyStateFileCleanup.run(dataFolderURL: dir)

		XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gate.json").path))
	}

	// MARK: - state.json: gated on rpg-state.json's presence

	func testStateJsonIsDeletedWhenRpgStateJsonAlreadyExists() {
		let dir = makeTmpDataFolder()
		defer { try? FileManager.default.removeItem(at: dir) }
		write("state.json", in: dir)
		write("rpg-state.json", in: dir)

		LegacyStateFileCleanup.run(dataFolderURL: dir)

		XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
	}

	func testStateJsonSurvivesWhenRpgStateJsonHasNotMigratedYet() {
		let dir = makeTmpDataFolder()
		defer { try? FileManager.default.removeItem(at: dir) }
		write("state.json", in: dir, contents: #"{"level": 3, "half_hearts": 6}"#)
		// rpg-state.json deliberately absent — the CLI's seedRpgState migration
		// has not run yet and still needs state.json as its seed source.

		LegacyStateFileCleanup.run(dataFolderURL: dir)

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path),
			"state.json must survive until rpg-state.json proves the CLI migration has completed")
	}

	func testRunIsIdempotentAndSelfHealingAcrossRepeatedCalls() {
		let dir = makeTmpDataFolder()
		defer { try? FileManager.default.removeItem(at: dir) }
		write("gate.json", in: dir)
		write("state.json", in: dir)

		// First launch: hook hasn't migrated RPG state yet.
		LegacyStateFileCleanup.run(dataFolderURL: dir)
		XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gate.json").path))
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path),
			"state.json must still survive on this launch")

		// A hook event fires between launches and completes the migration.
		write("rpg-state.json", in: dir)

		// Second launch: cleanup must catch up without any special handling.
		LegacyStateFileCleanup.run(dataFolderURL: dir)
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path),
			"state.json must be cleaned up once rpg-state.json appears on a later launch")
	}
}

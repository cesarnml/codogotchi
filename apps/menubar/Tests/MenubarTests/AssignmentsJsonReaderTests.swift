import XCTest

@testable import Codogotchi

// [red] AssignmentsJsonReader, AssignmentsSnapshot, AssignmentsJsonWriter, and
// AssignmentsMigration do not exist yet — this file causes a compile error until
// the GREEN implementation is added.
final class AssignmentsJsonReaderTests: XCTestCase {

	// MARK: - Absent file → safe default

	func testAbsentFileReturnsSafeDefault() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("does-not-exist-assignments-\(UUID().uuidString).json")
		let snapshot = AssignmentsJsonReader.read(at: missing.path)
		XCTAssertEqual(snapshot.default, DEFAULT_PET_NAME)
		XCTAssertEqual(snapshot.platformOverrides, [:])
	}

	// MARK: - Malformed file → safe default

	func testMalformedFileReturnsSafeDefault() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("assignments-malformed-\(UUID().uuidString).json")
		try "not json {{{".write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = AssignmentsJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.default, DEFAULT_PET_NAME)
		XCTAssertEqual(snapshot.platformOverrides, [:])
	}

	// MARK: - Full file resolves overrides

	func testValidFileDecodesAllFields() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("assignments-valid-\(UUID().uuidString).json")
		let json = """
			{
			  "schema_version": 1,
			  "default": "maew",
			  "claude_code": "shiba",
			  "cursor": "neko"
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = AssignmentsJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.default, "maew")
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "shiba")
		XCTAssertEqual(snapshot.platformOverrides["cursor"], "neko")
	}

	// MARK: - Origin without override → resolves to default

	func testOriginWithoutOverrideResolvesToDefault() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("assignments-no-override-\(UUID().uuidString).json")
		let json = """
			{
			  "schema_version": 1,
			  "default": "maew",
			  "claude_code": "shiba"
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = AssignmentsJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.resolve(origin: "vscode"), "maew")
		XCTAssertEqual(snapshot.resolve(origin: "claude_code"), "shiba")
	}

	// MARK: - combined resolves to default

	func testCombinedResolvesToDefault() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("assignments-combined-\(UUID().uuidString).json")
		let json = """
			{
			  "schema_version": 1,
			  "default": "maew",
			  "claude_code": "shiba"
			}
			"""
		try json.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let snapshot = AssignmentsJsonReader.read(at: tmp.path)
		XCTAssertEqual(snapshot.resolve(origin: "combined"), "maew",
			"combined origin must always resolve to default")
	}
}

final class AssignmentsJsonWriterTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("AssignmentsWriterTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	private func assignmentsURL() -> URL {
		tmp.appendingPathComponent("assignments.json")
	}

	// MARK: - Uniqueness: assigning badge to new pet removes it from old holder

	func testAssigningBadgeRemovesItFromPriorHolder() throws {
		let url = assignmentsURL()
		// Seed initial state: pet-a holds claude_code
		try AssignmentsJsonWriter.write(badge: "default", petId: "pet-a", to: url)
		try AssignmentsJsonWriter.write(badge: "claude_code", petId: "pet-a", to: url)

		// Reassign claude_code to pet-b
		try AssignmentsJsonWriter.write(badge: "claude_code", petId: "pet-b", to: url)

		let snapshot = AssignmentsJsonReader.read(at: url.path)
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "pet-b",
			"claude_code badge must be held by pet-b after reassignment")
	}

	// MARK: - Reassigning default moves the badge

	func testReassigningDefaultMoves() throws {
		let url = assignmentsURL()
		try AssignmentsJsonWriter.write(badge: "default", petId: "maew", to: url)
		try AssignmentsJsonWriter.write(badge: "default", petId: "shiba", to: url)

		let snapshot = AssignmentsJsonReader.read(at: url.path)
		XCTAssertEqual(snapshot.default, "shiba",
			"default badge must move to shiba after reassignment")
	}

	// MARK: - Fresh file with non-default badge auto-seeds default

	func testFreshNonDefaultWriteSeedsDefault() throws {
		let url = assignmentsURL()
		try AssignmentsJsonWriter.write(badge: "claude_code", petId: "shiba", to: url)

		let snapshot = AssignmentsJsonReader.read(at: url.path)
		XCTAssertEqual(snapshot.default, DEFAULT_PET_NAME,
			"fresh non-default badge write must auto-seed default to DEFAULT_PET_NAME")
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "shiba",
			"fresh non-default badge write must persist the claude_code override")
	}

	// MARK: - Round-trip through reader

	func testWriteRoundTripsThroughReader() throws {
		let url = assignmentsURL()
		try AssignmentsJsonWriter.write(badge: "default", petId: "maew", to: url)
		try AssignmentsJsonWriter.write(badge: "claude_code", petId: "shiba", to: url)
		try AssignmentsJsonWriter.write(badge: "cursor", petId: "neko", to: url)

		let snapshot = AssignmentsJsonReader.read(at: url.path)
		XCTAssertEqual(snapshot.default, "maew")
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "shiba")
		XCTAssertEqual(snapshot.platformOverrides["cursor"], "neko")
	}
}

final class AssignmentsMigrationTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("AssignmentsMigrationTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Absent assignments.json + config.json with pet → seeds default

	func testAbsentAssignmentsWithConfigPetSeedsDefault() throws {
		let assignmentsURL = tmp.appendingPathComponent("assignments.json")
		let configURL = tmp.appendingPathComponent("config.json")
		let configJson = """
			{ "pet": "foocat", "features": { "rpg_enabled": true } }
			"""
		try configJson.write(to: configURL, atomically: true, encoding: .utf8)

		AssignmentsMigration.seedIfAbsent(assignmentsURL: assignmentsURL, configURL: configURL)

		let snapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
		XCTAssertEqual(snapshot.default, "foocat",
			"migration must seed default from config.pet when assignments.json is absent")
	}

	// MARK: - Absent both → seeds default: maew

	func testAbsentBothSeedsDefaultMaew() {
		let assignmentsURL = tmp.appendingPathComponent("assignments.json")
		let configURL = tmp.appendingPathComponent("config.json")

		AssignmentsMigration.seedIfAbsent(assignmentsURL: assignmentsURL, configURL: configURL)

		let snapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
		XCTAssertEqual(snapshot.default, DEFAULT_PET_NAME,
			"migration must seed default to maew when both files are absent")
	}

	// MARK: - Existing assignments.json is left untouched (idempotent)

	func testExistingAssignmentsUntouched() throws {
		let assignmentsURL = tmp.appendingPathComponent("assignments.json")
		let configURL = tmp.appendingPathComponent("config.json")
		let existingJson = """
			{
			  "schema_version": 1,
			  "default": "my-custom-pet",
			  "claude_code": "other-pet"
			}
			"""
		try existingJson.write(to: assignmentsURL, atomically: true, encoding: .utf8)

		let configJson = """
			{ "pet": "different-pet", "features": { "rpg_enabled": true } }
			"""
		try configJson.write(to: configURL, atomically: true, encoding: .utf8)

		AssignmentsMigration.seedIfAbsent(assignmentsURL: assignmentsURL, configURL: configURL)

		let snapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
		XCTAssertEqual(snapshot.default, "my-custom-pet",
			"existing assignments.json must not be overwritten (idempotent)")
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "other-pet")
	}
}

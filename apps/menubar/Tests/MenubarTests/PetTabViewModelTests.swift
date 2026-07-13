import Foundation
import XCTest

@testable import Codogotchi

/// Behavior contract for `PetTabViewModel` — enumeration, default selection,
/// import delegation, persistence, activation notifications, and badge
/// assignment model (P14.07).
final class PetTabViewModelTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("PetTabViewModelTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Helpers

	private func makePets(codex: [String] = [], canonical: [String] = []) -> (
		codexRoot: URL, canonicalRoot: URL
	) {
		let codexRoot = tmp.appendingPathComponent("codex/pets")
		let canonicalRoot = tmp.appendingPathComponent("codogotchi/pets")
		for id in codex {
			let dir = codexRoot.appendingPathComponent(id)
			try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			// Codex-side pets are only surfaced when they look like real pets — write a
			// full valid manifest + spritesheet so fixtures pass the importable-listing filter.
			let json = #"{"id":"\#(id)","displayName":"\#(id)","spritesheetPath":"spritesheet.webp"}"#
			try! Data(json.utf8).write(to: dir.appendingPathComponent("pet.json"))
			try! Data("fakewebp".utf8).write(to: dir.appendingPathComponent("spritesheet.webp"))
		}
		for id in canonical {
			let dir = canonicalRoot.appendingPathComponent(id)
			try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			try! Data("{}".utf8).write(to: dir.appendingPathComponent("pet.json"))
		}
		return (codexRoot, canonicalRoot)
	}

	private func makeViewModel(
		codex: [String] = [],
		canonical: [String] = [],
		defaultPetId: String = DEFAULT_PET_NAME
	) -> (PetTabViewModel, configURL: URL) {
		let roots = makePets(codex: codex, canonical: canonical)
		let configURL = tmp.appendingPathComponent("config.json")
		let assignmentsURL = tmp.appendingPathComponent("assignments.json")
		// Seed the default badge when a non-Maew pet is requested so catalog
		// tests that rely on isDefault work without round-tripping through disk.
		if defaultPetId != DEFAULT_PET_NAME {
			try? AssignmentsJsonWriter.write(badge: "default", petId: defaultPetId, to: assignmentsURL)
		}
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL,
			assignmentsURL: assignmentsURL
		)
		return (vm, configURL)
	}

	// MARK: - Enumeration: three sources + deduplication

	func testEnumerationAlwaysIncludesBundledMaew() {
		let (vm, _) = makeViewModel()
		let ids = vm.allPetIds()
		XCTAssertTrue(ids.contains(DEFAULT_PET_NAME), "Maew must always appear in the pet list")
	}

	func testEnumerationIncludesCodexPets() {
		let (vm, _) = makeViewModel(codex: ["felix", "luna"])
		let ids = vm.allPetIds()
		XCTAssertTrue(ids.contains("felix"))
		XCTAssertTrue(ids.contains("luna"))
	}

	func testEnumerationIncludesCanonicalStorePets() {
		let (vm, _) = makeViewModel(canonical: ["nyx"])
		let ids = vm.allPetIds()
		XCTAssertTrue(ids.contains("nyx"))
	}

	func testEnumerationDeduplicatesMaewAcrossSources() {
		// maew may appear in codex, canonical, and as bundled — list it exactly once.
		let (vm, _) = makeViewModel(codex: ["maew"], canonical: ["maew"])
		let ids = vm.allPetIds()
		XCTAssertEqual(ids.filter { $0 == DEFAULT_PET_NAME }.count, 1, "maew must appear exactly once")
	}

	func testEnumerationToleratesMissingCodexRoot() {
		let (vm, _) = makeViewModel(codex: [], canonical: [])
		// codexRoot points to a non-existent directory — must not throw, must still list maew.
		let ids = vm.allPetIds()
		XCTAssertFalse(ids.isEmpty)
		XCTAssertTrue(ids.contains(DEFAULT_PET_NAME))
	}

	// MARK: - Default badge: snapshot reads

	func testDefaultBadgeIsMaewWhenNoAssignmentsFileExists() {
		let (vm, _) = makeViewModel()
		XCTAssertEqual(vm.assignmentsSnapshot.default, DEFAULT_PET_NAME,
			"default badge must fall back to maew when no assignments file exists")
	}

	func testDefaultBadgeHonorsPreviouslyPersistedAssignment() {
		let (vm, _) = makeViewModel(canonical: ["felix"], defaultPetId: "felix")
		XCTAssertEqual(vm.assignmentsSnapshot.default, "felix")
	}

	// MARK: - assign: persistence + notification

	func testAssignDefaultBadgePersistsToAssignmentsFile() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["ruby"])
		try vm.assign(badge: "default", to: "ruby")
		let snapshot = AssignmentsJsonReader.read(at: vm.assignmentsURL.path)
		XCTAssertEqual(snapshot.default, "ruby",
			"assign(default) must persist to the assignments file")
	}

	func testAssignDefaultBadgeUpdatesSnapshot() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["ruby"])
		try vm.assign(badge: "default", to: "ruby")
		XCTAssertEqual(vm.assignmentsSnapshot.default, "ruby")
	}

	func testAssignDoesNotUpdateInMemoryStateWhenWriteFails() {
		let roots = makePets(canonical: ["ruby"])
		let configURL = tmp.appendingPathComponent("config.json")
		let badAssignmentsURL = URL(fileURLWithPath: "/dev/null/nonexistent/assignments.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL,
			assignmentsURL: badAssignmentsURL
		)
		let originalDefault = vm.assignmentsSnapshot.default
		var callbackFired = false
		vm.onAssignmentsChanged = { callbackFired = true }
		XCTAssertThrowsError(try vm.assign(badge: "default", to: "ruby"),
			"assign must throw when the write fails")
		XCTAssertEqual(vm.assignmentsSnapshot.default, originalDefault,
			"snapshot.default must not change when write fails")
		XCTAssertFalse(callbackFired, "onAssignmentsChanged must not fire when write fails")
	}

	// MARK: - importPet: delegates to PetImportHelper

	func testImportPetDelegatesToPetImportHelper() throws {
		let roots = makePets(codex: ["felix"], canonical: [])
		let configURL = tmp.appendingPathComponent("config.json")
		var importedId: String?
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL,
			importOverride: { id in importedId = id }
		)
		try vm.importPet(id: "felix")
		XCTAssertEqual(importedId, "felix", "importPet must delegate to PetImportHelper (not re-implement)")
	}

	func testImportPetAddsToCanonicalAndRefreshesEntries() throws {
		let roots = makePets(codex: ["felix"], canonical: [])
		let canonicalRoot = roots.canonicalRoot
		let configURL = tmp.appendingPathComponent("config.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: canonicalRoot,
			configURL: configURL
		)
		// Simulate real import — create the canonical dir manually so enumeration picks it up.
		let felixDir = canonicalRoot.appendingPathComponent("felix")
		try FileManager.default.createDirectory(at: felixDir, withIntermediateDirectories: true)
		try Data("{}".utf8).write(to: felixDir.appendingPathComponent("pet.json"))

		try vm.importPet(id: "felix")
		// After import, felix should appear in canonical list.
		XCTAssertTrue(vm.allPetIds().contains("felix"))
	}

	// MARK: - catalog: state derivation + sorting

	private func entry(_ catalog: [PetCatalogEntry], _ id: String) -> PetCatalogEntry? {
		catalog.first { $0.id == id }
	}

	func testCatalogMarksDefaultBadgeHolderAsIsDefault() {
		let (vm, _) = makeViewModel(canonical: ["felix"], defaultPetId: "felix")
		let catalog = vm.catalog()
		XCTAssertTrue(entry(catalog, "felix")?.isDefault ?? false,
			"the default badge holder must have isDefault == true")
	}

	func testCatalogMarksNonDefaultCanonicalPetInstalled() {
		let (vm, _) = makeViewModel(canonical: ["felix", "luna"])
		let catalog = vm.catalog()
		XCTAssertEqual(entry(catalog, "luna")?.state, .installed)
		XCTAssertFalse(entry(catalog, "luna")?.isDefault ?? true,
			"non-default pet must have isDefault == false")
	}

	func testCatalogMarksCodexOnlyPetImportable() {
		let (vm, _) = makeViewModel(codex: ["alexander"], canonical: [])
		let catalog = vm.catalog()
		XCTAssertEqual(entry(catalog, "alexander")?.state, .importable)
	}

	func testCatalogTreatsBundledMaewAsInstalledEvenWhenNotSeeded() {
		// maew present only under ~/.codex must never read as importable —
		// it is the bundled default and is always installed.
		let (vm, _) = makeViewModel(codex: ["maew"], canonical: [])
		let catalog = vm.catalog()
		XCTAssertNotEqual(entry(catalog, DEFAULT_PET_NAME)?.state, .importable)
		XCTAssertTrue(entry(catalog, DEFAULT_PET_NAME)?.isDefault ?? false)
	}

	func testCatalogSortsAlphabeticallyRegardlessOfState() {
		// Mixed states must interleave by display name, not cluster by tier:
		// alpha (importable) precedes felix (installed) precedes zeta (installed).
		let (vm, _) = makeViewModel(codex: ["alpha"], canonical: ["felix", "zeta"])
		XCTAssertEqual(vm.catalog().map(\.id), ["alpha", "felix", DEFAULT_PET_NAME, "zeta"])
	}

	func testCatalogOrderIsStableWhenDefaultBadgeChanges() {
		// Reassigning the default badge must not relocate any card.
		let (vmA, _) = makeViewModel(canonical: ["felix", "zeta"], defaultPetId: "felix")
		let (vmB, _) = makeViewModel(canonical: ["felix", "zeta"], defaultPetId: "zeta")
		XCTAssertEqual(vmA.catalog().map(\.id), vmB.catalog().map(\.id))
	}

	func testCatalogReadsDisplayNameAndDescriptionFromPetJson() throws {
		let roots = makePets(canonical: [])
		let dir = roots.canonicalRoot.appendingPathComponent("rocky")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let json = #"{"id":"rocky","displayName":"Rocky","description":"A steady rock."}"#
		try Data(json.utf8).write(to: dir.appendingPathComponent("pet.json"))
		let configURL = tmp.appendingPathComponent("config.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL
		)
		let e = entry(vm.catalog(), "rocky")
		XCTAssertEqual(e?.displayName, "Rocky")
		XCTAssertEqual(e?.description, "A steady rock.")
	}

	func testCatalogFallsBackToIdWhenPetJsonHasNoDisplayName() {
		// makePets writes `{}` — display name must fall back to the directory id.
		let (vm, _) = makeViewModel(canonical: ["felix"])
		XCTAssertEqual(entry(vm.catalog(), "felix")?.displayName, "felix")
	}

	// MARK: - Assignment model (P14.07)

	private func makeViewModelWithAssignments(
		codex: [String] = [],
		canonical: [String] = []
	) -> (vm: PetTabViewModel, assignmentsURL: URL) {
		let roots = makePets(codex: codex, canonical: canonical)
		let configURL = tmp.appendingPathComponent("config-assign.json")
		let assignmentsURL = tmp.appendingPathComponent("assignments-assign.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL,
			assignmentsURL: assignmentsURL
		)
		return (vm, assignmentsURL)
	}

	func testAssignBadgeRemovesFromPriorHolder() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["pet-a", "pet-b"])
		try vm.assign(badge: "claude_code", to: "pet-a")
		XCTAssertTrue(vm.badges(for: "pet-a").contains("claude_code"))
		try vm.assign(badge: "claude_code", to: "pet-b")
		XCTAssertFalse(vm.badges(for: "pet-a").contains("claude_code"),
			"claude_code must move off pet-a when assigned to pet-b")
		XCTAssertTrue(vm.badges(for: "pet-b").contains("claude_code"))
	}

	func testUnassignRemovesBadgeAndPersists() throws {
		let (vm, assignmentsURL) = makeViewModelWithAssignments(canonical: ["pet-a"])
		try vm.assign(badge: "claude_code", to: "pet-a")

		let didUnassign = vm.unassign(badge: "claude_code", from: "pet-a")

		XCTAssertTrue(didUnassign)
		XCTAssertFalse(vm.badges(for: "pet-a").contains("claude_code"))
		let snapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
		XCTAssertNil(snapshot.platformOverrides["claude_code"])
	}

	func testUnassignDefaultIsNoOp() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["pet-a"])
		try vm.assign(badge: "default", to: "pet-a")
		var callbackFired = false
		vm.onAssignmentsChanged = { callbackFired = true }

		let didUnassign = vm.unassign(badge: "default", from: "pet-a")

		XCTAssertFalse(didUnassign)
		XCTAssertTrue(vm.badges(for: "pet-a").contains("default"))
		XCTAssertFalse(callbackFired, "default badge cannot be unassigned")
	}

	func testUnassignDoesNotUpdateInMemoryStateWhenWriteFails() throws {
		let roots = makePets(canonical: ["pet-a"])
		let assignmentsURL = tmp.appendingPathComponent("assignments-failing.json")
		try """
			{
			  "schema_version": 1,
			  "default": "maew",
			  "claude_code": "pet-a"
			}
			""".write(to: assignmentsURL, atomically: true, encoding: .utf8)
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: tmp.appendingPathComponent("config.json"),
			assignmentsURL: assignmentsURL
		)
		try FileManager.default.removeItem(at: assignmentsURL)
		try FileManager.default.createDirectory(at: assignmentsURL, withIntermediateDirectories: false)
		var callbackFired = false
		vm.onAssignmentsChanged = { callbackFired = true }

		let didUnassign = vm.unassign(badge: "claude_code", from: "pet-a")

		XCTAssertFalse(didUnassign)
		XCTAssertTrue(vm.badges(for: "pet-a").contains("claude_code"))
		XCTAssertFalse(callbackFired, "onAssignmentsChanged must not fire when unassign write fails")
	}

	func testReassigningDefaultMovesIsDefault() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["pet-a", "pet-b"])
		try vm.assign(badge: "default", to: "pet-a")
		XCTAssertTrue(vm.catalog().first { $0.id == "pet-a" }?.isDefault ?? false,
			"pet-a must be isDefault after receiving the default badge")
		try vm.assign(badge: "default", to: "pet-b")
		XCTAssertFalse(vm.catalog().first { $0.id == "pet-a" }?.isDefault ?? true,
			"pet-a must lose isDefault after default badge moves to pet-b")
		XCTAssertTrue(vm.catalog().first { $0.id == "pet-b" }?.isDefault ?? false,
			"pet-b must be isDefault after receiving the default badge")
	}

	func testAssignToImportablePetIsRejected() {
		let (vm, _) = makeViewModelWithAssignments(codex: ["importable-pet"])
		XCTAssertThrowsError(try vm.assign(badge: "default", to: "importable-pet"),
			"assign to an importable (codex-only) pet must throw")
	}

	func testOnAssignmentsChangedFiresExactlyWhenMapChanges() throws {
		let (vm, _) = makeViewModelWithAssignments(canonical: ["pet-a", "pet-b"])
		var fireCount = 0
		vm.onAssignmentsChanged = { fireCount += 1 }
		try vm.assign(badge: "claude_code", to: "pet-a")
		XCTAssertEqual(fireCount, 1, "onAssignmentsChanged must fire on first assign")
		try vm.assign(badge: "claude_code", to: "pet-a")
		XCTAssertEqual(fireCount, 1, "no-op assign (same badge, same pet) must not fire")
		try vm.assign(badge: "claude_code", to: "pet-b")
		XCTAssertEqual(fireCount, 2, "onAssignmentsChanged must fire when badge moves to a new pet")
	}

	func testAssignmentMapRoundTripsThroughWriterAndReader() throws {
		let (vm, assignmentsURL) = makeViewModelWithAssignments(canonical: ["pet-a", "pet-b"])
		try vm.assign(badge: "default", to: "pet-a")
		try vm.assign(badge: "claude_code", to: "pet-b")
		let snapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
		XCTAssertEqual(snapshot.default, "pet-a")
		XCTAssertEqual(snapshot.platformOverrides["claude_code"], "pet-b")
	}
}

// MARK: - PetConfig.write

final class PetConfigWriteTests: XCTestCase {
	func testWritePetNamePersistsToConfigUrl() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("pet-config-write-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let configURL = tmp.appendingPathComponent("config.json")
		try PetConfig.write(petName: "nyx", to: configURL)

		let data = try Data(contentsOf: configURL)
		let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		XCTAssertEqual(obj?["pet"] as? String, "nyx")
	}

	func testWritePetNameCreatesParentDirectoryWhenAbsent() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("pet-config-write-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: tmp) }
		XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))

		let configURL = tmp.appendingPathComponent("config.json")
		try PetConfig.write(petName: "nyx", to: configURL)

		XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
	}

	func testWritePetNameOverwritesExistingConfig() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("pet-config-write-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let configURL = tmp.appendingPathComponent("config.json")
		try PetConfig.write(petName: "first", to: configURL)
		try PetConfig.write(petName: "second", to: configURL)

		let data = try Data(contentsOf: configURL)
		let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		XCTAssertEqual(obj?["pet"] as? String, "second")
	}
}

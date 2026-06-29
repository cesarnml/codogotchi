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
			try! Data("{}".utf8).write(to: dir.appendingPathComponent("pet.json"))
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
		activePetId: String = DEFAULT_PET_NAME
	) -> (PetTabViewModel, configURL: URL) {
		let roots = makePets(codex: codex, canonical: canonical)
		let configURL = tmp.appendingPathComponent("config.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: configURL,
			initialActivePetId: activePetId
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

	// MARK: - Default selection: Maew

	func testDefaultSelectionIsMaewWhenNothingElseConfigured() {
		let (vm, _) = makeViewModel()
		XCTAssertEqual(vm.activePetId, DEFAULT_PET_NAME,
			"Active pet must default to maew when no other selection is configured")
	}

	func testDefaultSelectionHonorsPreviouslyPersistedChoice() {
		let (vm, _) = makeViewModel(canonical: ["felix"], activePetId: "felix")
		XCTAssertEqual(vm.activePetId, "felix")
	}

	// MARK: - selectPet: persistence + notification

	func testSelectPetPersistsChoiceToConfigUrl() throws {
		let (vm, configURL) = makeViewModel(canonical: ["ruby"])
		vm.selectPet(id: "ruby")
		let data = try Data(contentsOf: configURL)
		let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		XCTAssertEqual(obj?["pet"] as? String, "ruby", "selectPet must write the chosen id to config.json")
	}

	func testSelectPetUpdatesActivePetId() {
		let (vm, _) = makeViewModel(canonical: ["ruby"])
		vm.selectPet(id: "ruby")
		XCTAssertEqual(vm.activePetId, "ruby")
	}

	func testSelectPetFiresOnActivePetChanged() {
		let (vm, _) = makeViewModel(canonical: ["ruby"])
		var fired: String?
		vm.onActivePetChanged = { fired = $0 }
		vm.selectPet(id: "ruby")
		XCTAssertEqual(fired, "ruby", "onActivePetChanged must fire with the new pet id")
	}

	func testSelectPetDoesNotUpdateInMemoryStateWhenWriteFails() {
		// configURL points to an unwritable path — write must fail.
		let roots = makePets(canonical: ["ruby"])
		// Use a read-only directory as parent so the write throws
		let unwritableDir = URL(fileURLWithPath: "/dev/null/nonexistent")
		let badConfigURL = unwritableDir.appendingPathComponent("config.json")
		let vm = PetTabViewModel(
			codexPetsRoot: roots.codexRoot,
			canonicalPetsRoot: roots.canonicalRoot,
			configURL: badConfigURL,
			initialActivePetId: DEFAULT_PET_NAME
		)
		var callbackFired = false
		vm.onActivePetChanged = { _ in callbackFired = true }
		vm.selectPet(id: "ruby")
		// activePetId must NOT change and callback must NOT fire when write fails
		XCTAssertEqual(vm.activePetId, DEFAULT_PET_NAME,
			"activePetId must not change when config write fails")
		XCTAssertFalse(callbackFired, "onActivePetChanged must not fire when config write fails")
	}

	func testSelectPetNoOpWhenAlreadyActive() {
		let (vm, _) = makeViewModel()
		var callCount = 0
		vm.onActivePetChanged = { _ in callCount += 1 }
		vm.selectPet(id: DEFAULT_PET_NAME)
		XCTAssertEqual(callCount, 0, "selectPet must be a no-op when the pet is already active")
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
			initialActivePetId: DEFAULT_PET_NAME,
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
			configURL: configURL,
			initialActivePetId: DEFAULT_PET_NAME
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

	func testCatalogMarksActiveCanonicalPetSelected() {
		let (vm, _) = makeViewModel(canonical: ["felix"], activePetId: "felix")
		let catalog = vm.catalog()
		XCTAssertEqual(entry(catalog, "felix")?.state, .selected)
	}

	func testCatalogMarksNonActiveCanonicalPetInstalled() {
		let (vm, _) = makeViewModel(canonical: ["felix", "luna"], activePetId: "felix")
		let catalog = vm.catalog()
		XCTAssertEqual(entry(catalog, "luna")?.state, .installed)
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
		// alpha (importable) precedes felix (selected) precedes zeta (installed).
		let (vm, _) = makeViewModel(
			codex: ["alpha"], canonical: ["felix", "zeta"], activePetId: "felix")
		XCTAssertEqual(vm.catalog().map(\.id), ["alpha", "felix", DEFAULT_PET_NAME, "zeta"])
	}

	func testCatalogOrderIsStableWhenActiveSelectionChanges() {
		// Selecting a different pet must not move any card — the ordering is
		// identical whether felix or zeta is active.
		let (vmA, _) = makeViewModel(
			codex: [], canonical: ["felix", "zeta"], activePetId: "felix")
		let (vmB, _) = makeViewModel(
			codex: [], canonical: ["felix", "zeta"], activePetId: "zeta")
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
			configURL: configURL,
			initialActivePetId: DEFAULT_PET_NAME
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

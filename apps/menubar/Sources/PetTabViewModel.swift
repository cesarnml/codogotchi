import Foundation

/// View model for the Pet tab. Stubs until P8.07 green.
final class PetTabViewModel {
	let codexPetsRoot: URL
	let canonicalPetsRoot: URL
	let configURL: URL

	private(set) var activePetId: String

	var onActivePetChanged: ((String) -> Void)?

	private let importOverride: ((String) throws -> Void)?

	init(
		codexPetsRoot: URL,
		canonicalPetsRoot: URL,
		configURL: URL,
		initialActivePetId: String = DEFAULT_PET_NAME,
		importOverride: ((String) throws -> Void)? = nil
	) {
		self.codexPetsRoot = codexPetsRoot
		self.canonicalPetsRoot = canonicalPetsRoot
		self.configURL = configURL
		self.activePetId = initialActivePetId
		self.importOverride = importOverride
	}

	func allPetIds() -> [String] {
		// Stub: returns empty — tests will fail
		return []
	}

	func selectPet(id: String) {
		// Stub: no-op — tests will fail
	}

	func importPet(id: String) throws {
		// Stub: no-op — tests will fail
	}
}

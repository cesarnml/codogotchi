import Foundation

/// View model for the Pet tab: enumerates pets from bundled, Codex, and
/// canonical-store sources; manages active selection and persistence.
///
/// Three sources, deduplicated by pet ID:
/// 1. Bundled Maew — always present (`DEFAULT_PET_NAME`).
/// 2. Codex pets — `~/.codex/pets/<id>/` directories (may be absent).
/// 3. Canonical store pets — `~/.codogotchi/pets/<id>/` directories.
///
/// Active selection persists to `configURL` (defaults to `PetConfig.configURL()`).
final class PetTabViewModel {
	let codexPetsRoot: URL
	let canonicalPetsRoot: URL
	let configURL: URL

	private(set) var activePetId: String

	/// Fired only when `selectPet` actually changes the active pet.
	var onActivePetChanged: ((String) -> Void)?

	/// Optional import override — injected by tests to avoid real filesystem I/O.
	private let importOverride: ((String) throws -> Void)?

	init(
		codexPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codex/pets"),
		canonicalPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi/pets"),
		configURL: URL = PetConfig.configURL(),
		initialActivePetId: String = PetConfig.resolvedPetName(),
		importOverride: ((String) throws -> Void)? = nil
	) {
		self.codexPetsRoot = codexPetsRoot
		self.canonicalPetsRoot = canonicalPetsRoot
		self.configURL = configURL
		self.activePetId = initialActivePetId
		self.importOverride = importOverride
	}

	/// All available pet IDs from all three sources, deduplicated and sorted.
	/// Bundled Maew (`DEFAULT_PET_NAME`) is always included.
	func allPetIds() -> [String] {
		var ids = Set<String>()
		ids.insert(DEFAULT_PET_NAME)
		let fm = FileManager.default
		for root in [codexPetsRoot, canonicalPetsRoot] {
			guard let contents = try? fm.contentsOfDirectory(
				at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
			else { continue }
			for url in contents {
				let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
				if isDir { ids.insert(url.lastPathComponent) }
			}
		}
		return ids.sorted()
	}

	/// Sets the active pet, persists to `configURL`, and fires `onActivePetChanged`.
	/// No-op when `id` is already active. Aborts without updating in-memory state or
	/// firing the callback if the config write fails, so the user can retry.
	func selectPet(id: String) {
		guard id != activePetId else { return }
		do {
			try PetConfig.write(petName: id, to: configURL)
		} catch {
			NSLog("PetTabViewModel: failed to persist pet selection for '%@' — %@", id, error.localizedDescription)
			return
		}
		activePetId = id
		onActivePetChanged?(id)
	}

	/// Imports a Codex pet via `PetImportHelper` (or the injected test override).
	func importPet(id: String) throws {
		if let override = importOverride {
			try override(id)
		} else {
			let helper = PetImportHelper(
				codexPetsRoot: codexPetsRoot,
				canonicalPetsRoot: canonicalPetsRoot
			)
			try helper.importPet(id: id)
		}
	}
}

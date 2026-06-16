import Foundation

/// A single pet rendered as a card in the Pet tab grid.
///
/// `state` is derived purely from *where the pet lives*: a pet in the canonical
/// store (`~/.codogotchi/pets/`) is `installed` — and `selected` when it is the
/// active pet — while a pet that exists only under `~/.codex/pets/` is
/// `importable`. `assetDirectory` is the directory holding the pet's
/// `spritesheet.webp`, used to slice a static catalog thumbnail.
struct PetCatalogEntry: Equatable {
	enum State: Equatable {
		case selected  // installed and currently active
		case installed  // in the canonical store, not active
		case importable  // present only under ~/.codex/pets
	}

	let id: String
	let displayName: String
	let description: String
	let state: State
	let assetDirectory: URL
	let spritesheetURL: URL?

	var isDefault: Bool { id == DEFAULT_PET_NAME }
}

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

	/// Rich catalog of all pets for the card grid, deduplicated by ID and sorted
	/// for display: the selected pet first, then other installed pets, then
	/// importable Codex pets — alphabetically by display name within each tier.
	///
	/// Bundled Maew (`DEFAULT_PET_NAME`) is always treated as installed even if
	/// the canonical directory has not been seeded yet, so it never appears as
	/// importable.
	func catalog() -> [PetCatalogEntry] {
		let canonicalIds = Set(directoryNames(in: canonicalPetsRoot))
		let codexIds = Set(directoryNames(in: codexPetsRoot))
		var ids = canonicalIds.union(codexIds)
		ids.insert(DEFAULT_PET_NAME)

		let entries = ids.map { id -> PetCatalogEntry in
			let installed = canonicalIds.contains(id) || id == DEFAULT_PET_NAME
			let assetDir = (installed ? canonicalPetsRoot : codexPetsRoot)
				.appendingPathComponent(id, isDirectory: true)
			let meta = readMetadata(at: assetDir, fallbackId: id)
			let state: PetCatalogEntry.State =
				installed ? (id == activePetId ? .selected : .installed) : .importable
			let sheet = meta.spritesheetPath.map { assetDir.appendingPathComponent($0) }
			return PetCatalogEntry(
				id: id,
				displayName: meta.displayName,
				description: meta.description,
				state: state,
				assetDirectory: assetDir,
				spritesheetURL: sheet
			)
		}

		func rank(_ s: PetCatalogEntry.State) -> Int {
			switch s {
			case .selected: return 0
			case .installed: return 1
			case .importable: return 2
			}
		}
		return entries.sorted { a, b in
			if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
			return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
		}
	}

	private func directoryNames(in root: URL) -> [String] {
		guard let contents = try? FileManager.default.contentsOfDirectory(
			at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
		else { return [] }
		return contents.compactMap { url in
			let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
			return isDir ? url.lastPathComponent : nil
		}
	}

	private struct PetMetadataJSON: Decodable {
		let displayName: String?
		let description: String?
		let spritesheetPath: String?
	}

	/// Reads `pet.json` for display name, description, and spritesheet filename.
	/// Tolerates a missing or malformed file: falls back to the pet ID as the
	/// display name, an empty description, and the conventional
	/// `spritesheet.webp` so a thumbnail can still be attempted.
	private func readMetadata(at directory: URL, fallbackId: String)
		-> (displayName: String, description: String, spritesheetPath: String?)
	{
		let url = directory.appendingPathComponent("pet.json")
		guard let data = try? Data(contentsOf: url) else {
			return (fallbackId, "", "spritesheet.webp")
		}
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		let meta = try? decoder.decode(PetMetadataJSON.self, from: data)
		let name = meta?.displayName?.isEmpty == false ? meta!.displayName! : fallbackId
		return (name, meta?.description ?? "", meta?.spritesheetPath ?? "spritesheet.webp")
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

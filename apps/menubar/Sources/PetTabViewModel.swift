import Foundation

/// A single pet rendered as a card in the Pet tab grid.
///
/// `state` is derived from *where the pet lives*: a pet in the canonical
/// store (`~/.codogotchi/pets/`) is `installed`, while a pet that exists only
/// under `~/.codex/pets/` is `importable`. `isDefault` is true when this pet
/// holds the "default" badge in `assignments.json`. `assetDirectory` is the
/// directory holding the pet's `spritesheet.webp`.
struct PetCatalogEntry: Equatable {
	enum State: Equatable {
		case installed  // in the canonical store (or bundled Maew)
		case importable  // present only under ~/.codex/pets
	}

	let id: String
	let displayName: String
	let description: String
	let state: State
	let assetDirectory: URL
	let spritesheetURL: URL?
	let isDefault: Bool  // true when this pet holds the "default" badge
}

enum PetTabViewModelError: LocalizedError {
	case petNotAssignable(String)
	case invalidBadge(String)

	var errorDescription: String? {
		switch self {
		case .petNotAssignable(let id):
			return "Pet '\(id)' is importable-only and cannot be assigned a badge"
		case .invalidBadge(let key):
			return "'\(key)' is not a valid badge key"
		}
	}
}

/// View model for the Pet tab: enumerates pets from bundled, Codex, and
/// canonical-store sources; manages badge assignments and persistence.
///
/// Three sources, deduplicated by pet ID:
/// 1. Bundled Maew — always present (`DEFAULT_PET_NAME`).
/// 2. Codex pets — `~/.codex/pets/<id>/` directories (may be absent).
/// 3. Canonical store pets — `~/.codogotchi/pets/<id>/` directories.
///
/// Badge assignments persist to `assignmentsURL` (defaults to
/// `~/.codogotchi/assignments.json`). The "default" badge holder drives the
/// selection border in the Pet tab card grid.
final class PetTabViewModel {
	let codexPetsRoot: URL
	let canonicalPetsRoot: URL
	let configURL: URL
	let assignmentsURL: URL

	private(set) var assignmentsSnapshot: AssignmentsSnapshot

	/// Fired when `assign` or `unassign` changes the assignment map.
	var onAssignmentsChanged: (() -> Void)?

	/// Optional import override — injected by tests to avoid real filesystem I/O.
	private let importOverride: ((String) throws -> Void)?

	init(
		codexPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codex/pets"),
		canonicalPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi/pets"),
		configURL: URL = PetConfig.configURL(),
		assignmentsURL: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi/assignments.json"),
		importOverride: ((String) throws -> Void)? = nil
	) {
		self.codexPetsRoot = codexPetsRoot
		self.canonicalPetsRoot = canonicalPetsRoot
		self.configURL = configURL
		self.assignmentsURL = assignmentsURL
		self.assignmentsSnapshot = AssignmentsJsonReader.read(at: assignmentsURL.path)
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
	/// alphabetically by display name. Sort is deliberately *stable across state
	/// changes*: a pet's `state` drives its card's button and badge — never its
	/// position. Importing or assigning a badge to a pet must not relocate its
	/// card out from under the user.
	///
	/// Bundled Maew (`DEFAULT_PET_NAME`) is always treated as installed even if
	/// the canonical directory has not been seeded yet, so it never appears as
	/// importable.
	func catalog() -> [PetCatalogEntry] {
		let canonicalIds = Set(directoryNames(in: canonicalPetsRoot))
		let codexIds = Set(directoryNames(in: codexPetsRoot))
		var ids = canonicalIds.union(codexIds)
		ids.insert(DEFAULT_PET_NAME)

		let defaultHolder = assignmentsSnapshot.default

		let entries = ids.map { id -> PetCatalogEntry in
			let installed = canonicalIds.contains(id) || id == DEFAULT_PET_NAME
			let assetDir = (installed ? canonicalPetsRoot : codexPetsRoot)
				.appendingPathComponent(id, isDirectory: true)
			let meta = readMetadata(at: assetDir, fallbackId: id)
			let state: PetCatalogEntry.State = installed ? .installed : .importable
			let sheet = meta.spritesheetPath.map { assetDir.appendingPathComponent($0) }
			return PetCatalogEntry(
				id: id,
				displayName: meta.displayName,
				description: meta.description,
				state: state,
				assetDirectory: assetDir,
				spritesheetURL: sheet,
				isDefault: id == defaultHolder
			)
		}

		return entries.sorted { a, b in
			let byName = a.displayName.localizedCaseInsensitiveCompare(b.displayName)
			if byName != .orderedSame { return byName == .orderedAscending }
			// Stable tiebreak on id so equal display names keep a fixed order.
			return a.id < b.id
		}
	}

	/// Assigns `badge` to `petId`, enforcing the uniqueness invariant: the badge
	/// moves off its prior holder. Reuses `applyBadgeAssignment` from P14.03.
	///
	/// - Throws `PetTabViewModelError.petNotAssignable` when `petId` is
	///   importable (codex-only).
	/// - No-op when `petId` already holds `badge` (does not fire the callback).
	func assign(badge: String, to petId: String) throws {
		guard ASSIGNMENT_BADGE_KEYS.contains(badge) else {
			throw PetTabViewModelError.invalidBadge(badge)
		}
		guard isInstalled(petId) else {
			throw PetTabViewModelError.petNotAssignable(petId)
		}

		let currentHolder: String? =
			badge == "default"
			? assignmentsSnapshot.default
			: assignmentsSnapshot.platformOverrides[badge]
		guard currentHolder != petId else { return }

		try AssignmentsJsonWriter.write(badge: badge, petId: petId, to: assignmentsURL)
		let newOverrides =
			badge == "default"
			? assignmentsSnapshot.platformOverrides
			: applyBadgeAssignment(
				badge: badge, petId: petId, in: assignmentsSnapshot.platformOverrides)
		assignmentsSnapshot = AssignmentsSnapshot(
			default: badge == "default" ? petId : assignmentsSnapshot.default,
			platformOverrides: newOverrides
		)
		onAssignmentsChanged?()
	}

	/// Removes `badge` from `petId` when `petId` currently holds it.
	/// No-op otherwise. The "default" badge cannot be unassigned.
	/// Silently no-ops on write failure (persist-first: in-memory state
	/// is not updated when the file write fails).
	func unassign(badge: String, from petId: String) {
		guard badge != "default" else { return }
		guard assignmentsSnapshot.platformOverrides[badge] == petId else { return }
		guard (try? ConfigFileWriter.merge([badge: NSNull()], into: assignmentsURL)) != nil else { return }
		var newOverrides = assignmentsSnapshot.platformOverrides
		newOverrides.removeValue(forKey: badge)
		assignmentsSnapshot = AssignmentsSnapshot(
			default: assignmentsSnapshot.default,
			platformOverrides: newOverrides
		)
		onAssignmentsChanged?()
	}

	/// Returns the set of badge keys currently held by `petId`.
	func badges(for petId: String) -> Set<String> {
		var result = Set<String>()
		if assignmentsSnapshot.default == petId { result.insert("default") }
		for (badge, holder) in assignmentsSnapshot.platformOverrides {
			if holder == petId { result.insert(badge) }
		}
		return result
	}

	// MARK: - Private helpers

	private func isInstalled(_ id: String) -> Bool {
		id == DEFAULT_PET_NAME || directoryNames(in: canonicalPetsRoot).contains(id)
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

import Foundation

/// Copies pet directories from `~/.codex/pets/<id>/` into the canonical store
/// at `~/.codogotchi/pets/<id>/`. No runtime pet loading from the Codex path
/// happens after import — the canonical store is authoritative.
struct PetImportHelper {
	enum ImportError: Error {
		case sourcePetNotFound(id: String)
	}

	let codexPetsRoot: URL
	let canonicalPetsRoot: URL
	private let fileManager: FileManager

	init(
		codexPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codex/pets"),
		canonicalPetsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi/pets"),
		fileManager: FileManager = .default
	) {
		self.codexPetsRoot = codexPetsRoot
		self.canonicalPetsRoot = canonicalPetsRoot
		self.fileManager = fileManager
	}

	/// Returns the list of pet IDs available under `codexPetsRoot` (directory names only).
	func availableCodexPets() -> [String] {
		guard let contents = try? fileManager.contentsOfDirectory(
			at: codexPetsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []
		) else { return [] }
		return contents.compactMap { url -> String? in
			let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
			return isDir ? url.lastPathComponent : nil
		}.sorted()
	}

	/// Copies `codexPetsRoot/<id>/` into `canonicalPetsRoot/<id>/`, creating the
	/// destination directory tree when absent. Throws when the source pet is missing.
	func importPet(id: String) throws {
		let source = codexPetsRoot.appendingPathComponent(id, isDirectory: true)
		guard fileManager.fileExists(atPath: source.path) else {
			throw ImportError.sourcePetNotFound(id: id)
		}

		let destination = canonicalPetsRoot.appendingPathComponent(id, isDirectory: true)
		try fileManager.createDirectory(at: canonicalPetsRoot, withIntermediateDirectories: true)

		if fileManager.fileExists(atPath: destination.path) {
			try fileManager.removeItem(at: destination)
		}
		try fileManager.copyItem(at: source, to: destination)
	}
}

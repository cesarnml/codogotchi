import Foundation

/// Resolves a `petId` to a `(CodexPet, CodogotchiPet?)` pair and caches the
/// result so two origins assigned the same pet share one loaded `CodexPet`.
///
/// - Directories are derived per `petId`: `~/.codogotchi/pets/<petId>/`.
/// - For the built-in `maew` id, `maewFallbackURL` is used instead of the
///   user's `~/.codogotchi/pets/maew/` so the app always has something to render
///   even when the canonical store hasn't been seeded yet.
/// - A load failure for any non-maew pet falls back to loading maew from
///   `maewFallbackURL` rather than throwing, so callers always get renderable
///   assets. The fallback is logged via `NSLog`.
/// - `evict(petId:)` / `evictAll()` drops cached entries so a reassignment
///   forces a fresh load on the next `resolve` call.
final class PetAssetResolver {
	typealias CodexLoader = (URL) throws -> CodexPet
	typealias CodogotchiLoader = (URL) throws -> CodogotchiPet

	private var cache: [String: (CodexPet, CodogotchiPet?)] = [:]
	private let codexLoader: CodexLoader
	private let codogotchiLoader: CodogotchiLoader
	private let maewFallbackURL: URL

	init(
		codexLoader: @escaping CodexLoader = { try CodexPet(petDirectory: $0.path) },
		codogotchiLoader: @escaping CodogotchiLoader = { try CodogotchiPet(petDirectory: $0.path) },
		maewFallbackURL: URL = PetAssetResolver.defaultMaewFallbackURL()
	) {
		self.codexLoader = codexLoader
		self.codogotchiLoader = codogotchiLoader
		self.maewFallbackURL = maewFallbackURL
	}

	/// Resolve `petId` to `(CodexPet, CodogotchiPet?)`.
	///
	/// - For `DEFAULT_PET_NAME` ("maew"), `maewFallbackURL` is used as the directory.
	/// - For other ids, the directory is `<codogotchiPetsBase>/<petId>/`.
	/// - `CodogotchiPet` load failures are soft-degraded to `nil` (missing sheets
	///   are expected; `CodogotchiPet` itself handles the degrade internally).
	/// - `CodexPet` load failures for non-maew pets fall back to the maew assets.
	/// - Throws only when the maew fallback itself cannot be loaded (unexpected;
	///   bundled assets should always be present).
	func resolve(petId: String) throws -> (CodexPet, CodogotchiPet?) {
		if let cached = cache[petId] { return cached }

		let dirURL = petId == DEFAULT_PET_NAME ? maewFallbackURL : petsBaseURL(petId: petId)

		do {
			let codexPet = try codexLoader(dirURL)
			let codogotchiPet = try? codogotchiLoader(dirURL)
			let pair = (codexPet, codogotchiPet)
			cache[petId] = pair
			return pair
		} catch {
			guard petId != DEFAULT_PET_NAME else { throw error }
			NSLog(
				"PetAssetResolver: failed to load '%@' from %@ (%@) — falling back to Maew",
				petId, dirURL.path, error.localizedDescription)
			return try resolveMaewFallback()
		}
	}

	/// Drop the cached entry for `petId` so the next `resolve` re-loads from disk.
	func evict(petId: String) {
		cache.removeValue(forKey: petId)
	}

	/// Drop all cached entries.
	func evictAll() {
		cache.removeAll()
	}

	// MARK: - Private

	private func resolveMaewFallback() throws -> (CodexPet, CodogotchiPet?) {
		if let cached = cache[DEFAULT_PET_NAME] { return cached }
		let codexPet = try codexLoader(maewFallbackURL)
		let codogotchiPet = try? codogotchiLoader(maewFallbackURL)
		let pair = (codexPet, codogotchiPet)
		cache[DEFAULT_PET_NAME] = pair
		return pair
	}

	private func petsBaseURL(petId: String) -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"), let base = String(validatingUTF8: cStr) {
			return URL(fileURLWithPath: base)
				.appendingPathComponent("pets")
				.appendingPathComponent(petId)
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("pets")
			.appendingPathComponent(petId)
	}

	/// Bundled maew asset directory: `Codogotchi.app/Contents/Resources/maew/`.
	///
	/// The `Fixtures/maew` folder is declared `buildPhase: resources` in
	/// `project.yml`, so it lands at `Bundle.main.resourceURL/maew/` in the
	/// production app. Falls back to `~/.codogotchi/pets/maew/` when the bundle
	/// URL is unavailable (e.g. command-line tool contexts).
	static func defaultMaewFallbackURL() -> URL {
		if let resourceURL = Bundle.main.resourceURL {
			return resourceURL.appendingPathComponent("maew")
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("pets")
			.appendingPathComponent(DEFAULT_PET_NAME)
	}
}

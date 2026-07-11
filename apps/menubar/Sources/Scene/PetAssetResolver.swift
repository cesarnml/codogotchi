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
		let pair = try loadFresh(petId: petId)
		cache[petId] = pair
		return pair
	}

	/// Load `petId` from disk without touching the cache. Unlike `resolve`,
	/// this performs no shared mutable state access, so it is safe to call
	/// from a background thread/task — the expensive spritesheet decode and
	/// frame-slicing work happens here. Callers that want the result cached
	/// must call `insert(petId:pair:)` back on the resolver's owning thread.
	func loadFresh(petId: String) throws -> (CodexPet, CodogotchiPet?) {
		let dirURL: URL
		if petId == DEFAULT_PET_NAME {
			dirURL = maewFallbackURL
		} else {
			guard let safe = petsBaseURL(petId: petId) else {
				NSLog("PetAssetResolver: invalid petId '%@' — falling back to Maew", petId)
				return try loadMaewFallback()
			}
			dirURL = safe
		}

		do {
			let codexPet = try codexLoader(dirURL)
			let codogotchiPet = try? codogotchiLoader(dirURL)
			return (codexPet, codogotchiPet)
		} catch {
			guard petId != DEFAULT_PET_NAME else { throw error }
			NSLog(
				"PetAssetResolver: failed to load '%@' from %@ (%@) — falling back to Maew",
				petId, dirURL.path, error.localizedDescription)
			return try loadMaewFallback()
		}
	}

	/// Insert an already-loaded pair into the cache, as if `resolve(petId:)`
	/// had loaded it. Lets callers pair background loading (`loadFresh`) with
	/// a cheap, main-thread cache write.
	func insert(petId: String, pair: (CodexPet, CodogotchiPet?)) {
		cache[petId] = pair
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

	private func loadMaewFallback() throws -> (CodexPet, CodogotchiPet?) {
		let codexPet = try codexLoader(maewFallbackURL)
		let codogotchiPet = try? codogotchiLoader(maewFallbackURL)
		return (codexPet, codogotchiPet)
	}

	/// Returns the pets directory URL for `petId`, or `nil` when the petId
	/// would escape the canonical pets root via path traversal (e.g. `"../evil"`).
	private func petsBaseURL(petId: String) -> URL? {
		let root = petsRootURL()
		let candidate = root.appendingPathComponent(petId).standardizedFileURL
		let rootStd = root.standardizedFileURL
		let rootPath = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
		guard candidate.path.hasPrefix(rootPath) else { return nil }
		return root.appendingPathComponent(petId)
	}

	private func petsRootURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"), let base = String(validatingUTF8: cStr) {
			return URL(fileURLWithPath: base).appendingPathComponent("pets")
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("pets")
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

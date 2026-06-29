import AppKit
import XCTest

@testable import Codogotchi

/// Behavior contract for `PetAssetResolver` — the P14.04 id-to-assets cache.
///
/// Fixtures live at `apps/menubar/Fixtures/mali/` (CodexPet) and
/// `apps/menubar/Fixtures/maew/` (CodogotchiPet + maew fallback) so tests
/// run without populating `~/.codogotchi/pets/`.
final class PetAssetResolverTests: XCTestCase {

	// MARK: - Fixture helpers

	private func maliDirectory() -> URL {
		URL(fileURLWithPath: #file)
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Fixtures/mali")
	}

	private func maewDirectory() -> URL {
		URL(fileURLWithPath: #file)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")
	}

	private func makeCountingCodexLoader(
		count: inout Int,
		backing url: URL
	) -> PetAssetResolver.CodexLoader {
		{ [u = url] _ in
			count += 1
			return try CodexPet(petDirectory: u.path)
		}
	}

	// MARK: - Resolve returns assets

	func testResolvingIdReturnsCodexPet() throws {
		let resolver = PetAssetResolver(
			codexLoader: { _ in try CodexPet(petDirectory: self.maliDirectory().path) },
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)
		let (codexPet, _) = try resolver.resolve(petId: "mali")
		XCTAssertFalse(codexPet.frames(for: .idle).isEmpty, "resolved CodexPet must yield idle frames")
	}

	func testResolvingIdReturnsCodogotchiPetWhenLoaderSucceeds() throws {
		let resolver = PetAssetResolver(
			codexLoader: { _ in try CodexPet(petDirectory: self.maliDirectory().path) },
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)
		let (_, codogotchiPet) = try resolver.resolve(petId: "maew")
		XCTAssertNotNil(codogotchiPet, "CodogotchiPet must be loaded when loader succeeds")
	}

	// MARK: - Cache: loader called once

	func testResolvingTwiceHitsCacheLoaderCalledOnce() throws {
		var callCount = 0
		let resolver = PetAssetResolver(
			codexLoader: { [m = maliDirectory()] _ in
				callCount += 1
				return try CodexPet(petDirectory: m.path)
			},
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)

		_ = try resolver.resolve(petId: "mali")
		_ = try resolver.resolve(petId: "mali")

		XCTAssertEqual(callCount, 1, "codex loader must be called once for two resolves of the same id")
	}

	func testTwoDifferentOriginsSamePetIdShareOneLoadedInstance() throws {
		var callCount = 0
		let resolver = PetAssetResolver(
			codexLoader: { [m = maliDirectory()] _ in
				callCount += 1
				return try CodexPet(petDirectory: m.path)
			},
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)

		let (pet1, _) = try resolver.resolve(petId: "mali")
		let (pet2, _) = try resolver.resolve(petId: "mali")

		XCTAssertTrue(pet1 === pet2, "two resolves of the same petId must return the same CodexPet instance")
		XCTAssertEqual(callCount, 1, "loader must fire exactly once for shared pet")
	}

	// MARK: - Fallback to Maew

	func testNonMaewLoadFailureFallsBackToMaewWithoutThrowing() throws {
		let resolver = PetAssetResolver(
			codexLoader: { url in
				if url.lastPathComponent == DEFAULT_PET_NAME { return try CodexPet(petDirectory: self.maewDirectory().path) }
				throw CodexPetLoadError.petJsonNotFound
			},
			codogotchiLoader: { url in
				if url.lastPathComponent == DEFAULT_PET_NAME { return try CodogotchiPet(petDirectory: self.maewDirectory().path) }
				throw CodexPetLoadError.petJsonNotFound
			},
			maewFallbackURL: maewDirectory()
		)

		// Must not throw; must return maew assets
		let (codexPet, _) = try resolver.resolve(petId: "brokenPet")
		XCTAssertEqual(codexPet.id, "maew", "fallback must return maew CodexPet")
	}

	func testMaewFallbackDoesNotThrowToCallerEvenWhenPetIsNotCachedYet() throws {
		// Ensure fallback-to-maew path is exercised without a prior maew cache entry.
		let resolver = PetAssetResolver(
			codexLoader: { url in
				if url.lastPathComponent == DEFAULT_PET_NAME { return try CodexPet(petDirectory: self.maewDirectory().path) }
				throw CodexPetLoadError.petJsonNotFound
			},
			codogotchiLoader: { url in
				if url.lastPathComponent == DEFAULT_PET_NAME { return try CodogotchiPet(petDirectory: self.maewDirectory().path) }
				throw CodexPetLoadError.petJsonNotFound
			},
			maewFallbackURL: maewDirectory()
		)

		XCTAssertNoThrow(try resolver.resolve(petId: "noSuchPet"))
	}

	// MARK: - Eviction

	func testEvictionForcesReload() throws {
		var callCount = 0
		let resolver = PetAssetResolver(
			codexLoader: { [m = maliDirectory()] _ in
				callCount += 1
				return try CodexPet(petDirectory: m.path)
			},
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)

		_ = try resolver.resolve(petId: "mali")
		XCTAssertEqual(callCount, 1)

		resolver.evict(petId: "mali")
		_ = try resolver.resolve(petId: "mali")
		XCTAssertEqual(callCount, 2, "loader must re-fire after eviction")
	}

	func testEvictAllForcesReloadForAllPets() throws {
		var maliCount = 0
		var maewCount = 0
		let resolver = PetAssetResolver(
			codexLoader: { [mali = maliDirectory(), maew = maewDirectory()] url in
				if url.lastPathComponent == "mali" {
					maliCount += 1
					return try CodexPet(petDirectory: mali.path)
				}
				maewCount += 1
				return try CodexPet(petDirectory: maew.path)
			},
			codogotchiLoader: { _ in try CodogotchiPet(petDirectory: self.maewDirectory().path) },
			maewFallbackURL: maewDirectory()
		)

		_ = try resolver.resolve(petId: "mali")
		_ = try resolver.resolve(petId: "maew")

		resolver.evictAll()

		_ = try resolver.resolve(petId: "mali")
		_ = try resolver.resolve(petId: "maew")

		XCTAssertEqual(maliCount, 2, "mali loader must fire twice: initial + after evictAll")
		XCTAssertEqual(maewCount, 2, "maew loader must fire twice: initial + after evictAll")
	}
}

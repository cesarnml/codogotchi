import Foundation

/// Idempotent helper that seeds the canonical pet store from a source directory.
///
/// On first launch (or when the canonical store is incomplete), `MenubarApp`
/// calls `seed(from:into:)` to copy the bundled Maew assets into
/// `~/.codogotchi/pets/maew/`. Existing files are never overwritten so
/// a user-customised store survives repeated app launches.
enum PetStoreSeeder {
	/// Asset filenames that must all be present for a store to be considered complete.
	static let requiredAssets: [String] = [
		"pet.json",
		"spritesheet.webp",
		"codogotchi-lite-basic-spritesheet.webp",
		"codogotchi-soa-spritesheet.webp",
	]

	/// Returns `true` when every required asset exists inside `petDirectory`.
	static func isCanonicalStoreComplete(at petDirectory: String) -> Bool {
		let fm = FileManager.default
		let dir = URL(fileURLWithPath: petDirectory)
		for asset in requiredAssets {
			if !fm.fileExists(atPath: dir.appendingPathComponent(asset).path) {
				return false
			}
		}
		return true
	}

	/// Copies any missing required assets from `sourceDirectory` into `petDirectory`.
	///
	/// Creates `petDirectory` (including parents) when absent.
	/// Files that already exist are left untouched — the seed is idempotent.
	/// Source assets that are absent are silently skipped rather than throwing,
	/// so a partial bundle degrades gracefully.
	static func seed(from sourceDirectory: URL, into petDirectory: String) throws {
		let fm = FileManager.default
		let dest = URL(fileURLWithPath: petDirectory)

		if !fm.fileExists(atPath: petDirectory) {
			try fm.createDirectory(at: dest, withIntermediateDirectories: true)
		}

		for asset in requiredAssets {
			let src = sourceDirectory.appendingPathComponent(asset)
			let dst = dest.appendingPathComponent(asset)
			guard fm.fileExists(atPath: src.path) else {
				NSLog("PetStoreSeeder: bundle asset '%@' missing from source — store will remain incomplete", asset)
				continue
			}
			guard !fm.fileExists(atPath: dst.path) else { continue }
			try fm.copyItem(at: src, to: dst)
		}
	}
}

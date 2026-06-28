import AppKit
import Foundation

/// Canonical on-disk locations the user can open from Settings:
/// the data folder (Developer tab) and the pet store (Pet tab).
/// Both respect `CODOGOTCHI_HOME`.
enum CodogotchiFolders {
	/// `~/.codogotchi/` — home of `state.json`, `gate.json`, and the transition log.
	static func dataFolderURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"),
			let home = String(validatingUTF8: cStr),
			!home.isEmpty
		{
			return URL(fileURLWithPath: home, isDirectory: true)
		}
		return FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi", isDirectory: true)
	}

	/// `~/.codogotchi/pets/` — the canonical pet store directory.
	static func petFolderURL() -> URL {
		dataFolderURL().appendingPathComponent("pets", isDirectory: true)
	}

	/// `~/.codogotchi/rpg-state.json` — RPG progression written by the CLI.
	static func rpgStatePath() -> String {
		dataFolderURL().appendingPathComponent("rpg-state.json").path
	}

	/// Create the folder if missing, then reveal it in Finder. Creating first
	/// keeps a first-launch open (folder not yet written) from silently no-oping.
	/// `createDirectory(withIntermediateDirectories:)` is idempotent.
	@discardableResult
	static func reveal(
		_ url: URL,
		fileManager: FileManager = .default,
		open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
	) -> Bool {
		try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
		return open(url)
	}
}

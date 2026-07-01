import Foundation

/// A single enumeration of a `state.d/` directory captured once per poll tick.
///
/// Before P15.02 the poll path re-scanned `state.d/` several times every tick
/// (once for the per-origin state read, once for the per-origin gate/context
/// read, and once per `newest *.gate.json` / `*.context.json` resolution), each
/// issuing its own `contentsOfDirectory` + per-file `attributesOfItem` at 1 Hz.
/// This value captures the raw enumeration (leaf names + filesystem mtimes)
/// exactly once so those consumers share one directory scan.
///
/// Only the *enumeration* is shared. Every consumer keeps its own suffix, TTL,
/// `.tmp-`, and dotfile filtering, and still reads each file's contents fresh —
/// so results are byte-identical to independently re-scanning. Consumers that
/// are handed a listing skip their own `contentsOfDirectory`; consumers called
/// without one (existing direct callers and tests) self-scan exactly as before.
///
/// P15.03 extends this single seam to per-session granularity: the per-origin
/// reader that consumes this listing is where `origin:session_id` fan-out lands.
struct StateDirectoryListing {
	/// One entry per direct child of the scanned directory.
	struct Entry {
		/// The child's leaf name (not a full path), e.g. `claude_code:abc.json`.
		let name: String
		/// Filesystem modification date, or `nil` when `attributesOfItem` failed
		/// for this entry. Consumers apply their own guard: a `nil` mtime is
		/// treated exactly as each consumer treated a failed per-file stat before
		/// (the TTL reader falls through and still decodes; the gate reader and
		/// newest-file resolver skip the entry).
		let mtime: Date?
	}

	let entries: [Entry]

	/// Enumerate `dirPath` once, pre-fetching each child's mtime.
	///
	/// Returns `nil` when the directory cannot be listed (absent or unreadable),
	/// so callers can preserve their existing "directory missing" branch distinct
	/// from a present-but-empty directory (which yields `entries == []`).
	static func scan(
		at dirPath: String,
		fileManager: FileManager = .default
	) -> StateDirectoryListing? {
		guard let names = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
			return nil
		}
		let entries = names.map { name -> Entry in
			let fullPath = (dirPath as NSString).appendingPathComponent(name)
			let mtime = (try? fileManager.attributesOfItem(atPath: fullPath))?[.modificationDate] as? Date
			return Entry(name: name, mtime: mtime)
		}
		return StateDirectoryListing(entries: entries)
	}
}

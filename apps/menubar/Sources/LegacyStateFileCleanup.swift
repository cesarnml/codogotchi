import Foundation

/// One-time-in-spirit, safe-to-repeat cleanup of on-disk artifacts from the
/// pre-`state.d/` hook era.
///
/// Phase 15 advisory-observation triage found that `LivePollingDriver`'s
/// single-origin legacy-gate fallback (`resolveRenderedPlatforms`) can bleed
/// one flat `gate.json`/`delivery-context.json` status across every session
/// window of an origin when session-pets is on and multiple concurrent
/// sessions share that origin. A full-repo audit at triage time found no
/// remaining writer for either file anywhere in the CLI/hook or app —
/// `state.json`'s writer (`writeStateAtomic`) likewise has zero call sites in
/// the live hook path, which writes to `state.d/` via `writeSliceAtomic`
/// instead. All three are dead weight that can only exist on disk as leftover
/// artifacts from before the `state.d/` migration.
enum LegacyStateFileCleanup {
	/// Deletes `gate.json` and `delivery-context.json` unconditionally — safe
	/// because nothing in the current CLI/hook or app ever recreates them, so
	/// once removed they stay removed and the legacy fallback they used to
	/// feed can never fire again.
	///
	/// Deletes `state.json` only when `rpg-state.json` already exists.
	/// `rpg-state.json`'s presence proves the CLI's own one-time RPG-progress
	/// migration (`seedRpgState`, schema v8) has already run — that function
	/// reads flat `state.json` as its migration source the first time
	/// `rpg-state.json` is absent. Deleting `state.json` before that migration
	/// has run would erase a tester's pre-migration RPG progress instead of
	/// letting the CLI carry it forward on its next hook invocation.
	///
	/// Every check here is a plain file-existence test, so this is idempotent
	/// and self-healing across repeated calls (e.g. once per app launch): a
	/// tester whose hook hasn't fired yet on first launch after updating
	/// simply has `state.json` cleaned up automatically on a later launch,
	/// once `rpg-state.json` has appeared.
	static func run(dataFolderURL: URL = CodogotchiFolders.dataFolderURL()) {
		let fm = FileManager.default
		try? fm.removeItem(at: dataFolderURL.appendingPathComponent("gate.json"))
		try? fm.removeItem(at: dataFolderURL.appendingPathComponent("delivery-context.json"))

		let rpgStateURL = dataFolderURL.appendingPathComponent("rpg-state.json")
		guard fm.fileExists(atPath: rpgStateURL.path) else { return }
		try? fm.removeItem(at: dataFolderURL.appendingPathComponent("state.json"))
	}
}

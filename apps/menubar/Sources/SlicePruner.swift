import Foundation

/// Deletes long-dead `state.d/` slice files. Every agent session writes its own
/// `origin:session_id.json` slice and nothing ever removes them, so an install
/// accumulates hundreds over time (one machine reached 129). The reader
/// (`StateJsonReader.readPerPlatformDirectory`) ignores any slice whose mtime is
/// older than its 2h staleTTL, so anything past that horizon is pure dead
/// weight — invisible to the renderer, yet still scanned on every poll tick and
/// (before the winner-only rewrite) rewritten en masse by Force Idle / dismiss.
/// Pruning bounds that growth.
enum SlicePruner {
	/// Age past which a slice is considered dead and removable. Comfortably beyond
	/// the reader's 2h mtime staleTTL, so pruning can never delete a slice the
	/// renderer would still display, while still keeping a day of session history.
	static let defaultMaxAge: TimeInterval = 24 * 60 * 60

	/// Deletes `*.json` slices in `dir` whose filesystem mtime is older than
	/// `maxAge`, plus any leftover `.tmp-*` write partials. Returns the number of
	/// files removed. Never throws — a file that resists deletion is left in place
	/// and simply pruned on a later pass.
	@discardableResult
	static func prune(
		at dir: String,
		maxAge: TimeInterval = defaultMaxAge,
		now: Date = Date()
	) -> Int {
		let fm = FileManager.default
		guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
		var deleted = 0
		for name in names {
			let path = (dir as NSString).appendingPathComponent(name)
			// Sweep abandoned atomic-write partials regardless of age.
			if name.hasPrefix(".tmp-") || name.contains(".tmp-") {
				if (try? fm.removeItem(atPath: path)) != nil { deleted += 1 }
				continue
			}
			guard name.hasSuffix(".json"), !name.hasPrefix(".") else { continue }
			guard let attrs = try? fm.attributesOfItem(atPath: path),
				// Directories have no meaningful slice mtime; skip anything that
				// isn't a regular file so a stray `foo.json/` dir is never removed.
				(attrs[.type] as? FileAttributeType) == .typeRegular,
				let mtime = attrs[.modificationDate] as? Date,
				now.timeIntervalSince(mtime) > maxAge
			else { continue }
			if (try? fm.removeItem(atPath: path)) != nil { deleted += 1 }
		}
		return deleted
	}

	/// Removes `session-labels.json` keys whose `origin:session_id` slice no
	/// longer exists in `dir` — the orphan-hygiene half of P15.07's manual-prune
	/// contract, run automatically alongside age-based pruning so a label never
	/// outlives every trace of the session it named. Reads slice filenames via
	/// `StateJsonReader.parseSliceFilename` so the same origin/session-id parsing
	/// (colon-split, `.tmp-`/`.gate.json`/`.context.json` exclusion) governs both
	/// the slice sweep and the label sweep. Best-effort: a missing or unreadable
	/// labels file is a no-op, not an error. Returns the number of keys removed.
	///
	/// Only ever considers `origin:session_id` keys for orphaning. A plain-origin
	/// key (e.g. `"vscode"`) or the literal `"combined"` key names a persistent
	/// per-platform rename, not an ephemeral session — it never corresponds to a
	/// slice filename, so treating it the same way would delete it on every
	/// sweep. It has no natural expiry; it lives until the user renames or
	/// clears it.
	@discardableResult
	static func pruneOrphanLabels(dir: String, labelPath: String = SessionLabelStore.path()) -> Int {
		pruneOrphanKeys(dir: dir, storePath: labelPath, remove: SessionLabelStore.removeLabel)
	}

	/// Removes `retrieved-session-labels.json` keys whose `origin:session_id`
	/// slice no longer exists in `dir` — the same orphan-hygiene contract as
	/// `pruneOrphanLabels`, applied to `RetrievedSessionTitleStore`'s cache of
	/// platform-fetched thread titles instead of Codogotchi's own rename
	/// sidecar. Run alongside `pruneOrphanLabels` so neither file outlives
	/// every trace of the session it names.
	@discardableResult
	static func pruneOrphanRetrievedTitles(
		dir: String, storePath: String = RetrievedSessionTitleStore.path()
	) -> Int {
		pruneOrphanKeys(dir: dir, storePath: storePath, remove: RetrievedSessionTitleStore.removeTitle)
	}

	/// Shared orphan-sweep algorithm: reads `storePath` as a `[String: String]`
	/// JSON dict, and removes (via `remove`) every session-keyed
	/// (`"origin:session_id"`, colon-containing) key whose slice is no longer
	/// present in `dir`. Plain-origin keys (e.g. `"vscode"`) or the literal
	/// `"combined"` key name a persistent per-platform value, not an ephemeral
	/// session — they never correspond to a slice filename, so treating them
	/// the same way would delete them on every sweep. Best-effort: a missing
	/// or unreadable store file is a no-op, not an error. Returns the number
	/// of keys removed.
	private static func pruneOrphanKeys(
		dir: String, storePath: String, remove: (String, String) -> Void
	) -> Int {
		let fm = FileManager.default
		let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
		let liveKeys = Set(
			names.compactMap { name -> String? in
				guard let (origin, sessionId) = StateJsonReader.parseSliceFilename(name) else { return nil }
				return makeSessionKey(origin: origin, sessionId: sessionId)
			})
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)),
			let entries = try? JSONDecoder().decode([String: String].self, from: data)
		else { return 0 }
		var removed = 0
		for key in entries.keys where key.contains(":") && !liveKeys.contains(key) {
			remove(key, storePath)
			removed += 1
		}
		return removed
	}
}

/// Runs `SlicePruner.prune` shortly after launch and then on a fixed interval
/// for as long as Codogotchi is alive, so `state.d/` never grows without bound
/// between manual actions. The directory scan and deletes run off the main
/// thread; only the `Timer` scheduling touches it.
@MainActor
final class SlicePruneScheduler {
	private let dir: String
	private let interval: TimeInterval
	private let maxAge: TimeInterval
	private let initialDelay: TimeInterval
	private let queue: DispatchQueue
	private var timer: Timer?

	init(
		dir: String,
		interval: TimeInterval = 30 * 60,
		maxAge: TimeInterval = SlicePruner.defaultMaxAge,
		initialDelay: TimeInterval = 5,
		queue: DispatchQueue = DispatchQueue.global(qos: .utility)
	) {
		self.dir = dir
		self.interval = interval
		self.maxAge = maxAge
		self.initialDelay = initialDelay
		self.queue = queue
	}

	/// Schedule the first prune (after `initialDelay`, off the launch hot path)
	/// and the recurring one. Safe to call once; call `stop()` before re-starting.
	func start() {
		stop()
		DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
			self?.pruneAsync()
		}
		let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
			[weak self] _ in
			Task { @MainActor in self?.pruneAsync() }
		}
		// Idle-hygiene work; a generous tolerance lets the OS coalesce wake-ups.
		timer.tolerance = interval * 0.2
		self.timer = timer
	}

	/// Cancel the recurring prune. Safe to call multiple times.
	func stop() {
		timer?.invalidate()
		timer = nil
	}

	private func pruneAsync() {
		let dir = self.dir
		let maxAge = self.maxAge
		queue.async {
			let count = SlicePruner.prune(at: dir, maxAge: maxAge)
			if count > 0 {
				NSLog("SlicePruneScheduler: pruned %d stale state.d slice(s)", count)
			}
			let removedLabels = SlicePruner.pruneOrphanLabels(dir: dir)
			if removedLabels > 0 {
				NSLog("SlicePruneScheduler: removed %d orphan session-labels.json key(s)", removedLabels)
			}
			let removedTitles = SlicePruner.pruneOrphanRetrievedTitles(dir: dir)
			if removedTitles > 0 {
				NSLog(
					"SlicePruneScheduler: removed %d orphan retrieved-session-labels.json key(s)", removedTitles)
			}
		}
	}
}

import Foundation

/// Writes back to slice files in `state.d/`. Used when the app needs to clear
/// hook-owned state (e.g. dismissing an attention payload so a relaunch does
/// not re-show the bubble).
enum StateJsonWriter {
	/// Clears `attention` and sets `activity_state` to `"idle"` on the currently
	/// displayed slice of each `origins` entry, so a dismissed attention bubble
	/// does not re-show on the next poll or relaunch. Shares the winner-only
	/// mechanics (and rationale) of `forceIdle`: the bubble is drawn for the
	/// winner slice, so clearing that one is sufficient — and rewriting every
	/// session slice would freeze the UI and resurrect aged-out pets by refreshing
	/// their mtimes. Fails silently; the worst outcome is the bubble reappears.
	///
	/// `origins` is one entry for an own/minimalist pet, or the full combined-mode
	/// set for the shared combined window. Runs off the main thread.
	static func dismissAttention(
		at dir: String,
		origins: Set<String>,
		now: Date = Date(),
		staleTTL: TimeInterval = 2 * 60 * 60,
		queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
		completion: (() -> Void)? = nil
	) {
		guard !origins.isEmpty else {
			completion?()
			return
		}
		queue.async {
			resetWinnersToIdle(at: dir, origins: origins, now: now, staleTTL: staleTTL)
			if let completion {
				DispatchQueue.main.async(execute: completion)
			}
		}
	}

	/// Session-precise variant for a session-keyed window: rewrites exactly
	/// `origin:sessionId.json`, never a sibling session's slice. See
	/// `resetExactSliceToIdle` for why no winner-selection scan is needed here.
	static func dismissAttention(
		at dir: String,
		origin: String,
		sessionId: String,
		now: Date = Date(),
		staleTTL: TimeInterval = 2 * 60 * 60,
		queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
		completion: (() -> Void)? = nil
	) {
		queue.async {
			resetExactSliceToIdle(at: dir, origin: origin, sessionId: sessionId, now: now, staleTTL: staleTTL)
			if let completion {
				DispatchQueue.main.async(execute: completion)
			}
		}
	}

	/// Escape hatch for a pet stuck in a non-idle animation because a prompt
	/// failed (rate limit) or was manually stopped, so the hook never emitted a
	/// terminal event and `state.d/` still names the stale in-flight state.
	///
	/// Rewrites ONLY the *currently-displayed* slice of each target origin — the
	/// freshest (max `updated_at`) slice with a non-stale mtime, exactly the
	/// "winner" `StateJsonReader.readPerPlatformDirectory` picks. This is
	/// deliberately narrow, because a real `state.d/` accumulates one slice per
	/// session (hundreds of files): rewriting them all would (1) freeze the UI on
	/// a storm of atomic writes, and (2) refresh the mtime of long-stale slices,
	/// resurrecting pets whose windows had already aged out past the reader's 2h
	/// mtime TTL. Touching only the visible winner avoids both.
	///
	/// `origins` scopes the reset: one entry for an own/minimalist pet, or the full
	/// set of combined-mode origins for the shared combined window. The directory
	/// scan + writes run off the main thread so the click never stutters.
	static func forceIdle(
		at dir: String,
		origins: Set<String>,
		now: Date = Date(),
		staleTTL: TimeInterval = 2 * 60 * 60,
		queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
		completion: (() -> Void)? = nil
	) {
		guard !origins.isEmpty else {
			completion?()
			return
		}
		queue.async {
			resetWinnersToIdle(at: dir, origins: origins, now: now, staleTTL: staleTTL)
			if let completion {
				DispatchQueue.main.async(execute: completion)
			}
		}
	}

	/// Session-precise variant for a session-keyed window: rewrites exactly
	/// `origin:sessionId.json`, never a sibling session's slice. Fixes the
	/// P15.04 advisory observation where right-clicking Force Idle on one
	/// session window could reset a fresher sibling session's animation for
	/// up to one polling period, because the origin-scoped overload's
	/// freshest-wins selection can't distinguish which session the user
	/// actually clicked. See `resetExactSliceToIdle` for why no scan is
	/// needed once the exact session id is known.
	static func forceIdle(
		at dir: String,
		origin: String,
		sessionId: String,
		now: Date = Date(),
		staleTTL: TimeInterval = 2 * 60 * 60,
		queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
		completion: (() -> Void)? = nil
	) {
		queue.async {
			resetExactSliceToIdle(at: dir, origin: origin, sessionId: sessionId, now: now, staleTTL: staleTTL)
			if let completion {
				DispatchQueue.main.async(execute: completion)
			}
		}
	}

	/// Finds the winner slice (freshest `updated_at`, non-stale mtime) for each
	/// origin in `origins` and rewrites just those to idle. Runs synchronously on
	/// the caller's queue; `forceIdle` dispatches it off-main.
	private static func resetWinnersToIdle(
		at dir: String,
		origins: Set<String>,
		now: Date,
		staleTTL: TimeInterval
	) {
		let fm = FileManager.default
		guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }

		// Per target origin, track the freshest slice by `updated_at`.
		var winners: [String: (date: Date, url: URL, root: [String: Any])] = [:]
		for name in names {
			guard name.hasSuffix(".json"), !name.hasPrefix(".") else { continue }
			let path = (dir as NSString).appendingPathComponent(name)
			let url = URL(fileURLWithPath: path)
			// Skip slices the reader would ignore as stale, so we never refresh a
			// long-dead slice's mtime and resurrect an aged-out pet.
			if let attrs = try? fm.attributesOfItem(atPath: path),
				let mtime = attrs[.modificationDate] as? Date,
				now.timeIntervalSince(mtime) > staleTTL
			{
				continue
			}
			guard let data = try? Data(contentsOf: url),
				let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
			else { continue }
			let sliceOrigin = ((root["source_event"] as? [String: Any])?["origin"] as? String)?
				.trimmingCharacters(in: .whitespaces)
			guard let sliceOrigin, origins.contains(sliceOrigin) else { continue }
			let updatedAt = (root["updated_at"] as? String)
				.flatMap { StateJsonReader.parseISO8601Date($0) } ?? .distantPast
			if let existing = winners[sliceOrigin], existing.date >= updatedAt { continue }
			winners[sliceOrigin] = (updatedAt, url, root)
		}

		for winner in winners.values {
			var root = winner.root
			root["activity_state"] = "idle"
			root.removeValue(forKey: "attention")
			guard let out = try? JSONSerialization.data(
				withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
			else { continue }
			try? out.write(to: winner.url, options: .atomic)
		}
	}

	/// Rewrites exactly the `origin:sessionId.json` slice back to idle. Unlike
	/// `resetWinnersToIdle`'s freshest-wins scan — which exists because a
	/// collapsed/combined window has no single session to name — a
	/// session-keyed window's render key already IS the exact identity, so
	/// there is no ambiguity to resolve: `state.d/` slice filenames are
	/// `origin:session_id.json` (filename-authoritative, matching
	/// `StateJsonReader.parseSliceFilename`'s colon-split convention), so this
	/// reads/writes exactly one file with no directory scan.
	private static func resetExactSliceToIdle(
		at dir: String,
		origin: String,
		sessionId: String,
		now: Date,
		staleTTL: TimeInterval
	) {
		let fm = FileManager.default
		let path = (dir as NSString).appendingPathComponent("\(origin):\(sessionId).json")
		// Skip a slice the reader would already ignore as stale, so we never
		// refresh a long-dead slice's mtime and resurrect an aged-out pet.
		if let attrs = try? fm.attributesOfItem(atPath: path),
			let mtime = attrs[.modificationDate] as? Date,
			now.timeIntervalSince(mtime) > staleTTL
		{
			return
		}
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return }
		root["activity_state"] = "idle"
		root.removeValue(forKey: "attention")
		guard let out = try? JSONSerialization.data(
			withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
		else { return }
		try? out.write(to: URL(fileURLWithPath: path), options: .atomic)
	}
}

import Foundation

/// Where a `state.d/` slice sits in the session lifecycle, mirroring the
/// stages `StateJsonReader`/`SlicePruner` already implement but never surface:
///
/// - `active`: rendered or renderable right now — the same set Show/Hide All
///   Pets acts on. A window currently in the pool, or a *hidden* key whose
///   slice is still within the "Archive Session After Idle" window — hidden
///   either by the user ("Hide Pet") or by the "Hide Idle Pet After"
///   idle-dismiss TTL (`FloatingPetWindowPool.ttlDismissedWindowKeys`); both
///   mean "still here, just concealed" and carry a Show affordance.
/// - `live`: fresh (within the "Archive Session After Idle" window, default
///   2h) but not rendered and not merely concealed — never spawned, mode
///   off, or folded into a Combined panel — an explicit Show resurrects it
///   via `StateJsonWriter.refreshForShow`.
/// - `archived`: past the "Archive Session After Idle" window but short of
///   the "Prune Archived Sessions" deletion horizon (default 24h), which
///   `SlicePruner`'s background sweep honors too. Still resurrectable via
///   Show (which re-freshens the slice's mtime), or removable outright via
///   Prune.
///
/// Both TTLs are user-configurable via the Settings → Sessions tab pickers
/// and persist to `customization.json`; see `CustomizationTabViewModel`'s
/// `archiveSessionAfterIdleSeconds`/`pruneArchivedSessionsAfterSeconds`.
enum SessionTier {
	case active
	case live
	case archived
}

/// One row in the Sessions panel: a single `state.d/` slice, identified by
/// its window key (`origin`, `origin:session_id`, or the fallback plain
/// origin for a filename with no session id).
struct SessionRow: Identifiable {
	let id: WindowKey
	let origin: String
	let sessionId: String?
	let displayLabel: String
	let tier: SessionTier
	/// Only meaningful for `.active` rows: `true` when the window is
	/// currently rendered (Hide is the available action), `false` when it is
	/// user-hidden but still resurrectable (Show is the available action).
	let isShown: Bool
	let ageSeconds: TimeInterval
	/// Whether Show would surface *this* slice's own window (session pets on)
	/// or the fold window this slice currently owns (sessions off / Combined).
	/// False when Show would only unhide a shared fold already displaying a
	/// different winner — a no-op from the user's POV.
	let canShow: Bool
	/// Raw ISO 8601 `session_started_at` stamp read straight off the slice
	/// (v10+, best-effort — absent on ≤v9 slices and any v10 slice the hook
	/// didn't stamp). `nil` renders the row exactly as it did before P20.03:
	/// never fabricated from `updated_at`. See `SessionRowView.subtitleText`
	/// for how this becomes the "Started · 2h ago" fragment.
	let sessionStartedAt: String?

	/// Explicit memberwise init (rather than the compiler-synthesized one) so
	/// `sessionStartedAt` can default to `nil` for the handful of call sites
	/// that predate P20.03 (`MenubarMenu.fallbackActiveRows`) without having
	/// to touch them.
	init(
		id: WindowKey, origin: String, sessionId: String?, displayLabel: String,
		tier: SessionTier, isShown: Bool, ageSeconds: TimeInterval, canShow: Bool,
		sessionStartedAt: String? = nil
	) {
		self.id = id
		self.origin = origin
		self.sessionId = sessionId
		self.displayLabel = displayLabel
		self.tier = tier
		self.isShown = isShown
		self.ageSeconds = ageSeconds
		self.canShow = canShow
		self.sessionStartedAt = sessionStartedAt
	}
}

/// Backs the Settings → Sessions tab: a disk scan of `state.d/` bucketed into
/// the three tiers above, cross-referenced against `FloatingPetWindowPool`'s
/// live window/hidden-key sets for the `.active` tier, plus the bulk/per-row
/// actions the panel exposes (Show, Hide, Show All Live, Prune Archived).
///
/// Not annotated `@MainActor` at the class level — only the methods that
/// touch the (MainActor-isolated) `pool` are — so a plain `SessionsTabViewModel()`
/// default argument stays usable from `SettingsWindowController`'s nonisolated
/// init parameter list, mirroring `MenubarMenu`'s equivalent `floatingPetPool`
/// wiring.
final class SessionsTabViewModel {
	/// Settings → Sessions "Archive Session After Idle" TTL: a slice younger
	/// than this is still Active/Live; read fresh from `customization.json` on
	/// every access (not cached) since a picker change in the same window must
	/// take effect on the very next `refresh()`.
	private var liveTTL: TimeInterval {
		TimeInterval(CustomizationJsonReader.read(at: customizationPath).archiveSessionAfterIdleSeconds)
	}
	/// Settings → Sessions "Prune Archived Sessions" TTL: a slice older than
	/// this has already been (or is about to be) deleted from disk by
	/// `SlicePruner`, which reads the same persisted value.
	private var archiveTTL: TimeInterval {
		TimeInterval(
			CustomizationJsonReader.read(at: customizationPath).pruneArchivedSessionsAfterSeconds)
	}

	private let stateDirectoryPath: String
	private let customizationPath: String
	private weak var pool: FloatingPetWindowPool?
	private let refreshTtlForShow: (WindowKey) -> Void
	/// Keys `show(key:)` most recently un-hid, still waiting on the pool's
	/// next `update()` tick to actually respawn the window and populate
	/// `activeOrigins`. Bridges the one-refresh gap where the key is in
	/// neither `activeOrigins` nor `hiddenWindowKeys` (see `refresh()`),
	/// which would otherwise misclassify a freshly-shown Active row as Live.
	/// Cleared as soon as `activeOrigins`/`hiddenWindowKeys` catch up.
	private var pendingShowKeys: Set<WindowKey> = []

	private(set) var activeRows: [SessionRow] = []
	private(set) var liveRows: [SessionRow] = []
	private(set) var archivedRows: [SessionRow] = []

	init(
		stateDirectoryPath: String = CodogotchiFolders.stateDirectoryPath(),
		customizationPath: String = CodogotchiFolders.customizationPath(),
		pool: FloatingPetWindowPool? = nil,
		refreshTtlForShow: @escaping (WindowKey) -> Void = { _ in }
	) {
		self.stateDirectoryPath = stateDirectoryPath
		self.customizationPath = customizationPath
		self.pool = pool
		self.refreshTtlForShow = refreshTtlForShow
		// Not calling `refresh()` here: it touches the MainActor-isolated
		// `pool`, and this initializer must stay nonisolated so a plain
		// `SessionsTabViewModel()` remains usable as a default argument value
		// (see the class-level note above). Rows start empty; every real
		// caller (`SettingsWindowController.openWindow`, and the tab-select
		// handler) explicitly calls `refresh()` before the view reads rows.
	}

	/// Re-scans `state.d/` and re-buckets every slice. Cheap enough to call on
	/// every tab show/select and after every action — one directory listing
	/// plus a stat per entry, plus (P20.03) one lightweight `session_started_at`
	/// read per surviving candidate for the Sessions "Started" subtitle; no
	/// other file contents are read.
	@MainActor
	func refresh() {
		guard let listing = StateDirectoryListing.scan(at: stateDirectoryPath) else {
			activeRows = []
			liveRows = []
			archivedRows = []
			return
		}

		let now = Date()
		// Read once per pass rather than per row: both are a fresh
		// `customization.json` decode, so pull the current values a single
		// time and reuse them across every slice in this scan.
		let liveTTL = self.liveTTL
		let archiveTTL = self.archiveTTL
		let activeWindowKeys = Set(pool?.activeOrigins ?? [])
		let hiddenWindowKeys = Set(pool?.hiddenWindowKeys ?? [])
		let ttlDismissedKeys = pool?.ttlDismissedWindowKeys ?? []

		var active: [SessionRow] = []
		var live: [SessionRow] = []
		var archived: [SessionRow] = []

		for entry in listing.entries {
			guard let (origin, parsedSessionId) = StateJsonReader.parseSliceFilename(entry.name),
				let mtime = entry.mtime
			else { continue }

			let age = now.timeIntervalSince(mtime)
			let isSessionKeyed = parsedSessionId != "default"
			let key: WindowKey =
				isSessionKeyed ? .session(origin: origin, id: parsedSessionId) : .origin(origin)

			let renderedKey = pool?.renderedWindowKey(for: key) ?? key
			let resolvedIdentity = pool?.resolvedIdentity(forWindowKey: renderedKey)
			let ownsRenderedTarget = resolvedIdentity.map { $0 == key } ?? (renderedKey == key)
			// Show is only honest when this slice owns its render target (or *is*
			// the target). Sessions-off / Combined Live siblings of the current
			// fold winner cannot be surfaced without changing winner election —
			// offering Show there is a silent no-op.
			let canShow = renderedKey == key || ownsRenderedTarget
			let isRendered = activeWindowKeys.contains(key)
				|| (ownsRenderedTarget && activeWindowKeys.contains(renderedKey))
			let isHiddenByUser = hiddenWindowKeys.contains(key)
				|| (ownsRenderedTarget && hiddenWindowKeys.contains(renderedKey))
			let isPendingShow = pendingShowKeys.contains(key)
			let isTtlDismissed = ttlDismissedKeys.contains(key)
				|| (ownsRenderedTarget && ttlDismissedKeys.contains(renderedKey))
			let lifecycle = SessionLifecycle.classify(
				age: age,
				isRendered: isRendered,
				isConcealed: isHiddenByUser || isPendingShow || isTtlDismissed,
				liveTTL: liveTTL,
				archiveTTL: archiveTTL)
			// Past SlicePruner's deletion horizon: this slice is either already
			// gone or about to be swept on the next prune pass. Nothing to show.
			guard lifecycle != .pruned else { continue }

			let label =
				pool?.sessionDisplayLabel(forWindowKey: key, origin: origin)
				?? FloatingPetWindowPool.defaultSessionLabel(forOrigin: origin)
				?? origin
			let sessionId = isSessionKeyed ? parsedSessionId : nil
			let filePath = (stateDirectoryPath as NSString).appendingPathComponent(entry.name)
			let sessionStartedAt = StateJsonReader.readSessionStartedAt(atPath: filePath)

			switch lifecycle {
			case .pruned:
				continue
			case .active:
				if isRendered {
					pendingShowKeys.remove(key)
					active.append(
						SessionRow(
							id: key, origin: origin, sessionId: sessionId, displayLabel: label,
							tier: .active, isShown: true, ageSeconds: age, canShow: canShow,
							sessionStartedAt: sessionStartedAt))
				} else if isHiddenByUser {
					pendingShowKeys.remove(key)
					active.append(
						SessionRow(
							id: key, origin: origin, sessionId: sessionId, displayLabel: label,
							tier: .active, isShown: false, ageSeconds: age, canShow: canShow,
							sessionStartedAt: sessionStartedAt))
				} else if isPendingShow {
					active.append(
						SessionRow(
							id: key, origin: origin, sessionId: sessionId, displayLabel: label,
							tier: .active, isShown: true, ageSeconds: age, canShow: canShow,
							sessionStartedAt: sessionStartedAt))
				} else {
					// Hidden by the "Hide Idle Pet After" idle-dismiss TTL rather
					// than by the user — same Active (hidden) treatment: the pet is
					// still here, just concealed, and Show resurrects it. Checked
					// after `isPendingShow` so a just-clicked Show reads as shown
					// during the one-tick respawn gap, not as hidden again.
					active.append(
						SessionRow(
							id: key, origin: origin, sessionId: sessionId, displayLabel: label,
							tier: .active, isShown: false, ageSeconds: age, canShow: canShow,
							sessionStartedAt: sessionStartedAt))
				}
			case .live:
				live.append(
					SessionRow(
						id: key, origin: origin, sessionId: sessionId, displayLabel: label,
						tier: .live, isShown: false, ageSeconds: age, canShow: canShow,
						sessionStartedAt: sessionStartedAt))
			case .archived:
				archived.append(
					SessionRow(
						id: key, origin: origin, sessionId: sessionId, displayLabel: label,
						tier: .archived, isShown: false, ageSeconds: age, canShow: canShow,
						sessionStartedAt: sessionStartedAt))
			}
		}

		activeRows = active.sorted { $0.displayLabel < $1.displayLabel }
		liveRows = live.sorted { $0.ageSeconds < $1.ageSeconds }
		archivedRows = archived.sorted { $0.ageSeconds < $1.ageSeconds }
	}

	/// Un-hides `key` and restarts its dismiss-TTL clock first — the same
	/// two-step "Show" contract the menubar's "Show … Pet" items use, so a
	/// slice that aged out re-spawns instead of silently staying suppressed.
	/// Works uniformly for a hidden Active row, a Live row, or an Archived
	/// row (whose stale mtime `refreshForShow` re-freshens).
	@MainActor
	func show(key: WindowKey) {
		let renderedKey = pool?.renderedWindowKey(for: key) ?? key
		refreshTtlForShow(renderedKey)
		pendingShowKeys.insert(key)
		pool?.setVisible(true, for: renderedKey)
		refresh()
	}

	/// Hides a currently-rendered Active row.
	@MainActor
	func hide(key: WindowKey) {
		pool?.setVisible(false, for: pool?.renderedWindowKey(for: key) ?? key)
		refresh()
	}

	/// Show-and-resurrect every Live row the Settings "Show All Live" bulk
	/// action can honestly surface:
	/// - `canShow` rows (session-keyed window, or fold ownership) — same as a
	///   per-row Show;
	/// - sessions-off / Combined fold targets that the menubar promotes as
	///   "Show … Panel" from otherwise `canShow == false` Live rows (see
	///   `MenubarMenu.supplementalUnrenderedPanelRows`). Without this limb,
	///   Show All Live is a silent no-op for off-platform panels while
	///   "Show Cursor Panel" still works.
	@MainActor
	func showAllLive() {
		var promotedTargets: Set<WindowKey> = []

		for row in liveRows where row.canShow {
			let renderedKey = pool?.renderedWindowKey(for: row.id) ?? row.id
			refreshTtlForShow(renderedKey)
			pendingShowKeys.insert(row.id)
			pool?.setVisible(true, for: renderedKey)
			promotedTargets.insert(renderedKey)
		}

		if let pool {
			// liveRows are age-sorted ascending — first hit per fold target is
			// the freshest Live slice, matching refreshWinnersForShow's election.
			for row in liveRows where !row.canShow {
				guard pool.usesPanelAffordance(for: row.id) else { continue }
				let target = pool.renderedWindowKey(for: row.id)
				guard !pool.activeOrigins.contains(target) else { continue }
				guard promotedTargets.insert(target).inserted else { continue }
				refreshTtlForShow(target)
				pendingShowKeys.insert(row.id)
				pool.setVisible(true, for: target)
			}
		}

		refresh()
	}

	/// Deletes every Archived slice from disk outright — a manual
	/// `SlicePruner` pass with a lower horizon than its usual 24h, so it
	/// catches everything past the 2h fresh window instead of waiting for
	/// the 24h auto-prune.
	@MainActor
	func pruneArchivedNow() {
		SlicePruner.prune(at: stateDirectoryPath, maxAge: self.liveTTL)
		refresh()
	}

	/// Deletes one row's backing slice file outright, without refreshing —
	/// the shared primitive behind `prune(row:)` and the bulk Live/Archived
	/// prune actions, which each own their own single trailing `refresh()`
	/// rather than one per row.
	@MainActor
	private func deleteSlice(for row: SessionRow) {
		let filename =
			row.sessionId.map { "\(WindowKey.session(origin: row.origin, id: $0).rawValue).json" }
			?? "\(row.origin).json"
		let path = (stateDirectoryPath as NSString).appendingPathComponent(filename)
		try? FileManager.default.removeItem(atPath: path)
	}

	/// Deletes one row's backing slice file outright.
	@MainActor
	func prune(row: SessionRow) {
		deleteSlice(for: row)
		refresh()
	}

	/// Deletes every Live row's backing slice file outright — the "Prune All
	/// Live" bulk action, mirroring `pruneArchivedNow()`'s ungated raw
	/// deletion since Live rows (fresh but not rendered) have no pool window
	/// to tear down through `pruneSession`.
	@MainActor
	func pruneAllLive() {
		for row in liveRows {
			deleteSlice(for: row)
		}
		refresh()
	}

	/// Prunes an Active row through the pool's `pruneSession`, the same
	/// four-store cleanup (slice, free-list number, rename label, cached
	/// title) the right-click "Prune Session" affordance performs — unlike
	/// `prune(row:)` above, which only deletes the slice file and is used for
	/// windowless Archived rows. A no-op if `row` isn't session-keyed (the
	/// pool's own `isSessionKeyed` guard), mirroring the affordance's
	/// `hasActiveSessionBadge` gate.
	@MainActor
	func pruneActive(row: SessionRow) {
		pool?.pruneSession(windowKey: row.id, stateDirectory: stateDirectoryPath)
		refresh()
	}

	/// Prunes every session-keyed Active row through the pool's
	/// `pruneSession` — the "Prune All Active" bulk action. Skips
	/// plain-origin/"combined" Active rows, mirroring the per-row Prune
	/// button's `row.sessionId != nil` gate: those aren't sessions to prune,
	/// they're the platform's own always-present window.
	@MainActor
	func pruneAllActive() {
		for row in activeRows where row.sessionId != nil {
			pool?.pruneSession(windowKey: row.id, stateDirectory: stateDirectoryPath)
		}
		refresh()
	}

	/// Prunes every row across all three tiers in one pass — the top-level
	/// "Prune All Sessions" affordance. Composes the same per-tier primitives
	/// `pruneAllActive()`/`pruneAllLive()`/`pruneArchivedNow()` use, with a
	/// single trailing `refresh()` rather than three.
	@MainActor
	func pruneAllSessions() {
		for row in activeRows where row.sessionId != nil {
			pool?.pruneSession(windowKey: row.id, stateDirectory: stateDirectoryPath)
		}
		for row in liveRows {
			deleteSlice(for: row)
		}
		SlicePruner.prune(at: stateDirectoryPath, maxAge: self.liveTTL)
		refresh()
	}
}

import CoreGraphics
import Foundation

/// Executes a `WindowDiff` against real `FloatingPetWindowControlling`
/// controllers. Lives outside `Pool/Derive/` (unlike `PoolDiff`) because it
/// drives the AppKit-adjacent `FloatingPetWindowControlling` protocol and
/// reads live controller state (`currentFrame`) at execution time.
///
/// Zero policy decisions: every call here is a mechanical translation of
/// `WindowDiff`/`DesiredWindow` data into a controller method — any "should
/// we..." branch belongs in `PoolDerive`, not here (see the ticket's Review
/// Focus).
@MainActor
enum PoolApply {
	/// - Parameters:
	///   - diff: this tick's spawn/dismiss/update partitioning.
	///   - controllers: the live controller table, keyed by `WindowKey`.
	///     Mutated in place: spawned controllers are inserted, dismissed ones
	///     removed.
	///   - spawn: builds a fresh controller for a `toSpawn` entry. Left
	///     injectable (rather than calling a concrete factory here) so this
	///     mechanical layer stays agnostic to Own/Minimalist renderer choice
	///     and to `MenubarApp`'s actual window-construction wiring — the
	///     caller decides which factory to use from `DesiredWindow.isMinimalist`.
	static func apply(
		diff: WindowDiff,
		controllers: inout [WindowKey: FloatingPetWindowControlling],
		spawn: (WindowKey, DesiredWindow) -> FloatingPetWindowControlling
	) {
		// Read every spawn's inherited-frame donor's live on-screen frame
		// BEFORE any teardown below removes it from `controllers` — a donor
		// evicted the very same tick it hands off its frame is exactly the
		// concurrent spawn+teardown this ordering must survive (see
		// `PoolApplyTests.testFreshSpawnAdoptsDonorsLiveFrameReadAtExecutionTime`).
		var adoptedFrames: [WindowKey: CGRect] = [:]
		for (key, window) in diff.toSpawn {
			guard let donorKey = window.inheritedFrameFrom, let donor = controllers[donorKey] else { continue }
			adoptedFrames[key] = donor.currentFrame
		}

		for key in diff.toDismiss {
			controllers[key]?.setFloatingPetVisible(false)
			controllers.removeValue(forKey: key)
		}

		for (key, window) in diff.toSpawn {
			let controller = spawn(key, window)
			controllers[key] = controller
			controller.setFloatingPetVisible(true)
			if let frame = adoptedFrames[key] {
				controller.adoptFrame(frame)
			}
			push(window, key: key, to: controller)
		}

		for (key, window) in diff.toUpdate {
			guard let controller = controllers[key] else {
				assertionFailure("PoolApply.apply: toUpdate has no live controller for \(key) — caller state is inconsistent with the diff")
				continue
			}
			push(window, key: key, to: controller)
		}
	}

	/// Every `DesiredWindow` push-payload field, straight to its controller
	/// method — see the ticket's Review Focus on push completeness.
	/// Deliberately excluded (documented in the ticket's Rationale, not
	/// silently dropped):
	/// - `isMinimalist` — a spawn-time factory choice the `spawn` closure's
	///   caller makes, not a per-tick push.
	/// - `petId` / `replacePets(codexPet:codogotchiPet:)` — resolving a pet
	///   id into concrete `CodexPet`/`CodogotchiPet` assets is outside
	///   `DesiredWindow`'s data (needs a pet catalog lookup); deferred.
	private static func push(_ window: DesiredWindow, key: WindowKey, to controller: FloatingPetWindowControlling) {
		controller.apply(state: window.activityState, visualMode: .normal)
		controller.applyPromptTimerPresentation(window.promptTimerStatus)
		controller.applyAttention(payload: window.attention, sourceEvent: window.attentionSourceEvent)
		controller.applyGateBadge(content: window.gateBadge)
		controller.applyPlatform(origin: window.platformChip)
		controller.applyRPGState(
			halfHearts: window.rpgSnapshot.halfHearts,
			levelFraction: window.rpgSnapshot.levelFraction,
			level: window.rpgSnapshot.level,
			activeMinutes: window.rpgSnapshot.activeMinutes,
			hudEnabled: window.hudEnabled
		)
		// The combined window is never session-keyed — its push site never
		// calls `applySessionNumber` at all (unlike a direct key, where it's
		// always called, even to push `nil`).
		if key != .combined {
			controller.applySessionNumber(window.sessionNumber)
		}
		controller.applyHasActiveSession(window.hasActiveSession)
		controller.applySessionLabel(window.sessionLabel)
		controller.applySessionTooltip(window.sessionTooltip)
		controller.applyConflictBubble(window.conflictBubble)
	}

	// MARK: - Title resolution (disk cache read-through + write-through)

	/// Resolves `requests` (the `(origin, session_id)` identities `derive`
	/// flagged this tick via `DesiredWindows.titleResolutionRequests`) into
	/// their platform-auto-generated thread titles, reusing the same
	/// in-flight/on-disk caches `FloatingPetWindowPool.resolveSessionTitle`
	/// already established: `RetrievedSessionTitleStore` for the disk
	/// cache (checked first — cheap, no subprocess), falling through to
	/// `SessionTitleResolver` (a directory walk / sqlite3 subprocess / file
	/// read depending on origin) only on a cache miss, writing a freshly
	/// resolved title straight back through so a later tick or relaunch
	/// never re-pays that cost. Results are keyed by identity, not
	/// `WindowKey`, so the caller can fold them into next tick's
	/// `PoolMemory` however it keys its own resolved-title cache.
	static func resolveTitles(
		requests: [RenderKeyIdentity],
		readCachedTitle: (RenderKeyIdentity) -> String? = { identity in
			RetrievedSessionTitleStore.title(for: cacheKey(for: identity))
		},
		resolveTitle: (RenderKeyIdentity) -> String? = { identity in
			SessionTitleResolver.title(forOrigin: identity.origin, sessionId: identity.sessionId)
		},
		writeCachedTitle: (RenderKeyIdentity, String) -> Void = { identity, title in
			RetrievedSessionTitleStore.setTitle(title, for: cacheKey(for: identity))
		}
	) -> [RenderKeyIdentity: String] {
		var resolved: [RenderKeyIdentity: String] = [:]
		for identity in requests {
			if let cached = readCachedTitle(identity) {
				resolved[identity] = cached
				continue
			}
			guard let title = resolveTitle(identity) else { continue }
			writeCachedTitle(identity, title)
			resolved[identity] = title
		}
		return resolved
	}

	/// `RetrievedSessionTitleStore`'s key convention: byte-identical to the
	/// session-keyed `WindowKey.rawValue` for this identity
	/// (`"\(origin):\(sessionId)"`).
	private nonisolated static func cacheKey(for identity: RenderKeyIdentity) -> String {
		WindowKey.session(origin: identity.origin, id: identity.sessionId).rawValue
	}
}

import Foundation

/// Owns "which slices/origins does this window's action touch" — the
/// session / combined / plain-origin targeting policy that used to live
/// duplicated inline in `MenubarApp`'s own-window and minimalist-window
/// factory closures (see ticket P17.05). Both factories construct one
/// shared router and delegate their `onAttentionDismissed` /
/// `onForceIdle` handlers to it, so the targeting asymmetries below are
/// expressed exactly once.
@MainActor
final class WindowActionRouter {
	private let stateDir: () -> String
	private let resetPromptTimer: (WindowKey) -> Void
	private let combinedModeOrigins: () -> [String]
	private let clearAttentionBubbles: (WindowKey) -> Void

	init(
		stateDir: @escaping () -> String,
		resetPromptTimer: @escaping (WindowKey) -> Void,
		combinedModeOrigins: @escaping () -> [String],
		clearAttentionBubbles: @escaping (WindowKey) -> Void
	) {
		self.stateDir = stateDir
		self.resetPromptTimer = resetPromptTimer
		self.combinedModeOrigins = combinedModeOrigins
		self.clearAttentionBubbles = clearAttentionBubbles
	}

	/// Resolves a window's `state.d/` origins for the winner-only writers
	/// (`forceIdle` / `dismissAttention`). The shared combined window folds
	/// every combined-mode origin into one pet, so it expands to that live
	/// set; any other window key (plain origin or per-session
	/// `origin:session_id`) resolves to its owning origin, whose winner
	/// slice the writers target.
	func resolveWindowOrigins(_ windowKey: WindowKey) -> Set<String> {
		if windowKey == .combined {
			return Set(combinedModeOrigins())
		}
		return [windowKey.origin]
	}

	/// Persist the dismiss/focus so the next poll tick does not re-read the
	/// still-present `attention` and re-show the bubble. Focus/dismiss on a
	/// session-keyed window can only act on the platform app as a whole (no
	/// window-level API names a specific agent thread), so it idles every
	/// sibling session's slice for that origin, not just the clicked one,
	/// and clears their bubbles immediately rather than waiting a poll
	/// tick. A plain-origin or combined window has no single session to
	/// name, so it clears the winner slice per origin.
	///
	/// `completion` runs on the main queue once the underlying write settles
	/// — production call sites don't need it (the writer is fire-and-forget
	/// against a 1Hz poll loop); tests use it to await the async write
	/// deterministically instead of racing an arbitrary delay.
	func handleAttentionDismissed(for windowKey: WindowKey, completion: (() -> Void)? = nil) {
		// Reset the pool-owned prompt timer before the on-disk rewrite: the
		// reset's real-current-time stamp is what stops a next-tick poll of
		// the pre-rewrite slice from restarting the timer.
		resetPromptTimer(windowKey)
		if let identity = windowKey.sessionIdentity {
			StateJsonWriter.dismissAllSessionsAttention(at: stateDir(), origin: identity.origin, completion: completion)
			clearAttentionBubbles(windowKey)
		} else {
			StateJsonWriter.dismissAttention(
				at: stateDir(), origins: resolveWindowOrigins(windowKey), completion: completion)
		}
	}

	/// Right-click "Force Idle" escape hatch: rewrite this pet's displayed
	/// slice back to idle so a stuck (rate-limited / manually-stopped)
	/// animation clears. A session-keyed window targets exactly its own
	/// slice — never a sibling session's, which right-clicking Force Idle
	/// used to reset if that sibling happened to be the freshest slice for
	/// the origin. A combined window folds several origins into one pet, so
	/// it resets exactly that combined set; a plain own window resets just
	/// its origin's winner slice. Never all slices — that idles unrelated
	/// pets and resurrects aged-out ones by refreshing their mtimes.
	///
	/// `completion` — see `handleAttentionDismissed` above.
	func handleForceIdle(for windowKey: WindowKey, completion: (() -> Void)? = nil) {
		// Pool-tracker reset first — see handleAttentionDismissed above.
		resetPromptTimer(windowKey)
		if let identity = windowKey.sessionIdentity {
			StateJsonWriter.forceIdle(
				at: stateDir(), origin: identity.origin, sessionId: identity.sessionId, completion: completion)
		} else {
			StateJsonWriter.forceIdle(at: stateDir(), origins: resolveWindowOrigins(windowKey), completion: completion)
		}
	}
}

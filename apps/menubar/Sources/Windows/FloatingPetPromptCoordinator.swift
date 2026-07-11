import AppKit

/// Ensures only one right-click prompt (Force Idle / Hide) is visible across
/// every floating panel at once. `NSEvent.addGlobalMonitorForEvents` only
/// reports events from *other* applications, so a right-click on a different
/// in-app panel is invisible to the previous panel's own dismiss-on-click-away
/// monitor — without this coordinator, that previous prompt is stranded on
/// screen (each panel can only dismiss its own). Every presenter asks the
/// coordinator to take over before showing its prompt, which dismisses
/// whichever other panel is currently active, mirroring the same-panel
/// re-right-click behavior the rest of the UI already has.
///
/// Internal (not file-private) so `FloatingInteractionTests` can exercise the
/// owner-handoff logic directly with fake owners — no live window session
/// needed since this class holds no AppKit state of its own.
final class FloatingPetPromptCoordinator {
	static let shared = FloatingPetPromptCoordinator()

	private weak var activeOwner: AnyObject?
	private var activeDismiss: (() -> Void)?

	/// Not `private` so tests can construct isolated instances rather than
	/// sharing mutable state through `.shared` across test methods.
	init() {}

	/// Call immediately before presenting a new prompt. Dismisses any other
	/// panel's currently active prompt, then registers `owner` as active.
	func willPresent(owner: AnyObject, dismiss: @escaping () -> Void) {
		if activeOwner !== owner {
			activeDismiss?()
		}
		activeOwner = owner
		activeDismiss = dismiss
	}

	/// Call whenever `owner` dismisses its own prompt, for any reason, so a
	/// stale dismiss closure is never retained once that prompt is gone.
	func didDismiss(owner: AnyObject) {
		guard activeOwner === owner else { return }
		activeOwner = nil
		activeDismiss = nil
	}
}


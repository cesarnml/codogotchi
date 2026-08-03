import AppKit

/// One place the app asks "may I animate?".
///
/// Reduce Motion is a system-wide accessibility declaration, so it wins by
/// default everywhere. The single per-app override lives in `MotionSettings`;
/// this type only answers what the *system* is asking for, plus the seam that
/// keeps tests off the host's real setting.
enum MotionPolicy {
	/// Shipped behaviour, deliberately a `let` — nothing in the app can repoint it.
	static let systemPrefersReducedMotion: () -> Bool = {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	/// Test-only override. Animation tests must not read the host's real setting
	/// or they fail outright on a machine with Reduce Motion enabled. `nil`
	/// restores shipped behaviour; production never assigns this.
	static var overrideForTesting: (() -> Bool)?

	static func prefersReducedMotion() -> Bool {
		(overrideForTesting ?? systemPrefersReducedMotion)()
	}

	/// Reduce Motion is toggled in System Settings while the app is running, so
	/// every animating view reacts live rather than sampling once at launch.
	///
	/// Block-based with an explicit main queue: AppKit does not promise which
	/// thread posts this, and a selector-based observer would leave `deinit`'s
	/// removal racing an already-dispatched call into a half-freed view.
	static func observeChanges(_ handler: @escaping () -> Void) -> any NSObjectProtocol {
		NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil,
			queue: .main
		) { _ in handler() }
	}

	static func removeObserver(_ token: (any NSObjectProtocol)?) {
		guard let token else { return }
		NSWorkspace.shared.notificationCenter.removeObserver(token)
	}
}

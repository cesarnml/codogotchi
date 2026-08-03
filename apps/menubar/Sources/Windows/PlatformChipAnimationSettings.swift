import Foundation

/// The user's two decisions about the in-flight chip logo animation, travelling
/// together so the pool pushes one value rather than two parallel booleans.
struct PlatformChipAnimationSettings: Equatable {
	/// The Settings > General "Animate platform logo while working" toggle.
	var isEnabled: Bool = false

	/// Explicit per-app opt-out of the system Reduce Motion setting.
	///
	/// Reduce Motion is a system-wide accessibility declaration, so it wins by
	/// default — but a user who is *shown* that it is holding the animation back
	/// and then deliberately asks for the animation anyway has expressed a more
	/// specific intent than the global setting. Only that explicit choice sets
	/// this; nothing infers it.
	var ignoresReduceMotion: Bool = false

	static let disabled = PlatformChipAnimationSettings()

	/// Whether the animation should run, given the current system setting.
	/// The single place the precedence question is answered.
	func allowsMotion(systemPrefersReducedMotion: Bool) -> Bool {
		guard isEnabled else { return false }
		return ignoresReduceMotion || !systemPrefersReducedMotion
	}

	/// Whether the user is in the state worth telling them about: they asked for
	/// the animation, the system is suppressing it, and they have not yet chosen
	/// to override. Drives the Settings > General notice.
	func isSuppressedByReduceMotion(systemPrefersReducedMotion: Bool) -> Bool {
		isEnabled && systemPrefersReducedMotion && !ignoresReduceMotion
	}
}

import Foundation

/// The user's motion-related decisions, travelling together so the pool pushes
/// one value rather than a growing set of parallel booleans.
struct MotionSettings: Equatable {
	/// The Settings > General "Animate platform logo while working" toggle. A
	/// taste preference about one specific animation, not an accessibility one.
	var chipAnimationEnabled: Bool = false

	/// Explicit per-app opt-out of the system Reduce Motion setting, covering
	/// *every* animation the app gates — not just the chip.
	///
	/// Reduce Motion is a system-wide accessibility declaration, so it wins by
	/// default. But a user who is shown that it is holding animations back and
	/// then deliberately asks for them anyway has expressed a more specific
	/// intent than the global setting. Only that explicit choice sets this;
	/// nothing infers it.
	var ignoresReduceMotion: Bool = false

	static let disabled = MotionSettings()

	/// Whether motion that the user has to opt *into* may run — currently just
	/// the platform chip's spin/breathe.
	func allowsChipAnimation(systemPrefersReducedMotion: Bool) -> Bool {
		guard chipAnimationEnabled else { return false }
		return allowsAmbientMotion(systemPrefersReducedMotion: systemPrefersReducedMotion)
	}

	/// Whether always-on decorative motion may run — currently the activity
	/// pill's shimmer sweep. It has no toggle of its own: it is on for everyone
	/// and answers only to Reduce Motion and the override.
	func allowsAmbientMotion(systemPrefersReducedMotion: Bool) -> Bool {
		ignoresReduceMotion || !systemPrefersReducedMotion
	}

	/// Whether the user is in the state worth telling them about: they asked for
	/// the chip animation, the system is suppressing it, and they have not yet
	/// overridden. Drives the Settings > General notice.
	///
	/// Deliberately keyed on the chip toggle rather than on "any motion is
	/// suppressed": the shimmer is on by default, so a Reduce Motion user who
	/// never enabled anything has not been denied something they asked for, and
	/// must not be nagged about it.
	func isSuppressedByReduceMotion(systemPrefersReducedMotion: Bool) -> Bool {
		chipAnimationEnabled && systemPrefersReducedMotion && !ignoresReduceMotion
	}
}

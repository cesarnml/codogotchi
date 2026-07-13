import Foundation

/// Mechanical set-comparison output of `PoolDiff.diff`: this tick's
/// `DesiredWindows.windows` partitioned against the previous tick's rendered
/// `[WindowKey: DesiredWindow]` values, keyed by `WindowKey` membership alone.
///
/// `apply` (outside `Pool/Derive/`, since it drives the AppKit-adjacent
/// `FloatingPetWindowControlling`) is the only consumer that turns this data
/// into controller calls — `diff` itself makes no policy decision about
/// whether a push is "necessary" (see `toUpdate`'s doc).
struct WindowDiff: Equatable {
	/// Desired windows with no current entry: `apply` must spawn a fresh
	/// controller for these. Carries the full `DesiredWindow` value (every
	/// push-payload field, plus `inheritedFrameFrom` as inert pass-through
	/// data) — `apply` never re-derives push data itself.
	var toSpawn: [WindowKey: DesiredWindow] = [:]
	/// Current windows with no desired entry this tick: `apply` must tear
	/// these down.
	var toDismiss: Set<WindowKey> = []
	/// Keys present in both `desired` and `current`. Membership-only: a key
	/// lands here regardless of whether its `DesiredWindow` value actually
	/// changed since the last tick — deciding which specific pushes changed
	/// is `apply`'s field-by-field job, not `diff`'s.
	var toUpdate: [WindowKey: DesiredWindow] = [:]

	init() {}
}

/// Pure set algebra over `WindowKey`, no AppKit dependency (`Pool/Derive/`
/// purity gate). Zero policy branches: every "should this window exist /
/// should it change" decision was already made upstream by `PoolDerive`
/// (P18.01–P18.03) when it built `desired`. `diff` only decides which
/// controller-method family (spawn/dismiss/update) a key falls into this
/// tick.
enum PoolDiff {
	static func diff(desired: DesiredWindows, current: [WindowKey: DesiredWindow]) -> WindowDiff {
		var result = WindowDiff()

		for (key, window) in desired.windows {
			if current[key] != nil {
				result.toUpdate[key] = window
			} else {
				result.toSpawn[key] = window
			}
		}

		for key in current.keys where desired.windows[key] == nil {
			result.toDismiss.insert(key)
		}

		return result
	}
}

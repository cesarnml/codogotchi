import Foundation

/// Where a `state.d/` slice sits in its lifecycle, judged from a single
/// mtime-derived `age` plus the two policy TTLs and the pool's current
/// render/conceal state — the classifier `SessionsTabViewModel` and the
/// menubar pet section (via the shared view-model instance) both resolve
/// against, replacing the inline clock comparisons each used to carry
/// separately. See `classify(age:isRendered:isConcealed:liveTTL:archiveTTL:)`
/// for the precedence and boundary rules.
enum SessionLifecycle: Equatable {
	/// Rendered right now, or concealed (user-hidden, idle-dismissed, or
	/// mid-Show) with a slice still inside the reader-staleness window.
	case active
	/// Fresh (inside the reader-staleness window) but neither rendered nor
	/// concealed — an explicit Show would resurrect it.
	case live
	/// Past the reader-staleness window but short of the prune horizon —
	/// still resurrectable via Show, or removable via Prune.
	case archived
	/// At or past the prune horizon — `SlicePruner`'s sweep already has (or
	/// is about to) delete the backing slice; nothing to show.
	case pruned

	/// Pure classifier: clocks and pool state in, lifecycle state out — no
	/// `Date()`, no I/O. `age`, `liveTTL`, and `archiveTTL` share units
	/// (seconds); callers pass an `age` already computed against their own
	/// `now()`.
	///
	/// Precedence, matching the exact per-branch order this replaces:
	/// 1. `age >= archiveTTL` → `.pruned`, regardless of render/conceal state
	///    (the prune-horizon filter ran before any render check in the code
	///    this classifier extracts from).
	/// 2. `isRendered` → `.active`, unconditionally (a currently-rendered
	///    window is active no matter its slice age).
	/// 3. `isConcealed && age < liveTTL` → `.active` (hidden/idle-dismissed/
	///    pending-show, still within the reader-staleness window).
	/// 4. `age < liveTTL` → `.live`.
	/// 5. otherwise → `.archived`.
	///
	/// Every comparison is strict `<`: exactly-at-TTL is on the "expired"
	/// side, mirroring every inline `age < ttl` check being replaced.
	static func classify(
		age: TimeInterval,
		isRendered: Bool,
		isConcealed: Bool,
		liveTTL: TimeInterval,
		archiveTTL: TimeInterval
	) -> SessionLifecycle {
		guard age < archiveTTL else { return .pruned }
		if isRendered { return .active }
		if isConcealed && age < liveTTL { return .active }
		if age < liveTTL { return .live }
		return .archived
	}
}

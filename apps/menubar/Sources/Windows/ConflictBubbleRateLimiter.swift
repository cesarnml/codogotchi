import Foundation

/// Per-platform rate limiter gating P15.08's conflict bubble. `blockedOrigins`
/// (P15.07) is recomputed fresh on every pool tick, so without this gate a
/// persisting conflict would re-fire (re-front) the bubble on every single
/// tick, including right after the user dismissed it. `shouldShow` answers
/// "may a fresh presentation fire now?"; the caller records the fire via
/// `recordShown` immediately after presenting. In-memory only — resets on
/// relaunch; a post-relaunch re-fire is harmless.
struct ConflictBubbleRateLimiter {
	private static let window: TimeInterval = 3600

	private var lastShownAt: [String: Date] = [:]

	/// True when `origin` has never fired, or its last fire is older than the
	/// one-hour window. Each origin is rate-limited independently.
	func shouldShow(origin: String, now: Date) -> Bool {
		guard let last = lastShownAt[origin] else { return true }
		return now.timeIntervalSince(last) > Self.window
	}

	/// Records that a bubble fired for `origin` at `now`, starting its
	/// one-hour lockout.
	mutating func recordShown(origin: String, now: Date) {
		lastShownAt[origin] = now
	}
}

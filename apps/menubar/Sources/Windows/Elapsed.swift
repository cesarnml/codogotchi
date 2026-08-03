import Foundation

/// What an `ElapsedPresentation` is measuring. The chip slot renders exactly one
/// of these at a time, and the two are mutually exclusive by construction:
/// `PromptTimerTracker.observe` resets to `nil` the moment a slice reads `idle`,
/// so the turn clock is always absent precisely when the idle clock wants the
/// slot. Modelled as an enum rather than a glyph string or a bool so a future
/// third reading (a gate countdown, say) is a compiler-enforced sweep.
enum ElapsedKind: Equatable {
	/// Time spent in the current prompt turn. Owned by `PromptTimerTracker`.
	case turn
	/// Time this session has been quiet. Derived from the slice's `updated_at`
	/// by `IdleElapsed` — no tracker, no in-memory state.
	case idle

	/// SF Symbol for the glyph half of the chip.
	var symbolName: String {
		switch self {
		case .turn: return "timer"
		case .idle: return "zzz"
		}
	}

	var accessibilityDescription: String {
		switch self {
		case .turn: return "Prompt timer"
		case .idle: return "Idle timer"
		}
	}
}

/// Rendered form of either elapsed clock: the compact label, whether it is still
/// advancing (drives the dimmed treatment on a frozen turn clock), and which
/// clock it is.
struct ElapsedPresentation: Equatable {
	let label: String
	let isRunning: Bool
	let kind: ElapsedKind

	init(label: String, isRunning: Bool, kind: ElapsedKind) {
		self.label = label
		self.isRunning = isRunning
		self.kind = kind
	}

	static func compactLabel(elapsed: TimeInterval) -> String {
		let totalSeconds = max(0, Int(elapsed.rounded(.down)))
		let seconds = totalSeconds % 60
		let totalMinutes = totalSeconds / 60
		let minutes = totalMinutes % 60
		let totalHours = totalMinutes / 60

		if totalHours == 0 {
			return "\(minutes):\(String(format: "%02d", seconds))"
		}
		if totalHours < 10 {
			return "\(totalHours)h \(String(format: "%02d", minutes))m"
		}
		if totalHours < 100 {
			return "\(totalHours)h \(minutes)m"
		}

		let days = totalHours / 24
		let hours = totalHours % 24
		return "\(days)d \(hours)h"
	}
}

/// How long the session behind a slice has been quiet.
///
/// Deliberately a pure function, not a peer to `PromptTimerTracker`: there is no
/// `idle_since` stamp to track and nothing to accumulate. The hook *deletes* the
/// three sticky turn clocks when it writes idle (`mergeStickyStamps`), so the
/// slice's own `updated_at` is the only durable anchor — and it is enough,
/// because every path that moves a slice into idle either stamps `updated_at` at
/// that moment (the hook's abort paths) or deliberately leaves it pointing at the
/// agent's last real event (`StateJsonWriter.forceIdle`, which rewrites
/// `activity_state` only). Both readings answer the same question: *how long
/// since this agent last did anything.*
///
/// Being slice-derived rather than scene-derived is what lets the same number
/// render in Minimalist mode, which has no scene and therefore no idle
/// escalation to source a clock from. It also means the number never rewinds:
/// the click-hold gesture calms the sprite (`FloatingPetScene.resetIdleEscalation`)
/// without touching the slice, so badge and sprite report different things on
/// purpose — "this session has been quiet 42m" versus "you last reassured me
/// 12m ago".
enum IdleElapsed {
	/// `nil` unless the slice is idle and carries a parseable `updated_at` — a
	/// working, standby, or errored session has a turn clock in the slot
	/// instead, and an unparseable stamp yields no chip rather than a wrong one.
	static func presentation(
		activityState: ActivityState,
		updatedAt: String?,
		now: Date = Date()
	) -> ElapsedPresentation? {
		guard activityState == .idle,
			let updatedAt,
			let since = StateJsonReader.parseISO8601Date(updatedAt)
		else { return nil }
		return ElapsedPresentation(
			label: ElapsedPresentation.compactLabel(elapsed: max(0, now.timeIntervalSince(since))),
			isRunning: true,
			kind: .idle
		)
	}
}

import Foundation

struct PromptTimerStatus: Equatable {
	let startedAt: Date
	let endedAt: Date?

	var isRunning: Bool { endedAt == nil }

	func elapsed(now: Date = Date()) -> TimeInterval {
		max(0, (endedAt ?? now).timeIntervalSince(startedAt))
	}

	func presentation(now: Date = Date()) -> PromptTimerPresentation {
		PromptTimerPresentation(
			label: PromptTimerPresentation.compactLabel(elapsed: elapsed(now: now)),
			isRunning: isRunning
		)
	}
}

struct PromptTimerPresentation: Equatable {
	let label: String
	let isRunning: Bool

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

/// Tracks one prompt turn from its `session_start` event until the renderer sees
/// a terminal attention state. Transient tool failures do not stop the clock;
/// an uninterrupted errored state only freezes the timer after the grace period.
///
/// Owned by `FloatingPetWindowPool`, one tracker per render key — NOT by the
/// window/panel it renders on. The pool observes every polled slice every tick
/// whether or not a window currently exists for it, so the timer keeps correct
/// time across hide/show, idle-TTL dismiss, and session-cap de-render — windows
/// only ever receive the resulting `PromptTimerStatus` to display.
struct PromptTimerTracker: Equatable {
	static let erroredTerminalThreshold: TimeInterval = 60

	private(set) var status: PromptTimerStatus?
	private var erroredSince: Date?
	private var lastObservedState: ActivityState?
	private var resetAt: Date?

	/// - Parameter now: the moment this reset becomes authoritative. A caller
	///   resetting in response to a live action (Force Idle) should pass the
	///   real current time; `observe()`'s internal idle transition passes the
	///   idle event's own timestamp instead. Either way, any later `observe()`
	///   of an in-flight state timestamped AT OR BEFORE this moment is treated
	///   as a stale, out-of-order write racing the reset — not a new turn —
	///   and will not restart the timer. Without this, an explicit Force Idle
	///   reset can be immediately undone by the next poll tick reading the
	///   pre-reset on-disk state before the async idle rewrite lands.
	mutating func reset(now: Date = Date()) {
		status = nil
		erroredSince = nil
		lastObservedState = nil
		resetAt = now
	}

	/// - Parameters:
	///   - promptStartedAt: sticky `prompt_started_at` stamp (P20.01) for the
	///     current turn, when the slice carries one. Preferred over `updatedAt`
	///     for the running start time so elapsed stays correct across a mid-turn
	///     `updated_at` bump that doesn't move the turn's own start clock.
	///   - erroredSince: sticky `errored_since` stamp. Preferred over the
	///     tracker's own first-observed-errored heuristic so the 60s grace is
	///     measured from a durable clock — the same one a relaunched tracker or
	///     a different window would compute — not from whichever poll tick
	///     happened to first see the errored state.
	///   - turnEndedAt: sticky `turn_ended_at` stamp. Preferred over `updatedAt`
	///     for the standby freeze point.
	///   All three default to nil and fall back to today's `updatedAt`
	///   heuristics when the slice doesn't carry them (≤v9 payloads, or a v10
	///   payload the hook didn't stamp).
	mutating func observe(
		state: ActivityState,
		updatedAt: String,
		sourceEvent: SourceEvent?,
		attention: AttentionPayload?,
		promptStartedAt: String? = nil,
		erroredSince erroredSinceStamp: String? = nil,
		turnEndedAt: String? = nil,
		now: Date = Date()
	) {
		let observedAt = StateJsonReader.parseISO8601Date(updatedAt) ?? now
		let startedAt = promptStartedAt.flatMap(StateJsonReader.parseISO8601Date) ?? observedAt
		defer { lastObservedState = state }

		// Idle wins over every other signal, including a `session_start`
		// source event: Force Idle's slice rewrite flips only `activity_state`
		// to idle, preserving the old `source_event` and `updated_at` — so an
		// idle slice can still carry `kind: "session_start"` on every poll
		// tick afterward. Checking session_start first would restart the timer
		// from that preserved timestamp forever, making the chip immortal. A
		// REAL session start never classifies to idle (the hook maps it to
		// thinking), so nothing legitimate is lost by resetting here.
		if state == .idle {
			reset(now: observedAt)
			return
		}

		if sourceEvent?.kind == "session_start" {
			status = PromptTimerStatus(startedAt: startedAt, endedAt: nil)
			erroredSince = nil
			return
		}

		if state.isInFlight, shouldStartTimer(observedAt: observedAt) {
			status = PromptTimerStatus(startedAt: startedAt, endedAt: nil)
			erroredSince = nil
			return
		}

		guard var current = status, current.endedAt == nil else { return }

		if state == .standby, attention?.isExpired(now: observedAt) != true, attention != nil {
			let endedAt = turnEndedAt.flatMap(StateJsonReader.parseISO8601Date) ?? observedAt
			current = PromptTimerStatus(startedAt: current.startedAt, endedAt: endedAt)
			status = current
			erroredSince = nil
			return
		}

		if state == .errored {
			if erroredSince == nil {
				erroredSince = erroredSinceStamp.flatMap(StateJsonReader.parseISO8601Date) ?? observedAt
			}
			freezeIfErroredTooLong(now: observedAt)
			return
		}

		erroredSince = nil
	}

	private func shouldStartTimer(observedAt: Date) -> Bool {
		guard status?.isRunning != true else { return false }
		guard let lastObservedState else {
			if let resetAt { return observedAt > resetAt }
			return true
		}
		switch lastObservedState {
		case .idle, .standby, .errored:
			return true
		default:
			return false
		}
	}

	mutating func currentStatus(now: Date = Date()) -> PromptTimerStatus? {
		freezeIfErroredTooLong(now: now)
		return status
	}

	mutating func presentation(now: Date = Date()) -> PromptTimerPresentation? {
		guard let current = currentStatus(now: now) else { return nil }
		return PromptTimerPresentation(
			label: PromptTimerPresentation.compactLabel(elapsed: current.elapsed(now: now)),
			isRunning: current.isRunning
		)
	}

	private mutating func freezeIfErroredTooLong(now: Date) {
		guard let current = status, current.endedAt == nil, let erroredSince else { return }
		let terminalAt = erroredSince.addingTimeInterval(Self.erroredTerminalThreshold)
		guard now >= terminalAt else { return }
		status = PromptTimerStatus(startedAt: current.startedAt, endedAt: terminalAt)
	}
}

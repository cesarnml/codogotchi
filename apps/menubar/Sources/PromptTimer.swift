import Foundation

struct PromptTimerStatus: Equatable {
	let startedAt: Date
	let endedAt: Date?

	var isRunning: Bool { endedAt == nil }

	func elapsed(now: Date = Date()) -> TimeInterval {
		max(0, (endedAt ?? now).timeIntervalSince(startedAt))
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
struct PromptTimerTracker: Equatable {
	static let erroredTerminalThreshold: TimeInterval = 60

	private(set) var status: PromptTimerStatus?
	private var erroredSince: Date?
	private var lastObservedState: ActivityState?

	mutating func reset() {
		status = nil
		erroredSince = nil
		lastObservedState = nil
	}

	mutating func observe(
		state: ActivityState,
		updatedAt: String,
		sourceEvent: SourceEvent?,
		attention: AttentionPayload?,
		now: Date = Date()
	) {
		let observedAt = StateJsonReader.parseISO8601Date(updatedAt) ?? now
		defer { lastObservedState = state }

		if sourceEvent?.kind == "session_start" {
			status = PromptTimerStatus(startedAt: observedAt, endedAt: nil)
			erroredSince = nil
			return
		}

		if state == .idle {
			reset()
			return
		}

		if state.isInFlight, shouldStartTimerOnInFlightTransition {
			status = PromptTimerStatus(startedAt: observedAt, endedAt: nil)
			erroredSince = nil
			return
		}

		guard var current = status, current.endedAt == nil else { return }

		if state == .standby, attention?.isExpired(now: observedAt) != true, attention != nil {
			current = PromptTimerStatus(startedAt: current.startedAt, endedAt: observedAt)
			status = current
			erroredSince = nil
			return
		}

		if state == .errored {
			if erroredSince == nil {
				erroredSince = observedAt
			}
			freezeIfErroredTooLong(now: observedAt)
			return
		}

		erroredSince = nil
	}

	private var shouldStartTimerOnInFlightTransition: Bool {
		guard status?.isRunning != true else { return false }
		guard let lastObservedState else { return true }
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

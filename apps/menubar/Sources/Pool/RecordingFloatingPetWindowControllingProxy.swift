import AppKit
import CoreGraphics
import Foundation

/// One recorded push made through `RecordingFloatingPetWindowControllingProxy`
/// this tick, in call order. Mirrors `PoolShadowComparator`'s field-path
/// naming so a divergence record and a recorded push are trivially
/// cross-referenced by a human reading the shadow log.
enum RecordedPush: Equatable {
	case visibility(Bool)
	case apply(state: ActivityState, visualMode: VisualMode)
	case promptTimerStatus(PromptTimerStatus?)
	case promptTimerPresentation(PromptTimerPresentation?)
	case rpgState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)
	case attention(payload: AttentionPayload?, sourceEvent: SourceEvent?)
	case gateBadge(GateBadgeContent?)
	case platform(String?)
	case sessionNumber(Int?)
	case sessionLabel(String?)
	case sessionTooltip(String?)
	case conflictBubble(ConflictBubblePayload?)
	case adoptFrame(CGRect)
	case idleEscalationConfig(IdleEscalationConfig)
}

/// Forwards every `FloatingPetWindowControlling` call to a wrapped
/// controller while logging each push (in call order), for use with
/// `PoolShadowComparator`. Retained (Phase 18 closeout) as a standalone,
/// directly-tested utility only — nothing in production wraps a real
/// controller in this proxy any longer; see
/// `docs/product/delivery/phase-18/ticket-07-deletion-closeout.md`. The
/// `liveFrameLookup` seam supports wrapping a no-op stub whose `currentFrame`
/// reads through to a real controller by key instead of the stub's own inert
/// `.zero`.
@MainActor
final class RecordingFloatingPetWindowControllingProxy: FloatingPetWindowControlling {
	private let wrapped: FloatingPetWindowControlling
	private let key: WindowKey
	private let liveFrameLookup: ((WindowKey) -> CGRect?)?

	/// Every push recorded since this proxy was created, or since the last
	/// `resetRecording()`, in call order.
	private(set) var recordedCalls: [RecordedPush] = []

	init(
		wrapping wrapped: FloatingPetWindowControlling,
		key: WindowKey,
		liveFrameLookup: ((WindowKey) -> CGRect?)? = nil
	) {
		self.wrapped = wrapped
		self.key = key
		self.liveFrameLookup = liveFrameLookup
	}

	/// The concrete controller this proxy forwards to — lets a caller wrapping
	/// a real controller downcast to a concrete controller type without the
	/// proxy itself getting in the way.
	var underlyingController: FloatingPetWindowControlling { wrapped }

	var isFloatingPetVisible: Bool { wrapped.isFloatingPetVisible }

	func setFloatingPetVisible(_ visible: Bool) {
		recordedCalls.append(.visibility(visible))
		wrapped.setFloatingPetVisible(visible)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		recordedCalls.append(.apply(state: state, visualMode: visualMode))
		wrapped.apply(state: state, visualMode: visualMode)
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		recordedCalls.append(.promptTimerStatus(status))
		wrapped.applyPromptTimerStatus(status)
	}

	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
		recordedCalls.append(.promptTimerPresentation(presentation))
		wrapped.applyPromptTimerPresentation(presentation)
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		recordedCalls.append(
			.rpgState(
				halfHearts: halfHearts, levelFraction: levelFraction, level: level, activeMinutes: activeMinutes,
				hudEnabled: hudEnabled))
		wrapped.applyRPGState(
			halfHearts: halfHearts, levelFraction: levelFraction, level: level, activeMinutes: activeMinutes,
			hudEnabled: hudEnabled)
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		recordedCalls.append(.attention(payload: payload, sourceEvent: sourceEvent))
		wrapped.applyAttention(payload: payload, sourceEvent: sourceEvent)
	}

	func applyGateBadge(content: GateBadgeContent?) {
		recordedCalls.append(.gateBadge(content))
		wrapped.applyGateBadge(content: content)
	}

	func applyPlatform(origin: String?) {
		recordedCalls.append(.platform(origin))
		wrapped.applyPlatform(origin: origin)
	}

	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		wrapped.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	func applySessionNumber(_ number: Int?) {
		recordedCalls.append(.sessionNumber(number))
		wrapped.applySessionNumber(number)
	}

	func applyHasActiveSession(_ hasActiveSession: Bool) {
		wrapped.applyHasActiveSession(hasActiveSession)
	}

	func applySessionLabel(_ label: String?) {
		recordedCalls.append(.sessionLabel(label))
		wrapped.applySessionLabel(label)
	}

	func applySessionTooltip(_ summary: String?) {
		recordedCalls.append(.sessionTooltip(summary))
		wrapped.applySessionTooltip(summary)
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		recordedCalls.append(.conflictBubble(payload))
		wrapped.applyConflictBubble(payload)
	}

	/// Reads through to a live window by key when `liveFrameLookup` is set
	/// AND resolves a frame for `key` — the reversed-shadow direction, where
	/// `wrapped` is a no-op stub holding no real frame of its own. Falls back
	/// to `wrapped.currentFrame` otherwise (the normal direction, where
	/// `wrapped` IS the real controller).
	var currentFrame: CGRect {
		if let liveFrameLookup, let liveFrame = liveFrameLookup(key) {
			return liveFrame
		}
		return wrapped.currentFrame
	}

	func adoptFrame(_ frame: CGRect) {
		recordedCalls.append(.adoptFrame(frame))
		wrapped.adoptFrame(frame)
	}

	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {
		recordedCalls.append(.idleEscalationConfig(config))
		wrapped.updateIdleEscalationConfig(config)
	}

	/// Clears `recordedCalls`, keeping the wrapped controller and key intact —
	/// so a caller driving several ticks against the same proxy can isolate
	/// each tick's pushes.
	func resetRecording() {
		recordedCalls.removeAll()
	}
}

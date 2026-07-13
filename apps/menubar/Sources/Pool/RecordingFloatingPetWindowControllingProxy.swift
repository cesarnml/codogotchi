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
/// controller while logging each push (in call order) for the shadow
/// comparator. Runs in both shadow directions (Grill-Me decision 4):
///
/// - **Pre-cutover** (P18.05): wraps the real controller the old pipeline
///   already drives, so the new engine's shadow run observes the same
///   pushes without double-driving the window.
/// - **Post-cutover, reversed** (P18.06): wraps a no-op stub (no real
///   window), with `liveFrameLookup` reading `currentFrame` through to
///   whichever controller the (now-live) new engine actually spawned for
///   `key` — so the reversed shadow's `currentFrame` reads still see a real
///   on-screen frame rather than the stub's inert `.zero`.
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

	/// The concrete controller this proxy forwards to. `windows[key]` now
	/// stores the proxy rather than the concrete `FloatingPetController` /
	/// `MinimalistWindowController`, so any call site that needs to identity-
	/// compare or downcast to a concrete controller type (e.g. the HUD demo,
	/// which requires real `FloatingPetController` state) must unwrap through
	/// here rather than casting `pool.controller(for:)` directly — recording
	/// stays internal to the proxy either way.
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

	/// Clears `recordedCalls`, keeping the wrapped controller and key intact.
	/// P18.05's shadow tick calls this once per `FloatingPetWindowPool.update()`
	/// tick, before the old pipeline pushes anything, so a reconstructed
	/// `DesiredWindow` reflects only THIS tick's pushes — mirroring
	/// `PoolDerive`'s own per-tick "recompute desired state from scratch"
	/// contract rather than leaking a stale push from an earlier tick forward.
	func resetRecording() {
		recordedCalls.removeAll()
	}
}

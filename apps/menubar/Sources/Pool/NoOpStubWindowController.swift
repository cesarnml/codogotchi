import CoreGraphics
import Foundation

/// A `FloatingPetWindowControlling` conformer that does nothing — no real
/// AppKit window, no persisted state. Used to give `LegacyPoolEngine` a
/// harmless spawn target when it is running as the reversed shadow (P18.06:
/// `CODOGOTCHI_POOL_ENGINE` unset, new engine authoritative) — the old
/// pipeline's imperative logic still runs unchanged and still makes the same
/// decisions, but those decisions land on an inert stub instead of a real
/// window.
@MainActor
final class NoOpStubWindowController: FloatingPetWindowControlling {
	var isFloatingPetVisible = false
	var currentFrame: CGRect = .zero

	func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
	func apply(state: ActivityState, visualMode: VisualMode) {}
	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {}
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {}
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
	func applyGateBadge(content: GateBadgeContent?) {}
	func applyPlatform(origin: String?) {}
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
	func applySessionNumber(_ number: Int?) {}
	func applySessionLabel(_ label: String?) {}
	func applySessionTooltip(_ summary: String?) {}
	func applyConflictBubble(_ payload: ConflictBubblePayload?) {}
	func adoptFrame(_ frame: CGRect) { currentFrame = frame }
	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {}
}

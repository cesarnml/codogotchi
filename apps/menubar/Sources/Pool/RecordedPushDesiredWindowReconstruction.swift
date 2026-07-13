import Foundation

/// Folds one tick's `RecordedPush` log (in call order — last value per field
/// wins) into the `DesiredWindow` shape `PoolShadowComparator` compares
/// against `PoolDerive`'s output. Lives outside `Pool/Derive/` — it reads
/// `RecordedPush`, an AppKit-adjacent proxy type.
///
/// Fields `RecordingFloatingPetWindowControllingProxy` cannot express from a
/// push alone are seeded by the caller (`FloatingPetWindowPool`, which
/// already tracks the old pipeline's own live state) rather than guessed
/// from push data:
/// - `isMinimalist` — a spawn-time factory choice, never itself pushed.
/// - `petId` — only reachable via the unrecorded `replacePets` call (P18.04's
///   own documented deferral); the caller resolves it the same way
///   `PoolDerive` does (`assignments.resolve(origin:)`), from the same
///   `AssignmentsSnapshot` both pipelines read this tick.
/// - `promptTimerStatus` — the old pipeline only ever pushes the raw
///   `PromptTimerStatus` via `applyPromptTimerStatus` (see P18.04's
///   Rationale "Contract note"), never the rendered `PromptTimerPresentation`
///   `DesiredWindow` carries; the caller seeds this from its own
///   `PromptTimerTracker.presentation(now:)` — the identical tracker
///   instance `PoolDerive`'s own fold would converge to given identical
///   observed inputs — and this reconstruction only overrides it if a
///   `.promptTimerPresentation` push is ever actually recorded.
/// - `rpgSnapshot` — the push only carries the four scalar fields
///   `applyRPGState` forwards (`halfHearts`/`levelFraction`/`level`/
///   `activeMinutes`), never `lastActivityAt`/`reviveUntil`; the caller
///   seeds the full `RpgSnapshot` both pipelines read from the same
///   `PerPlatformSnapshot.rpgSnapshot` this tick.
/// - `inheritedFrameFrom` — the proxy only records the resolved `CGRect` via
///   `adoptFrame`, never the structural donor `WindowKey` `PoolDerive`
///   emits; left `nil` always (see `ShadowCompareExemption
///   .frameProvenanceUnavailableFromRecordedPushes`, which the comparator
///   consults to exempt this field rather than treat it as a real
///   divergence every time a fresh spawn inherits a frame).
enum RecordedPushDesiredWindowReconstruction {
	static func reconstruct(
		key: WindowKey,
		pushes: [RecordedPush],
		isMinimalist: Bool,
		petId: String,
		promptTimerStatus: PromptTimerPresentation?,
		rpgSnapshot: RpgSnapshot
	) -> DesiredWindow {
		var window = DesiredWindow(key: key)
		window.isMinimalist = isMinimalist
		window.petId = petId
		window.promptTimerStatus = promptTimerStatus
		window.rpgSnapshot = rpgSnapshot

		for push in pushes {
			switch push {
			case .apply(let state, _):
				window.activityState = state
			case .attention(let payload, let sourceEvent):
				window.attention = payload
				window.attentionSourceEvent = sourceEvent
			case .gateBadge(let content):
				window.gateBadge = content
			case .platform(let origin):
				window.platformChip = origin
			case .rpgState(_, _, _, _, let hudEnabled):
				window.hudEnabled = hudEnabled
			case .sessionNumber(let number):
				window.sessionNumber = number
			case .sessionLabel(let label):
				window.sessionLabel = label
			case .sessionTooltip(let tooltip):
				window.sessionTooltip = tooltip
			case .conflictBubble(let payload):
				window.conflictBubble = payload
			case .promptTimerPresentation(let presentation):
				window.promptTimerStatus = presentation
			case .visibility, .promptTimerStatus, .adoptFrame, .idleEscalationConfig:
				continue
			}
		}
		return window
	}
}

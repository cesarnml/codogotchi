import Foundation

/// One tick's worth of pure input to `PoolDerive.derive`.
///
/// Mirrors what `FloatingPetWindowPool.update(snapshot:)` reads from its
/// injected closures (`customizationReader`, `assignmentsReader`, `now()`)
/// plus the arrived `PerPlatformSnapshot` — hoisted to plain data so the
/// derive core never touches I/O or wall-clock time itself. The shell reads
/// customization/assignments fresh and resolves `now()` once per tick, then
/// constructs this value.
struct PoolTickInput {
	let snapshot: PerPlatformSnapshot
	let customization: CustomizationSnapshot
	let assignments: AssignmentsSnapshot
	let currentTime: Date
	/// Environment overrides for `IdleEscalationConfig.resolve` (P18.03 —
	/// unused by P18.01's derive core, carried now so this type does not
	/// reshape when pushes wire it in).
	let idleEscalationEnvironment: [String: String]
	/// Pure shell-provided values from the three read/effect seams used by push derivation.
	let sessionLabels: [WindowKey: String]
	let knownSessionTitles: [WindowKey: String]
	let sessionPromptSummaries: [WindowKey: String]
	let hudMode: PetConfig.RPGHUDMode

	init(
		snapshot: PerPlatformSnapshot,
		customization: CustomizationSnapshot,
		assignments: AssignmentsSnapshot,
		currentTime: Date,
		idleEscalationEnvironment: [String: String] = [:],
		sessionLabels: [WindowKey: String] = [:],
		knownSessionTitles: [WindowKey: String] = [:],
		sessionPromptSummaries: [WindowKey: String] = [:],
		hudMode: PetConfig.RPGHUDMode = .mostRecent
	) {
		self.snapshot = snapshot
		self.customization = customization
		self.assignments = assignments
		self.currentTime = currentTime
		self.idleEscalationEnvironment = idleEscalationEnvironment
		self.sessionLabels = sessionLabels
		self.knownSessionTitles = knownSessionTitles
		self.sessionPromptSummaries = sessionPromptSummaries
		self.hudMode = hudMode
	}
}

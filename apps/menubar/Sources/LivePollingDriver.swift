import Foundation

/// Canonical user-facing tooltip strings for the three failure visuals defined
/// in `docs/contracts/animation-state-vocabulary.md` (P2.02 appendix). The
/// contract doc is the source of truth — these constants reproduce the canonical
/// copy character-for-character and `LivePollingDriver` consumes them. Tooltip
/// drift between code and contract is a known future-bug class, so the strings
/// live in exactly one place.
enum LivePollingTooltips {
	// Stub — green pass fills in canonical strings.
	static let noHookDetected: String = ""
	static let schemaMissing: String = ""

	static func schemaNewer(got: Int, expected: Int) -> String {
		// Stub — green pass fills in the canonical template.
		return ""
	}
}

/// Stub for P2.07 live polling driver. Real implementation lands in the green
/// pass and is asserted by `LivePollingTests`.
@MainActor
final class LivePollingDriver {
	typealias Apply = (ActivityState, VisualMode) -> Void
	typealias SetTooltip = (String?) -> Void

	init(
		pollingTargetPath: String,
		apply: @escaping Apply,
		setTooltip: @escaping SetTooltip,
		tickInterval: TimeInterval = 1.0
	) {
		// Stub: stored on the green pass.
		_ = pollingTargetPath
		_ = apply
		_ = setTooltip
		_ = tickInterval
	}

	func start() {}

	func stop() {}

	func tickForTesting() {}
}

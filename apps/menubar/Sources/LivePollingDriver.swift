import Foundation

/// Canonical user-facing tooltip strings for the three failure visuals defined
/// in `docs/contracts/animation-state-vocabulary.md` (P2.02 appendix). The
/// contract doc is the source of truth — these constants reproduce the
/// canonical copy character-for-character and `LivePollingDriver` consumes
/// them. Tooltip drift between code and contract is a known future-bug class,
/// so the strings live in exactly one place. If you change a string here,
/// update the contract doc in the same PR (and vice versa).
enum LivePollingTooltips {
	/// Surfaced when the polling target file is absent — the hook binary is
	/// almost certainly not installed or has never run on this machine.
	static let noHookDetected: String = "codogotchi-hook not detected"

	/// Surfaced for both malformed JSON and missing/non-integer `schema_version`.
	/// The product policy folds those into a single user-facing failure visual
	/// because both shapes are "the hook wrote something this app cannot trust";
	/// distinguishing them in the tooltip would just confuse non-developer
	/// users.
	static let schemaMissing: String =
		"state.json schema_version is missing — codogotchi-hook may be too old."

	/// Surfaced when the payload declares a `schema_version` newer than this
	/// build understands. The integers are interpolated into the canonical
	/// template so a renderer update is an actionable fix.
	static func schemaNewer(got: Int, expected: Int) -> String {
		return
			"state.json schema_version is v\(got); this app supports v\(expected). Update the menu bar app."
	}
}

/// Reads `state.json` from the configured `pollingTarget` every `tickInterval`
/// seconds and pushes `(activity_state, visual_mode)` plus tooltip updates into
/// the renderer / status-item seam.
///
/// Behavior on each tick:
/// - `.success(snapshot)` → apply `(snapshot.activityState, .normal)` and clear
///   the tooltip.
/// - `.failure(.fileNotFound)` → apply `(.idle, .desaturated)` and set the
///   no-hook-detected tooltip.
/// - `.failure(.malformed)` or `.failure(.schemaMissingOrInvalid)` → apply
///   `(.idle, .desaturated)` and set the schema-missing tooltip.
/// - `.failure(.schemaNewer(got, expected))` → apply `(.idle, .desaturated)`
///   and set the version-interpolated schema-newer tooltip.
///
/// Staleness (file present + valid + `updated_at` hours old) gets **no special
/// handling**: the parsed `activityState` flows through unchanged. That mirrors
/// the locked product decision in the implementation plan ("quiet agent = idle
/// pet is the truth") and is asserted by `LivePollingTests`.
///
/// Last-emitted state/tooltip are cached so the renderer is not called every
/// tick with the same value. Tests exercise the cache via the synchronous
/// `tickForTesting()` seam instead of the production 1-second `Timer` so
/// `xcodebuild ... test` does not stall on wall-clock waits.
@MainActor
final class LivePollingDriver {
	typealias Apply = (ActivityState, VisualMode) -> Void
	typealias SetTooltip = (String?) -> Void
	typealias Reader = (String) -> Result<StateSnapshot, StateReadError>

	private let pollingTargetPath: String
	private let apply: Apply
	private let setTooltip: SetTooltip
	private let reader: Reader
	private let tickInterval: TimeInterval
	private let transitionLog: TransitionLog?

	private var timer: Timer?
	private var lastRendered: (state: ActivityState, mode: VisualMode)?
	private var lastTooltip: String?
	private var hasEmittedTooltip: Bool = false
	/// Agent-reported state from the last successful read. The transition log
	/// records changes against this value, not against the rendered visual
	/// state, because failure visuals collapse to `.idle` regardless of what
	/// the hook last reported and would otherwise pollute the log with phantom
	/// `prev=idle` entries every time the hook briefly hiccups.
	private var lastAgentState: ActivityState?

	init(
		pollingTargetPath: String,
		apply: @escaping Apply,
		setTooltip: @escaping SetTooltip,
		reader: @escaping Reader = StateJsonReader.read(at:),
		tickInterval: TimeInterval = 1.0,
		transitionLog: TransitionLog? = nil
	) {
		self.pollingTargetPath = pollingTargetPath
		self.apply = apply
		self.setTooltip = setTooltip
		self.reader = reader
		self.tickInterval = tickInterval
		self.transitionLog = transitionLog
	}

	deinit {
		timer?.invalidate()
	}

	/// Begin polling. Emits the first tick immediately so the menubar reflects
	/// current state without waiting `tickInterval` seconds for the first read.
	func start() {
		stop()
		runTick()
		timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) {
			[weak self] _ in
			Task { @MainActor in self?.runTick() }
		}
	}

	/// Cancel the timer. Safe to call multiple times.
	func stop() {
		timer?.invalidate()
		timer = nil
	}

	/// Advance one poll synchronously. Used by tests so they can assert
	/// per-tick behavior without scheduling a real `Timer`.
	func tickForTesting() {
		runTick()
	}

	/// Out-of-band poll trigger. Used by the wake-from-sleep observer
	/// (`NSWorkspace.didWakeNotification`) so the menu bar pet reflects the
	/// current `state.json` without waiting up to `tickInterval` seconds for
	/// the next scheduled tick. Safe to call when polling is not running —
	/// it simply runs one read; the recurring `Timer` is independent.
	func pollNow() {
		runTick()
	}

	private func runTick() {
		let result = reader(pollingTargetPath)
		if case .success(let snapshot) = result {
			let prev = lastAgentState
			if prev != snapshot.activityState {
				transitionLog?.recordTransition(
					snapshot: snapshot,
					previousState: prev ?? snapshot.activityState
				)
			}
			lastAgentState = snapshot.activityState
		}
		let outcome = decide(from: result)
		emit(outcome)
	}

	private struct Outcome: Equatable {
		let state: ActivityState
		let mode: VisualMode
		let tooltip: String?
	}

	private func decide(from result: Result<StateSnapshot, StateReadError>) -> Outcome {
		switch result {
		case .success(let snapshot):
			return Outcome(state: snapshot.activityState, mode: .normal, tooltip: nil)
		case .failure(.fileNotFound):
			return Outcome(state: .idle, mode: .desaturated, tooltip: LivePollingTooltips.noHookDetected)
		case .failure(.malformed), .failure(.schemaMissingOrInvalid):
			return Outcome(state: .idle, mode: .desaturated, tooltip: LivePollingTooltips.schemaMissing)
		case .failure(.schemaNewer(let got, let expected)):
			return Outcome(
				state: .idle,
				mode: .desaturated,
				tooltip: LivePollingTooltips.schemaNewer(got: got, expected: expected)
			)
		}
	}

	private func emit(_ outcome: Outcome) {
		// Collapse no-op renders so the renderer's state machine is not nudged
		// at 1Hz with the same value. Refactor item from the ticket: avoid
		// avoidable churn.
		let newRender = (outcome.state, outcome.mode)
		let renderChanged: Bool = {
			guard let prior = lastRendered else { return true }
			return prior.state != newRender.0 || prior.mode != newRender.1
		}()
		if renderChanged {
			apply(outcome.state, outcome.mode)
			lastRendered = (outcome.state, outcome.mode)
		}

		// Tooltip cache uses an explicit "has ever emitted" flag so the first
		// nil emission still reaches the status item (clearing any inherited
		// placeholder copy) but later identical nils are suppressed.
		let tooltipChanged = !hasEmittedTooltip || outcome.tooltip != lastTooltip
		if tooltipChanged {
			setTooltip(outcome.tooltip)
			lastTooltip = outcome.tooltip
			hasEmittedTooltip = true
		}
	}
}

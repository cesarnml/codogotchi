import Foundation

/// Canonical user-facing tooltip strings for the three failure visuals defined
/// in `docs/contracts/animation-state-vocabulary.md` (P2.02 appendix). The
/// contract doc is the source of truth — these constants reproduce the
/// canonical copy character-for-character and `LivePollingDriver` consumes
/// them. Tooltip drift between code and contract is a known future-bug class,
/// so the strings live in exactly one place. If you change a string here,
/// update the contract doc in the same PR (and vice versa).
enum LivePollingTooltips {
	/// Surfaced when the polling target file is absent — hooks are installed
	/// but no agent prompt has been run yet on this machine.
	static let noHookDetected: String = "Waiting for first agent prompt…"

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
	typealias ApplyAttention = (AttentionPayload?, SourceEvent?) -> Void
	typealias ApplyGateBadge = (GateBadgeContent?) -> Void
	typealias ApplyPlatform = (String?) -> Void
	typealias ApplyRPGState = (Int, Double, Int) -> Void
	typealias Reader = (String) -> Result<StateSnapshot, StateReadError>
	typealias GateReader = (String) -> GateSnapshot?
	typealias DeliveryContextReaderFn = (String) -> DeliveryContextSnapshot?

	private let pollingTargetPath: String
	private let gatePath: String?
	private let deliveryContextPath: String?
	private let previewStatePath: String?
	private let previewGatePath: String?
	private let apply: Apply
	private let setTooltip: SetTooltip
	private let reader: Reader
	private let gateReader: GateReader
	private let deliveryContextReader: DeliveryContextReaderFn
	private let tickInterval: TimeInterval
	private let transitionLog: TransitionLog?
	private var codogotchiPet: CodogotchiPet?
	/// Wall-clock source for half-heart decay. Injected so tests drive decay
	/// deterministically; production uses `Date()`. Each tick recomputes the
	/// displayed half-hearts against this `now`, so the 1Hz poll loop *is* the
	/// decay timer — no separate `Timer` is needed and `pollNow()` (wake-from-
	/// sleep) reflects true elapsed time immediately.
	private let now: () -> Date

	/// Optional sink for attention payload updates. Called when `attention`
	/// or `sourceEvent.origin` changes between ticks. Second parameter is the
	/// source origin from `source_event.origin` (e.g. `"claude_code"`, `"cursor"`).
	var applyAttention: ApplyAttention?
	/// Optional sink for persistent gate badge updates. Badge content comes from
	/// `delivery-context.json`; `gate.json` remains only the animation pulse.
	var applyGateBadge: ApplyGateBadge?
	/// Optional sink for the driving platform. Emits `source_event.origin` (e.g.
	/// `"claude_code"`, `"cursor"`) whenever it changes so the animation badge's
	/// platform chip can track who last drove the pet. `nil` on read failures and
	/// when the payload omits an origin.
	var applyPlatform: ApplyPlatform?
	/// Optional sink for RPG state (halfHearts, levelFraction, level). Emitted
	/// whenever any of the three values change on a successful read. Not emitted
	/// on read failures — the HUD retains its last-known values.
	var applyRPGState: ApplyRPGState?

	private var timer: Timer?
	private var lastRendered: (state: ActivityState, mode: VisualMode)?
	private var lastTooltip: String?
	private var hasEmittedTooltip: Bool = false
	/// Cached attention emission — nil means "never emitted". Outer Optional wraps
	/// the inner `(AttentionPayload?, String?)` so we can distinguish "never
	/// emitted" from "emitted (nil, nil)".
	private var lastAttentionEmission: (AttentionPayload?, SourceEvent?)? = nil
	private var lastGateBadge: GateBadgeContent?
	private var hasEmittedGateBadge = false
	/// Cached platform origin. `hasEmittedPlatform` distinguishes "never emitted"
	/// so the first `nil` origin still clears any inherited chip.
	private var lastPlatformOrigin: String?
	private var hasEmittedPlatform = false
	/// Cached RPG state triple. `nil` means never emitted.
	private var lastRPGState: (halfHearts: Int, levelFraction: Double, level: Int)? = nil
	/// Agent-reported state from the last successful read. The transition log
	/// records changes against this value, not against the rendered visual
	/// state, because failure visuals collapse to `.idle` regardless of what
	/// the hook last reported and would otherwise pollute the log with phantom
	/// `prev=idle` entries every time the hook briefly hiccups.
	private var lastAgentState: ActivityState?

	init(
		pollingTargetPath: String,
		gatePath: String? = nil,
		deliveryContextPath: String? = nil,
		previewStatePath: String? = PreviewOverrideReader.defaultStatePath().path,
		previewGatePath: String? = PreviewOverrideReader.defaultGatePath().path,
		apply: @escaping Apply,
		setTooltip: @escaping SetTooltip,
		reader: @escaping Reader = StateJsonReader.read(at:),
		gateReader: @escaping GateReader = GateJsonReader.read(at:),
		deliveryContextReader: @escaping DeliveryContextReaderFn = DeliveryContextReader.read(at:),
		tickInterval: TimeInterval = 1.0,
		transitionLog: TransitionLog? = nil,
		codogotchiPet: CodogotchiPet? = nil,
		now: @escaping () -> Date = { Date() }
	) {
		self.pollingTargetPath = pollingTargetPath
		self.gatePath = gatePath
		self.deliveryContextPath = deliveryContextPath
		self.previewStatePath = previewStatePath
		self.previewGatePath = previewGatePath
		self.apply = apply
		self.setTooltip = setTooltip
		self.reader = reader
		self.gateReader = gateReader
		self.deliveryContextReader = deliveryContextReader
		self.tickInterval = tickInterval
		self.transitionLog = transitionLog
		self.codogotchiPet = codogotchiPet
		self.now = now
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

	/// Update the stored CodogotchiPet reference so the gate resolver
	/// uses the newly loaded SoA sheet on the next tick.
	func replaceCodogotchiPet(_ pet: CodogotchiPet?) {
		codogotchiPet = pet
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
		let previewState = previewStatePath.flatMap { PreviewOverrideReader.readState(at: $0) }
		let previewGate = previewGatePath.flatMap { PreviewOverrideReader.readGate(at: $0) }
		let previewActive = previewState != nil || previewGate != nil
		let result = reader(pollingTargetPath)
		if !previewActive, case .success(let snapshot) = result {
			let prev = lastAgentState
			if prev != snapshot.activityState {
				transitionLog?.recordTransition(
					snapshot: snapshot,
					previousState: prev ?? snapshot.activityState
				)
			}
			lastAgentState = snapshot.activityState
		}
		let outcome = decide(from: result, previewState: previewState, previewGate: previewGate)
		emit(outcome)
	}

	private struct Outcome: Equatable {
		let state: ActivityState
		let mode: VisualMode
		let tooltip: String?
		let attention: AttentionPayload?
		let sourceEvent: SourceEvent?
		let gateBadge: GateBadgeContent?
		let rpgState: (halfHearts: Int, levelFraction: Double, level: Int)?

		static func == (lhs: Outcome, rhs: Outcome) -> Bool {
			lhs.state == rhs.state
				&& lhs.mode == rhs.mode
				&& lhs.tooltip == rhs.tooltip
				&& lhs.attention == rhs.attention
				&& lhs.sourceEvent == rhs.sourceEvent
				&& lhs.gateBadge == rhs.gateBadge
				&& lhs.rpgState?.halfHearts == rhs.rpgState?.halfHearts
				&& lhs.rpgState?.levelFraction == rhs.rpgState?.levelFraction
				&& lhs.rpgState?.level == rhs.rpgState?.level
		}
	}

	private func decide(
		from result: Result<StateSnapshot, StateReadError>,
		previewState: PreviewStateOverride?,
		previewGate: PreviewGateOverride?
	) -> Outcome {
		if let previewOutcome = previewOutcome(
			from: result, previewState: previewState, previewGate: previewGate)
		{
			return previewOutcome
		}
		let gate = gatePath.flatMap { gateReader($0) }
		let deliveryContext = deliveryContextPath.flatMap { deliveryContextReader($0) }
		switch result {
		case .success(let snapshot):
			let state = resolveActivityState(
				gate: gate, hookState: snapshot.activityState, codogotchiPet: codogotchiPet)
			let gateBadge = resolveGateBadgeContent(
				deliveryContext: deliveryContext,
				sourceEvent: snapshot.sourceEvent
			)
			// Decay the *displayed* half-hearts below the written value based on
			// wall-clock elapsed since `last_activity_at`. The writer is
			// authoritative on heals; Swift only ever decays (never invents
			// heals). Recomputed every tick against the injected clock, so a long
			// idle stretch with no new hook write still shows hearts ticking down
			// — the change-gated emit fires only when a half-heart boundary is
			// crossed (≤ once per 8h), so this is effectively free.
			let displayedHalfHearts = HalfHeartDecayEngine.displayed(
				written: snapshot.halfHearts,
				lastActivityAt: Self.parseISO8601Date(snapshot.lastActivityAt),
				now: now()
			)
			return Outcome(
				state: state,
				mode: .normal,
				tooltip: nil,
				attention: snapshot.attention,
				sourceEvent: snapshot.sourceEvent,
				gateBadge: gateBadge,
				rpgState: (displayedHalfHearts, snapshot.levelFraction, snapshot.level)
			)
		case .failure(.fileNotFound):
			let gateBadge = resolveGateBadgeContent(deliveryContext: deliveryContext, sourceEvent: nil)
			return Outcome(
				state: .idle, mode: .normal,
				tooltip: LivePollingTooltips.noHookDetected,
				attention: nil, sourceEvent: nil, gateBadge: gateBadge, rpgState: nil
			)
		case .failure(.malformed), .failure(.schemaMissingOrInvalid):
			let gateBadge = resolveGateBadgeContent(deliveryContext: deliveryContext, sourceEvent: nil)
			return Outcome(
				state: .idle, mode: .desaturated,
				tooltip: LivePollingTooltips.schemaMissing,
				attention: nil, sourceEvent: nil, gateBadge: gateBadge, rpgState: nil
			)
		case .failure(.schemaNewer(let got, let expected)):
			let gateBadge = resolveGateBadgeContent(deliveryContext: deliveryContext, sourceEvent: nil)
			return Outcome(
				state: .idle,
				mode: .desaturated,
				tooltip: LivePollingTooltips.schemaNewer(got: got, expected: expected),
				attention: nil, sourceEvent: nil, gateBadge: gateBadge, rpgState: nil
			)
		}
	}

	private func previewOutcome(
		from result: Result<StateSnapshot, StateReadError>,
		previewState: PreviewStateOverride?,
		previewGate: PreviewGateOverride?
	) -> Outcome? {
		guard previewState != nil || previewGate != nil else { return nil }
		let hookState: ActivityState = {
			if let previewState {
				return previewState.activityState
			}
			if case .success(let snapshot) = result {
				return snapshot.activityState
			}
			return .idle
		}()
		let gateSnapshot = previewGate.map {
			GateSnapshot(
				gate: $0.activityState.rawValue,
				since: $0.since,
				expiresAt: $0.expiresAt,
				planKey: nil,
				ticketId: nil
			)
		}
		let state = resolveActivityState(
			gate: gateSnapshot,
			hookState: hookState,
			codogotchiPet: codogotchiPet
		)
		return Outcome(
			state: state,
			mode: .normal,
			tooltip: nil,
			attention: nil,
			sourceEvent: nil,
			gateBadge: nil,
			rpgState: nil
		)
	}

	/// Two-pass ISO 8601 parse for `last_activity_at`: fractional-seconds form
	/// first (writer default), then whole-seconds fallback. `nil` in → `nil` out
	/// (no activity recorded → the decay engine treats it as "no decay").
	private static func parseISO8601Date(_ string: String?) -> Date? {
		guard let string else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: string) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: string)
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

		// Attention payload — emit when changed; suppress identical repeats.
		if let sink = applyAttention {
			let newAttention = (outcome.attention, outcome.sourceEvent)
			let attentionChanged: Bool
			if let last = lastAttentionEmission {
				attentionChanged = last.0 != newAttention.0 || last.1 != newAttention.1
			} else {
				attentionChanged = true
			}
			if attentionChanged {
				sink(newAttention.0, newAttention.1)
				lastAttentionEmission = newAttention
			}
		}

		if let sink = applyGateBadge {
			let badgeChanged = !hasEmittedGateBadge || outcome.gateBadge != lastGateBadge
			if badgeChanged {
				sink(outcome.gateBadge)
				lastGateBadge = outcome.gateBadge
				hasEmittedGateBadge = true
			}
		}

		if let sink = applyPlatform {
			let origin = outcome.sourceEvent?.origin
			let platformChanged = !hasEmittedPlatform || origin != lastPlatformOrigin
			if platformChanged {
				sink(origin)
				lastPlatformOrigin = origin
				hasEmittedPlatform = true
			}
		}

		if let sink = applyRPGState, let rpg = outcome.rpgState {
			let changed: Bool = {
				guard let last = lastRPGState else { return true }
				return last.halfHearts != rpg.halfHearts
					|| last.levelFraction != rpg.levelFraction
					|| last.level != rpg.level
			}()
			if changed {
				sink(rpg.halfHearts, rpg.levelFraction, rpg.level)
				lastRPGState = rpg
			}
		}
	}
}

struct PreviewStateOverride {
	let activityState: ActivityState
	let expiresAt: String
	let since: String

	func isExpired(now: Date = Date()) -> Bool {
		parsePreviewISO8601Date(expiresAt).map { $0 < now } ?? true
	}
}

struct PreviewGateOverride {
	let activityState: ActivityState
	let expiresAt: String
	let since: String

	func isExpired(now: Date = Date()) -> Bool {
		parsePreviewISO8601Date(expiresAt).map { $0 < now } ?? true
	}
}

enum PreviewOverrideReader {
	static let directoryName = "codogotchi-preview"
	static let stateFilename = "state-override.json"
	static let gateFilename = "gate-override.json"

	static func defaultRoot(
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> URL {
		let tmpRoot: URL =
			environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return tmpRoot.appendingPathComponent(directoryName, isDirectory: true)
	}

	static func defaultStatePath(
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> URL {
		defaultRoot(environment: environment).appendingPathComponent(stateFilename)
	}

	static func defaultGatePath(
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> URL {
		defaultRoot(environment: environment).appendingPathComponent(gateFilename)
	}

	static func readState(at path: String, now: Date = Date()) -> PreviewStateOverride? {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return nil }
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let rawState = root["activity_state"] as? String,
			let activityState = ActivityState(rawValue: rawState),
			let expiresAt = root["expires_at"] as? String,
			let since = root["since"] as? String
		else { return nil }
		let override = PreviewStateOverride(
			activityState: activityState,
			expiresAt: expiresAt,
			since: since
		)
		return override.isExpired(now: now) ? nil : override
	}

	static func readGate(at path: String, now: Date = Date()) -> PreviewGateOverride? {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return nil }
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let rawState = root["gate"] as? String,
			let activityState = ActivityState(rawValue: rawState),
			CodogotchiPet.soaRowMap[activityState] != nil,
			let expiresAt = root["expires_at"] as? String,
			let since = root["since"] as? String
		else { return nil }
		let override = PreviewGateOverride(
			activityState: activityState,
			expiresAt: expiresAt,
			since: since
		)
		return override.isExpired(now: now) ? nil : override
	}
}

private func parsePreviewISO8601Date(_ string: String) -> Date? {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let date = formatter.date(from: string) { return date }
	formatter.formatOptions = [.withInternetDateTime]
	return formatter.date(from: string)
}

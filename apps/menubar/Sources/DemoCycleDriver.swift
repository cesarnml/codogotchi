import Foundation

/// Drives the demo cycle when the app launches under
/// `CODOGOTCHI_DEMO=1` (or `--demo`).
///
/// On each tick, the driver copies the next fixture from
/// `apps/menubar/Fixtures/state-json/` (bundled as a Resources subdirectory) to
/// the sandboxed `pollingTarget` using an atomic write (write-to-sibling then
/// rename), then calls `apply(state)` so the renderer can swap rows. The
/// atomic write mirrors the Phase 01 hook's pattern so demo mode exercises the
/// same race-free read semantics live polling (P2.07) will depend on.
///
/// The cycle visits all 19 `ActivityState` v4 cases in contract order;
/// see `Self.cycle` for the full sequence.
///
/// Tests drive the cycle deterministically via `tickForTesting()` instead of
/// the production 3-second `Timer` so they do not stall `xcodebuild ... test`.
@MainActor
final class DemoCycleDriver {
	typealias StateApply = (ActivityState) -> Void

	/// Canonical demo cycle order — all 24 `ActivityState` cases.
	/// The demo doubles as a manual visual check that every state renders correctly.
	static let cycle: [(state: ActivityState, fixtureFilename: String)] = [
		(.idle, "idle.json"),
		(.implementing, "implementing.json"),
		(.editing, "editing.json"),
		(.searching, "searching.json"),
		(.webSearch, "web_search.json"),
		(.verifying, "verifying.json"),
		(.gitOps, "git_ops.json"),
		(.testing, "testing.json"),
		(.thinking, "thinking.json"),
		(.reading, "reading.json"),
		(.cramming, "cramming.json"),
		(.waitingForInput, "waiting_for_input.json"),
		(.standby, "standby.json"),
		(.errored, "errored.json"),
		(.ticketStarted, "ticket_started.json"),
		(.redTdd, "red_tdd.json"),
		(.greenTdd, "green_tdd.json"),
		(.adversarialReview, "adversarial_review.json"),
		(.openPr, "open_pr.json"),
		(.pollReview, "poll_review.json"),
		(.recordReview, "record_review.json"),
		(.advance, "advance.json"),
		(.ticketCompleted, "ticket_completed.json"),
		(.reviewClean, "review_clean.json"),
	]

	private let sandboxedPath: URL
	private let fixturesDirectory: URL
	private let apply: StateApply
	private let tickInterval: TimeInterval
	private let transitionLog: TransitionLog?
	private var index: Int = 0
	private var timer: Timer?
	private var lastEmittedState: ActivityState?

	init(
		sandboxedPath: URL,
		fixturesDirectory: URL,
		apply: @escaping StateApply,
		tickInterval: TimeInterval = 3.0,
		transitionLog: TransitionLog? = nil
	) {
		self.sandboxedPath = sandboxedPath
		self.fixturesDirectory = fixturesDirectory
		self.apply = apply
		self.tickInterval = tickInterval
		self.transitionLog = transitionLog
	}

	deinit {
		timer?.invalidate()
	}

	/// Begin the cycle. Emits the first state immediately so the menubar shows
	/// motion without waiting `tickInterval` seconds for the first paint.
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

	/// Advance one cycle step synchronously. Throws on fixture read or atomic
	/// write failures so tests can assert error cases directly.
	func tickForTesting() throws {
		try advance()
	}

	private func runTick() {
		do {
			try advance()
		} catch {
			NSLog("DemoCycleDriver: tick failed: \(error)")
		}
	}

	private func advance() throws {
		let entry = Self.cycle[index]
		index = (index + 1) % Self.cycle.count

		let fixtureURL = fixturesDirectory.appendingPathComponent(entry.fixtureFilename)
		let data = try Data(contentsOf: fixtureURL)

		let parent = sandboxedPath.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
		// `.atomic` writes to a sibling temp file in the same directory and
		// renames into place. This matches the Phase 01 hook's atomic write
		// pattern so demo mode exercises the same race-free read semantics
		// live polling (P2.07) depends on.
		try data.write(to: sandboxedPath, options: .atomic)

		// Mirror what live polling would record: feed the same fixture
		// payload through StateJsonReader so the transition log captures
		// the fixture's `source_event` triplet without the demo driver
		// owning a second copy of the parsing rules.
		if let log = transitionLog, lastEmittedState != entry.state {
			switch StateJsonReader.read(at: sandboxedPath.path) {
			case .success(let snapshot):
				log.recordTransition(
					snapshot: snapshot,
					previousState: lastEmittedState ?? entry.state
				)
			case .failure(let err):
				// Surface fixture parse failures explicitly so a silent
				// log gap (renderer advances but no NDJSON line lands) is
				// diagnosable from Console.app instead of requiring
				// after-the-fact log auditing.
				NSLog(
					"DemoCycleDriver: transition log skipped — fixture parse failed (\(err))"
				)
			}
		}
		lastEmittedState = entry.state

		apply(entry.state)
	}
}

/// Drives a self-contained RPG-HUD animation for developer convenience when the
/// app launches under `CODOGOTCHI_HUD_DEMO=1` (see `tch` / `test-codogotchi-hud`).
///
/// Over `totalDuration` seconds it sweeps the HUD's three inputs:
/// - **level** starts at 1 and increments every `secondsPerLevel` seconds,
/// - **levelFraction** fills 0→1 within each level so the XP ring climbs
///   gradually,
/// - **halfHearts** runs a triangle wave 6→0→6, one half-heart every
///   `secondsPerHalfHeartStep` seconds.
///
/// With the defaults (120s, 8s/level, 5s/half-heart) the run ends on level 16
/// after two complete full→empty→full heart cycles. `secondsPerLevel` is
/// configurable (faster leveling for a punchier demo); the half-heart step
/// scales with it so the heart cycle keeps the same 5:8 ratio. The pure
/// `snapshot(at:)` mapping is unit-tested; the timer is a thin driver around it.
@MainActor
final class HUDDemoDriver {
	typealias RPGApply = (
		_ halfHearts: Int, _ levelFraction: Double, _ level: Int, _ activeMinutes: Int
	) -> Void

	static let totalDuration: TimeInterval = 120
	static let defaultSecondsPerLevel: TimeInterval = 8
	static let defaultSecondsPerHalfHeartStep: TimeInterval = 5
	static let maxHalfHearts = 6
	static let startLevel = 1

	/// Proportional half-heart step for a given seconds-per-level, preserving the
	/// default 5:8 heart:level ratio so faster leveling speeds the heart cycle to
	/// match. E.g. 3s/level → 3 × 5/8 ≈ 1.875s per half-heart.
	static func halfHeartStep(forSecondsPerLevel secondsPerLevel: TimeInterval) -> TimeInterval {
		secondsPerLevel * (defaultSecondsPerHalfHeartStep / defaultSecondsPerLevel)
	}

	/// Deterministic mapping from elapsed seconds to HUD RPG values. Pure so it
	/// can be unit-tested without a timer.
	static func snapshot(
		at elapsed: TimeInterval,
		secondsPerLevel: TimeInterval = defaultSecondsPerLevel,
		secondsPerHalfHeartStep: TimeInterval = defaultSecondsPerHalfHeartStep
	)
		-> (halfHearts: Int, levelFraction: Double, level: Int)
	{
		let t = max(0, min(totalDuration, elapsed))
		let level = startLevel + Int(t / secondsPerLevel)
		let levelFraction = t.truncatingRemainder(dividingBy: secondsPerLevel) / secondsPerLevel
		let step = Int(t / secondsPerHalfHeartStep)
		let period = maxHalfHearts * 2
		let pos = step % period
		let halfHearts = pos <= maxHalfHearts ? maxHalfHearts - pos : pos - maxHalfHearts
		return (halfHearts, levelFraction, level)
	}

	private let apply: RPGApply
	private let onComplete: () -> Void
	private let secondsPerLevel: TimeInterval
	private let secondsPerHalfHeartStep: TimeInterval
	private let heartsFull: Bool
	private let tickInterval: TimeInterval
	private let clock: () -> Date
	private var startedAt: Date?
	private var timer: Timer?

	/// - Parameters:
	///   - secondsPerLevel: how long each level takes (default 8s).
	///   - secondsPerHalfHeartStep: half-heart cadence; when `nil` it is derived
	///     from `secondsPerLevel` to preserve the default 5:8 heart:level ratio.
	///   - heartsFull: when true, hearts stay pinned at full (the heart triangle
	///     wave is suppressed) so the demo shows only the level/XP-ring sweep —
	///     the "leveling" demo (`tcl`). The pure `snapshot` math is untouched; the
	///     override is applied at emit time.
	init(
		apply: @escaping RPGApply,
		onComplete: @escaping () -> Void = {},
		secondsPerLevel: TimeInterval = defaultSecondsPerLevel,
		secondsPerHalfHeartStep: TimeInterval? = nil,
		heartsFull: Bool = false,
		tickInterval: TimeInterval = 0.05,
		clock: @escaping () -> Date = Date.init
	) {
		self.apply = apply
		self.onComplete = onComplete
		self.secondsPerLevel = secondsPerLevel
		self.secondsPerHalfHeartStep =
			secondsPerHalfHeartStep ?? Self.halfHeartStep(forSecondsPerLevel: secondsPerLevel)
		self.heartsFull = heartsFull
		self.tickInterval = tickInterval
		self.clock = clock
	}

	deinit {
		timer?.invalidate()
	}

	/// Begin the animation, emitting the starting frame (level 1, empty ring,
	/// full hearts) immediately.
	func start() {
		stop()
		startedAt = clock()
		emit(at: 0)
		timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) {
			[weak self] _ in
			Task { @MainActor in self?.runTick() }
		}
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}

	private func runTick() {
		guard let startedAt else { return }
		let elapsed = clock().timeIntervalSince(startedAt)
		emit(at: elapsed)
		if elapsed >= Self.totalDuration {
			stop()
			onComplete()
		}
	}

	private func emit(at elapsed: TimeInterval) {
		let snap = Self.snapshot(
			at: elapsed,
			secondsPerLevel: secondsPerLevel,
			secondsPerHalfHeartStep: secondsPerHalfHeartStep)
		// Synthesize a revival-meter carry from progress within the current
		// half-heart step so the meter visibly fills while the demo pet is dead
		// (halfHearts == 0). Not part of the unit-tested `snapshot` shape.
		let t = max(0, min(Self.totalDuration, elapsed))
		let stepProgress =
			t.truncatingRemainder(dividingBy: secondsPerHalfHeartStep) / secondsPerHalfHeartStep
		let demoActiveMinutes = Int(stepProgress * Double(ACTIVE_MINUTES_PER_HALF_HEART))
		// `heartsFull` pins hearts at max so only the level/XP-ring sweep shows
		// (the leveling demo). Full hearts → not dead → revive meter stays hidden.
		let hearts = heartsFull ? Self.maxHalfHearts : snap.halfHearts
		let active = heartsFull ? 0 : demoActiveMinutes
		apply(hearts, snap.levelFraction, snap.level, active)
	}
}

import Foundation

/// Drives the four-floor-state demo cycle when the app launches under
/// `CODOGOTCHI_DEMO=1` (or `--demo`).
///
/// On each tick, the driver copies the next fixture from
/// `apps/menubar/Fixtures/state-json/` (bundled as a Resources subdirectory) to
/// the sandboxed `pollingTarget` using an atomic write (write-to-sibling then
/// rename), then calls `apply(state)` so the renderer can swap rows. The
/// atomic write mirrors the Phase 01 hook's pattern so demo mode exercises the
/// same race-free read semantics live polling (P2.07) will depend on.
///
/// The cycle is hardcoded:
/// `.idle` → `.implementing` → `.runningTests` → `.celebrating` → loop.
///
/// Tests drive the cycle deterministically via `tickForTesting()` instead of
/// the production 3-second `Timer` so they do not stall `xcodebuild ... test`.
@MainActor
final class DemoCycleDriver {
	typealias StateApply = (ActivityState) -> Void

	/// Canonical demo cycle order. Hardcoded — order matches the contract's
	/// Activity States table top-to-bottom so the demo doubles as a manual
	/// visual check that all 15 states render correctly.
	static let cycle: [(state: ActivityState, fixtureFilename: String)] = [
		(.idle, "idle.json"),
		(.implementing, "implementing.json"),
		(.runningTests, "running-tests.json"),
		(.reviewing, "reviewing.json"),
		(.pushing, "pushing.json"),
		(.hyped, "hyped.json"),
		(.focused, "focused.json"),
		(.nervous, "nervous.json"),
		(.waiting, "waiting.json"),
		(.celebrating, "celebrating.json"),
		(.ascended, "ascended.json"),
		(.callingForBackup, "calling-for-backup.json"),
		(.panicking, "panicking.json"),
		(.requestingInput, "requesting-input.json"),
		(.errored, "errored.json"),
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
		dbgLog(
			"DBG DemoCycleDriver.start: tickInterval=\(tickInterval) sandboxedPath=\(sandboxedPath.path) fixturesDirectory=\(fixturesDirectory.path)"
		)
		runTick()
		timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) {
			[weak self] _ in
			dbgLog("DBG DemoCycleDriver: timer fired")
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
		dbgLog("DBG DemoCycleDriver.runTick: entering, index=\(index)")
		do {
			try advance()
			dbgLog("DBG DemoCycleDriver.runTick: advance OK, next index=\(index)")
		} catch {
			dbgLog("DBG DemoCycleDriver.runTick: advance FAILED (\(error))")
		}
	}

	private func advance() throws {
		let entry = Self.cycle[index]
		dbgLog(
			"DBG DemoCycleDriver.advance: picking entry index=\(index) state=\(entry.state.rawValue) fixture=\(entry.fixtureFilename)"
		)
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

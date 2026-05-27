import Foundation

/// Append-only NDJSON writer for observed activity-state transitions.
///
/// Behavior:
/// - `recordTransition(snapshot:previousState:)` writes one NDJSON line per
///   observed state change. Field shape:
///   ```
///   {"ts":"...","state":"...","prev":"...","schema_version":1,
///    "source_origin":"...","source_kind":"...","source_name":"..."}
///   ```
/// - A heartbeat NDJSON line is appended once per `heartbeatInterval` (60
///   minutes by default) when no transition has occurred in that window.
///   Any real transition resets the heartbeat window. Heartbeat shape:
///   ```
///   {"ts":"...","state":"<last activity state>","heartbeat":true,
///    "schema_version":1}
///   ```
/// - Default path is `~/.codogotchi/state-transitions.log`. The path is
///   injectable for tests and for demo mode (sandboxed log location).
/// - On each write, if the active log exceeds 10 MB it is rotated by
///   renaming to `<path>.1`, overwriting any prior `.1`. Single backup
///   policy — `.log.2` is never created. Heartbeat lines count toward
///   rotation accounting because every appended byte sits in the same
///   file; tracking them separately would be misleading.
///
/// The `clock` closure is injectable so tests can fast-forward time without
/// `Thread.sleep`. The default uses wall-clock `Date()`.
///
/// Threading: `TransitionLog` is intentionally not `@MainActor`. The
/// existing drivers (`LivePollingDriver`, `DemoCycleDriver`) call into it
/// from the main actor only, and the heartbeat `Timer` schedules on the
/// main run loop, so internal state mutation is serialized in practice
/// without explicit locking. Bridging to a background actor would require
/// reworking the drivers and is out of scope for P2.08.
final class TransitionLog {

	/// 10 MB rotation threshold, matching the convention documented for the
	/// TS-side `sync.log` (`docs/contracts/animation-state-vocabulary.md`).
	static let rotationByteThreshold: Int = 10 * 1024 * 1024

	private let path: URL
	private let clock: () -> Date
	private let heartbeatInterval: TimeInterval

	/// Last in-process activity state observed via `recordTransition`. Used
	/// as the `state` field on heartbeat lines so the log carries a useful
	/// "what was the agent last doing?" signal even during quiet windows.
	private var lastObservedState: ActivityState = .idle

	/// Wall-clock instant of the most recent transition or heartbeat write.
	/// Heartbeat ticks only fire once `clock() - lastActivity >= interval`.
	private var lastActivityAt: Date?

	/// Encoder for the NDJSON line objects. JSON keys are pre-sorted so the
	/// log is diff-friendly when humans inspect it.
	private let encoder: JSONEncoder = {
		let e = JSONEncoder()
		e.outputFormatting = [.sortedKeys]
		return e
	}()

	/// ISO-8601 timestamp formatter. A single static instance avoids the
	/// well-known per-call cost of `ISO8601DateFormatter` initialization.
	private static let isoFormatter: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private var heartbeatTimer: Timer?

	init(
		path: URL,
		clock: @escaping () -> Date = Date.init,
		heartbeatInterval: TimeInterval = 60 * 60
	) {
		self.path = path
		self.clock = clock
		self.heartbeatInterval = heartbeatInterval
	}

	deinit {
		heartbeatTimer?.invalidate()
	}

	/// Default log location: `~/.codogotchi/state-transitions.log`.
	static func defaultPath() -> URL {
		let home = FileManager.default.homeDirectoryForCurrentUser
		return home
			.appendingPathComponent(".codogotchi", isDirectory: true)
			.appendingPathComponent("state-transitions.log")
	}

	// MARK: - Public API

	/// Append one NDJSON line describing the observed transition and reset
	/// the heartbeat window. Failures are logged via `NSLog` and swallowed
	/// — the log is best-effort and must never crash the menubar app.
	func recordTransition(snapshot: StateSnapshot, previousState: ActivityState) {
		let payload = LinePayload(
			ts: Self.isoFormatter.string(from: clock()),
			state: snapshot.activityState.rawValue,
			prev: previousState.rawValue,
			schemaVersion: 1,
			heartbeat: nil,
			sourceOrigin: snapshot.sourceEvent?.origin,
			sourceKind: snapshot.sourceEvent?.kind,
			sourceName: snapshot.sourceEvent?.name
		)
		write(payload)
		lastObservedState = snapshot.activityState
		lastActivityAt = clock()
	}

	/// Schedule the heartbeat timer on the main run loop. Safe to call
	/// multiple times; the prior timer is invalidated. The first heartbeat
	/// fires only after `heartbeatInterval` has elapsed since the last
	/// recorded transition (or since `start()` if no transitions yet).
	func start() {
		stop()
		if lastActivityAt == nil {
			lastActivityAt = clock()
		}
		// Check every minute whether the window has elapsed; the timer
		// itself does not need to match the configured cadence. This keeps
		// the cost trivial and avoids drift compounding when a tick is
		// delayed by app sleep.
		let pollInterval: TimeInterval = 60
		heartbeatTimer = Timer.scheduledTimer(
			withTimeInterval: pollInterval,
			repeats: true
		) { [weak self] _ in
			self?.maybeEmitHeartbeat()
		}
	}

	/// Invalidate the heartbeat timer. Safe to call multiple times.
	func stop() {
		heartbeatTimer?.invalidate()
		heartbeatTimer = nil
	}

	/// Synchronous heartbeat probe used by tests in lieu of a real `Timer`.
	/// Equivalent to one production timer tick.
	func tickHeartbeatForTesting() {
		maybeEmitHeartbeat()
	}

	// MARK: - Internals

	private func maybeEmitHeartbeat() {
		let now = clock()
		let baseline = lastActivityAt ?? now
		if now.timeIntervalSince(baseline) < heartbeatInterval {
			return
		}
		let payload = LinePayload(
			ts: Self.isoFormatter.string(from: now),
			state: lastObservedState.rawValue,
			prev: nil,
			schemaVersion: 1,
			heartbeat: true,
			sourceOrigin: nil,
			sourceKind: nil,
			sourceName: nil
		)
		write(payload)
		lastActivityAt = now
	}

	private func write(_ payload: LinePayload) {
		do {
			let data = try encoder.encode(payload)
			var lineBytes = data
			lineBytes.append(0x0A)  // newline

			let fm = FileManager.default
			let parent = path.deletingLastPathComponent()
			if !fm.fileExists(atPath: parent.path) {
				try fm.createDirectory(at: parent, withIntermediateDirectories: true)
			}

			let alreadyExists = fm.fileExists(atPath: path.path)
			let currentSize = alreadyExists ? fileSize(at: path) : 0
			if currentSize > Self.rotationByteThreshold {
				rotate()
			}

			if !fm.fileExists(atPath: path.path) {
				fm.createFile(atPath: path.path, contents: nil)
			}
			let handle = try FileHandle(forWritingTo: path)
			defer { try? handle.close() }
			try handle.seekToEnd()
			try handle.write(contentsOf: lineBytes)
		} catch {
			NSLog("TransitionLog: write failed (\(error))")
		}
	}

	private func fileSize(at url: URL) -> Int {
		let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
		return (attrs?[.size] as? Int) ?? 0
	}

	private func rotate() {
		let fm = FileManager.default
		let backup = path.deletingLastPathComponent()
			.appendingPathComponent(path.lastPathComponent + ".1")
		do {
			if fm.fileExists(atPath: backup.path) {
				try fm.removeItem(at: backup)
			}
			if fm.fileExists(atPath: path.path) {
				try fm.moveItem(at: path, to: backup)
			}
		} catch {
			NSLog("TransitionLog: rotate failed (\(error))")
		}
	}
}

/// Wire shape for one NDJSON line. JSON keys are emitted in snake_case to
/// match the contract doc.
private struct LinePayload: Encodable {
	let ts: String
	let state: String
	let prev: String?
	let schemaVersion: Int
	let heartbeat: Bool?
	let sourceOrigin: String?
	let sourceKind: String?
	let sourceName: String?

	enum CodingKeys: String, CodingKey {
		case ts
		case state
		case prev
		case schemaVersion = "schema_version"
		case heartbeat
		case sourceOrigin = "source_origin"
		case sourceKind = "source_kind"
		case sourceName = "source_name"
	}
}

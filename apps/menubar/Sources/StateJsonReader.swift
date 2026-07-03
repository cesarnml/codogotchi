import Foundation

/// Renderer-side schema version this build understands. P2.02's forward-compat
/// clause: any `state.json` with `schema_version > EXPECTED_STATE_SCHEMA_VERSION`
/// is refused; equal or lower versions parse best-effort and tolerate extra
/// fields. Bump deliberately when the renderer gains support for a newer
/// schema; do not silently widen.
let EXPECTED_STATE_SCHEMA_VERSION = 8

/// Error cases surfaced by `StateJsonReader.read(at:)`.
///
/// `schemaNewer` carries both observed and expected versions so the renderer's
/// tooltip code (P2.07) can format the canonical "schema_version is v{got};
/// this app supports v{expected}" string without re-parsing the payload.
enum StateReadError: Error, Equatable {
	case fileNotFound
	case malformed
	case schemaMissingOrInvalid
	case schemaNewer(got: Int, expected: Int)
}

/// Reads `state.json` payloads from disk and returns either a decoded
/// `StateSnapshot` or the precise failure reason.
///
/// The reader is namespace-style (enum with no cases) because there is no
/// instance state — every call resolves a single path. `Result` is preferred
/// over throws so callers can match exhaustively without `do/catch` ceremony.
enum StateJsonReader {
	static func read(at path: String) -> Result<StateSnapshot, StateReadError> {
		let url = URL(fileURLWithPath: path)

		let data: Data
		do {
			data = try Data(contentsOf: url)
		} catch {
			if (error as NSError).domain == NSCocoaErrorDomain
				&& (error as NSError).code == NSFileReadNoSuchFileError
			{
				return .failure(.fileNotFound)
			}
			if !FileManager.default.fileExists(atPath: path) {
				return .failure(.fileNotFound)
			}
			return .failure(.malformed)
		}

		// Inspect schema_version before full decode so we can map the precise
		// missing/non-integer and newer-than-expected cases.
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return .failure(.malformed)
		}
		// JSONSerialization bridges JSON booleans to NSNumber, and NSNumber
		// satisfies `as? Int`. Reject Bool explicitly so `"schema_version": true`
		// is correctly classified as `.schemaMissingOrInvalid` rather than
		// silently coerced to `1`. Only true integer NSNumbers are accepted.
		guard let rawNumber = root["schema_version"] as? NSNumber,
			CFGetTypeID(rawNumber) != CFBooleanGetTypeID(),
			CFNumberIsFloatType(rawNumber) == false
		else {
			return .failure(.schemaMissingOrInvalid)
		}
		let schemaVersion = rawNumber.intValue
		if schemaVersion > EXPECTED_STATE_SCHEMA_VERSION {
			return .failure(
				.schemaNewer(got: schemaVersion, expected: EXPECTED_STATE_SCHEMA_VERSION)
			)
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		do {
			let payload = try decoder.decode(StatePayload.self, from: data)
			let raw = StateSnapshot(
				schemaVersion: payload.schemaVersion,
				activityState: payload.activityState,
				updatedAt: payload.updatedAt,
				sourceEvent: payload.sourceEvent,
				attention: payload.attention,
				toolCommand: payload.toolCommand,
				level: payload.level ?? 1,
				levelFraction: payload.levelFraction ?? 0.0,
				halfHearts: payload.halfHearts ?? MAX_HALF_HEARTS,
				activeMinutes: payload.activeMinutes ?? 0,
				// `?? nil` coerces String?? → String?: maps both absent key (.none outer)
				// and explicit JSON null (.some(.none) inner) to nil. Do not remove.
				lastActivityAt: payload.lastActivityAt ?? nil,
				reviveUntil: payload.reviveUntil ?? nil
			)
			return .success(
				StateSnapshot(
					schemaVersion: raw.schemaVersion,
					activityState: resolveActivityState(raw),
					updatedAt: raw.updatedAt,
					sourceEvent: raw.sourceEvent,
					attention: raw.attention,
					toolCommand: raw.toolCommand,
					level: raw.level,
					levelFraction: raw.levelFraction,
					halfHearts: raw.halfHearts,
					activeMinutes: raw.activeMinutes,
					lastActivityAt: raw.lastActivityAt,
					reviveUntil: raw.reviveUntil
				)
			)
		} catch {
			return .failure(.malformed)
		}
	}

	/// Applies the TTL policy: if `attention.expires_at` is parseable and in
	/// the past, returns `.idle` regardless of the written `activity_state`.
	/// When `attention` is absent or `expires_at` cannot be parsed, the raw
	/// `activity_state` is returned unchanged.
	///
	/// Two-pass ISO 8601 parse: tries fractional-seconds form first (Zod
	/// default: `"2026-05-29T14:00:00.000Z"`) then falls back to whole-seconds
	/// form so both hook output shapes are accepted.
	static func resolveActivityState(_ snapshot: StateSnapshot, now: Date = Date()) -> ActivityState {
		guard let attention = snapshot.attention,
			let expiresAtStr = attention.expiresAt,
			let expiry = parseISO8601Date(expiresAtStr),
			expiry < now
		else { return snapshot.activityState }
		return .idle
	}

	static func parseISO8601Date(_ string: String) -> Date? {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: string) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: string)
	}

	/// Entry point matching the `(String) -> Result<StateSnapshot, StateReadError>`
	/// Reader typealias used by `LivePollingDriver`. Calls through to the full
	/// implementation with `now = Date()` and the default 2-hour stale TTL.
	static func readDirectory(at dirPath: String) -> Result<StateSnapshot, StateReadError> {
		readDirectoryImpl(at: dirPath, now: Date(), staleTTL: 2 * 60 * 60)
	}

	/// Reads all slice files from a `state.d/` directory and collapses them to a
	/// single `StateSnapshot` via globalAggregate (most-recent `updated_at` wins).
	///
	/// Excludes files whose filesystem mtime is older than `staleTTL` (default 2h)
	/// and files whose name matches the tmp-write pattern (`*.tmp-*`). Returns
	/// `.failure(.fileNotFound)` when the directory itself does not exist.
	/// Returns `.success` with an idle default when the directory is empty or all
	/// slices are stale.
	static func readDirectory(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval = 2 * 60 * 60
	) -> Result<StateSnapshot, StateReadError> {
		readDirectoryImpl(at: dirPath, now: now, staleTTL: staleTTL)
	}

	private static func readDirectoryImpl(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval
	) -> Result<StateSnapshot, StateReadError> {
		let fm = FileManager.default
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
			return .failure(.fileNotFound)
		}

		let names: [String]
		do {
			names = try fm.contentsOfDirectory(atPath: dirPath)
		} catch {
			return .failure(.malformed)
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase

		var winner: (date: Date, slice: SlicePayload)? = nil

		for name in names {
			guard name.hasSuffix(".json"), !name.contains(".tmp-") else { continue }
			let filePath = (dirPath as NSString).appendingPathComponent(name)

			// mtime TTL filter
			if let attrs = try? fm.attributesOfItem(atPath: filePath),
				let mtime = attrs[.modificationDate] as? Date,
				now.timeIntervalSince(mtime) > staleTTL
			{
				continue
			}

			guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
				let slice = try? decoder.decode(SlicePayload.self, from: data)
			else { continue }

			let candidateDate = parseISO8601Date(slice.updatedAt) ?? Date.distantPast
			if winner == nil || candidateDate > winner!.date {
				winner = (candidateDate, slice)
			}
		}

		guard let (_, slice) = winner else {
			return .success(idleSnapshot())
		}

		let raw = StateSnapshot(
			schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
			activityState: slice.activityState,
			updatedAt: slice.updatedAt,
			sourceEvent: slice.sourceEvent,
			attention: slice.attention,
			toolCommand: slice.toolCommand,
			level: 1,
			levelFraction: 0.0,
			halfHearts: MAX_HALF_HEARTS,
			activeMinutes: 0,
			lastActivityAt: nil,
			reviveUntil: nil
		)
		return .success(
			StateSnapshot(
				schemaVersion: raw.schemaVersion,
				activityState: resolveActivityState(raw, now: now),
				updatedAt: raw.updatedAt,
				sourceEvent: raw.sourceEvent,
				attention: raw.attention,
				toolCommand: raw.toolCommand,
				level: raw.level,
				levelFraction: raw.levelFraction,
				halfHearts: raw.halfHearts,
				activeMinutes: raw.activeMinutes,
				lastActivityAt: raw.lastActivityAt,
				reviveUntil: raw.reviveUntil
			)
		)
	}

	private static func idleSnapshot() -> StateSnapshot {
		StateSnapshot(
			schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
			activityState: .idle,
			updatedAt: "",
			sourceEvent: nil,
			attention: nil,
			toolCommand: nil,
			level: 1,
			levelFraction: 0.0,
			halfHearts: MAX_HALF_HEARTS,
			activeMinutes: 0,
			lastActivityAt: nil,
			reviveUntil: nil
		)
	}

	/// Groups all fresh slices in a `state.d/` directory by `source_event.origin`
	/// (last-writer-wins per group) and returns a per-origin map of `StateSnapshot`.
	/// Slices without a parseable origin are skipped.
	/// Returns `.failure(.fileNotFound)` when the directory does not exist.
	/// Returns `.success([:])` when the directory is empty or all slices are stale.
	static func readPerPlatformDirectory(
		at dirPath: String,
		listing: StateDirectoryListing? = nil
	) -> Result<[String: StateSnapshot], StateReadError> {
		readPerPlatformDirectoryImpl(at: dirPath, now: Date(), staleTTL: 2 * 60 * 60, listing: listing)
	}

	static func readPerPlatformDirectory(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval = 2 * 60 * 60,
		listing: StateDirectoryListing? = nil
	) -> Result<[String: StateSnapshot], StateReadError> {
		readPerPlatformDirectoryImpl(at: dirPath, now: now, staleTTL: staleTTL, listing: listing)
	}

	/// `listing`, when supplied, is a `state.d/` enumeration already produced once
	/// for this poll tick — the reader consumes it instead of re-scanning. When
	/// omitted (direct callers, tests), the reader self-scans exactly as before,
	/// preserving the `.fileNotFound` (missing dir) vs `.malformed` (unreadable
	/// dir) distinction. Only the raw enumeration is shared; each slice's contents
	/// and the stale-TTL filter are still applied here.
	private static func readPerPlatformDirectoryImpl(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval,
		listing: StateDirectoryListing?
	) -> Result<[String: StateSnapshot], StateReadError> {
		let fm = FileManager.default

		let entries: [StateDirectoryListing.Entry]
		if let listing {
			entries = listing.entries
		} else {
			var isDir: ObjCBool = false
			guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
				return .failure(.fileNotFound)
			}
			guard let scanned = StateDirectoryListing.scan(at: dirPath) else {
				return .failure(.malformed)
			}
			entries = scanned.entries
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase

		var winners: [String: (date: Date, slice: SlicePayload)] = [:]

		for entry in entries {
			let name = entry.name
			guard name.hasSuffix(".json"), !name.contains(".tmp-") else { continue }
			let filePath = (dirPath as NSString).appendingPathComponent(name)

			if let mtime = entry.mtime, now.timeIntervalSince(mtime) > staleTTL {
				continue
			}

			guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
				let slice = try? decoder.decode(SlicePayload.self, from: data),
				let rawOrigin = slice.sourceEvent?.origin,
				!rawOrigin.trimmingCharacters(in: .whitespaces).isEmpty
			else { continue }
			let origin = rawOrigin.trimmingCharacters(in: .whitespaces)

			let candidateDate = parseISO8601Date(slice.updatedAt) ?? Date.distantPast
			if winners[origin] == nil || candidateDate > winners[origin]!.date {
				winners[origin] = (candidateDate, slice)
			}
		}

		var result: [String: StateSnapshot] = [:]
		for (origin, (_, slice)) in winners {
			let raw = StateSnapshot(
				schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
				activityState: slice.activityState,
				updatedAt: slice.updatedAt,
				sourceEvent: slice.sourceEvent,
				attention: slice.attention,
				toolCommand: slice.toolCommand
			)
			result[origin] = StateSnapshot(
				schemaVersion: raw.schemaVersion,
				activityState: resolveActivityState(raw, now: now),
				updatedAt: raw.updatedAt,
				sourceEvent: raw.sourceEvent,
				attention: raw.attention,
				toolCommand: raw.toolCommand
			)
		}
		return .success(result)
	}

	/// Parses a `state.d/` slice filename into its `(origin, sessionId)` identity.
	///
	/// The CLI writes slices as `<origin>:<session_id>.json` (see
	/// `sliceFilePath` in `packages/cli/src/hook-binary.ts`, where `sessionId`
	/// defaults to `"default"`). We split on the **first** colon so a
	/// `session_id` that itself contains a colon still resolves — `origin` is a
	/// fixed enum value that never contains one. A filename with no colon keys
	/// as `origin:default`, matching the CLI writer's `sessionId ?? "default"`
	/// fallback for a session that never set an id.
	///
	/// Returns `nil` — the slice is skipped — for non-slice entries (`.tmp-`
	/// temp writes, the `.gate.json` / `.context.json` sidecars that share the
	/// `.json` suffix), a name with no `.json` suffix, or an empty origin
	/// component (an unparseable filename such as `:orphan.json`).
	static func parseSliceFilename(_ name: String) -> (origin: String, sessionId: String)? {
		guard name.hasSuffix(".json"), !name.contains(".tmp-") else { return nil }
		if name.hasSuffix(".gate.json") || name.hasSuffix(".context.json") { return nil }
		let stem = String(name.dropLast(".json".count))
		guard !stem.isEmpty else { return nil }
		guard let colon = stem.firstIndex(of: ":") else {
			return (stem, "default")
		}
		let origin = String(stem[stem.startIndex..<colon])
		guard !origin.isEmpty else { return nil }
		let session = String(stem[stem.index(after: colon)...])
		return (origin, session.isEmpty ? "default" : session)
	}

	/// Full per-session granularity: groups fresh `state.d/` slices by the
	/// `origin:session_id` identity parsed from each filename, applying the same
	/// stale-TTL filter and `resolveActivityState` treatment as
	/// `readPerPlatformDirectory`. Slices whose filename lacks a parseable origin
	/// are skipped.
	///
	/// Keys are `"<origin>:<session_id>"`. Returns `.failure(.fileNotFound)` when
	/// the directory does not exist and `.success([:])` when it is empty or all
	/// slices are stale.
	static func readPerSessionDirectory(
		at dirPath: String,
		listing: StateDirectoryListing? = nil
	) -> Result<[String: StateSnapshot], StateReadError> {
		readPerSessionDirectoryImpl(at: dirPath, now: Date(), staleTTL: 2 * 60 * 60, listing: listing)
	}

	static func readPerSessionDirectory(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval = 2 * 60 * 60,
		listing: StateDirectoryListing? = nil
	) -> Result<[String: StateSnapshot], StateReadError> {
		readPerSessionDirectoryImpl(at: dirPath, now: now, staleTTL: staleTTL, listing: listing)
	}

	/// `listing`, when supplied, is the shared per-tick `state.d/` enumeration
	/// (P15.02); the reader consumes it instead of re-scanning. When omitted it
	/// self-scans, preserving the `.fileNotFound` (missing dir) vs `.malformed`
	/// (unreadable dir) distinction. Slice construction mirrors
	/// `readPerPlatformDirectoryImpl` field-for-field so an all-default
	/// `resolveRenderKeys` collapse is byte-identical to the per-origin map.
	private static func readPerSessionDirectoryImpl(
		at dirPath: String,
		now: Date,
		staleTTL: TimeInterval,
		listing: StateDirectoryListing?
	) -> Result<[String: StateSnapshot], StateReadError> {
		let fm = FileManager.default

		let entries: [StateDirectoryListing.Entry]
		if let listing {
			entries = listing.entries
		} else {
			var isDir: ObjCBool = false
			guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
				return .failure(.fileNotFound)
			}
			guard let scanned = StateDirectoryListing.scan(at: dirPath) else {
				return .failure(.malformed)
			}
			entries = scanned.entries
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase

		// One winner per (origin, session) key. Distinct filenames normally map
		// to distinct keys, but the strict-`>` tie-break is kept so this matches
		// the per-origin reader's grouping semantics exactly.
		var winners: [String: (date: Date, slice: SlicePayload)] = [:]

		for entry in entries {
			guard let (origin, sessionId) = parseSliceFilename(entry.name) else { continue }
			let filePath = (dirPath as NSString).appendingPathComponent(entry.name)

			if let mtime = entry.mtime, now.timeIntervalSince(mtime) > staleTTL {
				continue
			}

			guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
				let slice = try? decoder.decode(SlicePayload.self, from: data)
			else { continue }

			let key = makeSessionKey(origin: origin, sessionId: sessionId)
			let candidateDate = parseISO8601Date(slice.updatedAt) ?? Date.distantPast
			if winners[key] == nil || candidateDate > winners[key]!.date {
				winners[key] = (candidateDate, slice)
			}
		}

		var result: [String: StateSnapshot] = [:]
		for (key, (_, slice)) in winners {
			let raw = StateSnapshot(
				schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
				activityState: slice.activityState,
				updatedAt: slice.updatedAt,
				sourceEvent: slice.sourceEvent,
				attention: slice.attention,
				toolCommand: slice.toolCommand
			)
			result[key] = StateSnapshot(
				schemaVersion: raw.schemaVersion,
				activityState: resolveActivityState(raw, now: now),
				updatedAt: raw.updatedAt,
				sourceEvent: raw.sourceEvent,
				attention: raw.attention,
				toolCommand: raw.toolCommand
			)
		}
		return .success(result)
	}
}

/// Private wire shape: matches v1 schema keys after snake-case conversion.
/// Extra payload fields (`hp`, `hpOverlay`, etc.) are tolerated because
/// `Decodable` ignores unknown keys by default. `sourceEvent` is decoded
/// when present so the transition log (P2.08) can record its
/// `origin`/`kind`/`name` triplet; absence is normal and surfaces as nil.
/// `attention` carries the TTL expiry used by `resolveActivityState` (P6.07).
/// v5 RPG fields are optional so ≤v4 payloads parse without them; the reader
/// fills in safe defaults when they are absent.
private struct StatePayload: Decodable {
	let schemaVersion: Int
	let activityState: ActivityState
	let updatedAt: String
	let sourceEvent: SourceEvent?
	let attention: AttentionPayload?
	/// `tool_command` (snake-case in the wire payload) carries the raw shell
	/// command string for Bash/Shell tool events. Decoded so the transition
	/// log can record it; absence is normal for non-shell events.
	let toolCommand: String?
	// v5 RPG progression fields — optional for forward-compat with ≤v4 payloads
	let level: Int?
	let levelFraction: Double?
	let halfHearts: Int?
	/// Active-minute carry toward the next half-heart (0…59). Absent for ≤v4
	/// payloads and older v5 writers; the reader fills 0 when missing.
	let activeMinutes: Int?
	/// Decoded as `String?` to preserve the raw ISO 8601 value; null from the
	/// writer decodes as nil. Wall-clock elapsed is computed in
	/// `HalfHeartDecayEngine` using `Date` after parsing.
	let lastActivityAt: String??
	/// v6 `revive_until` — ISO 8601 datetime or null. `String??` distinguishes
	/// absent key (≤v5 payloads, outer .none) from explicit JSON null
	/// (.some(.none)); both collapse to nil at the snapshot boundary.
	let reviveUntil: String??
}

/// Wire shape for v8 slice files (state.d/<origin>:<session_id>.json).
/// RPG fields moved to `rpg-state.json` in schema v8; `Decodable` silently
/// ignores them if present in older v7 slices. `origin` and `sessionId` are
/// carried in the filename and not decoded here (best-effort posture).
private struct SlicePayload: Decodable {
	let activityState: ActivityState
	let updatedAt: String
	let sourceEvent: SourceEvent?
	let attention: AttentionPayload?
	let toolCommand: String?
}

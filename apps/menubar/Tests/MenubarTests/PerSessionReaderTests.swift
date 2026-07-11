import XCTest

@testable import Codogotchi

/// P15.03 behavior contract for the per-session reader and the pure
/// `resolveRenderKeys` collapse.
///
/// Two layers are exercised:
/// - `StateJsonReader.readPerSessionDirectory` emits full `origin:session_id`
///   granularity, parsing `session_id` from the slice filename
///   (`state.d/<origin>:<session_id>.json`).
/// - `resolveRenderKeys` reduces that per-session map to the render set for a
///   given customization snapshot: Combined origins fold to `"combined"`;
///   Own/Minimalist with session-pets off fold each origin's sessions to the
///   last-writer-wins winner keyed by plain `origin`; session-pets on keep
///   each `origin:session_id` key.
///
/// The safety property the whole composite-key foundation rests on — that an
/// all-default customization yields a render set byte-identical to today's
/// per-origin map — is locked by `testAllDefaultCollapseEqualsPerOriginMap`.
final class PerSessionReaderTests: XCTestCase {

	// MARK: - Fixture helpers

	private func makeTempDir() -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("per-session-reader-\(UUID().uuidString)", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func writeSlice(
		_ dir: URL,
		filename: String,
		origin: String,
		state: String,
		updatedAt: String
	) throws {
		try """
			{ "activity_state": "\(state)", "updated_at": "\(updatedAt)", "source_event": { "origin": "\(origin)" } }
			""".write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
	}

	private func customization(
		modes: [String: PlatformMode] = [:],
		sessionPets: [String: Bool] = [:],
		activatedAt: [String: String] = [:],
		grandfathered: [String: String] = [:]
	) -> CustomizationSnapshot {
		CustomizationSnapshot(
			platformModes: modes,
			idleDismissTtlSeconds: 300,
			menubarIconMonochrome: false,
			combinedMinimalistEnabled: false,
			minimalistBadgeScale: 1.0,
			sessionPetsEnabled: sessionPets,
			sessionCap: [:],
			sessionPetsActivatedAt: activatedAt,
			sessionPetsGrandfatheredSessionId: grandfathered
		)
	}

	// MARK: - Reader: per-session granularity

	func testTwoSessionsSameOriginProduceTwoEntries() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "thinking",
			updatedAt: iso)

		guard case .success(let map) = StateJsonReader.readPerSessionDirectory(at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		XCTAssertEqual(
			Set(map.keys), ["claude_code:s1", "claude_code:s2"],
			"two sessions of one origin must produce two per-session entries")
		XCTAssertEqual(map["claude_code:s1"]?.activityState, .implementing)
		XCTAssertEqual(map["claude_code:s2"]?.activityState, .thinking)
	}

	func testMissingSessionComponentKeysAsDefault() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		// No colon in the filename → session component falls back to "default",
		// matching the CLI writer's `sessionId ?? "default"`.
		try writeSlice(
			dir, filename: "claude_code.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)

		guard case .success(let map) = StateJsonReader.readPerSessionDirectory(at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		XCTAssertEqual(
			Set(map.keys), ["claude_code:default"],
			"a slice filename with no session component must key as origin:default")
	}

	func testUnparseableFilenameIsSkipped() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		// Leading colon → empty origin component → unparseable → skipped.
		try writeSlice(
			dir, filename: ":orphan.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)
		// A valid slice alongside it must still be read.
		try writeSlice(
			dir, filename: "cursor:s1.json", origin: "cursor", state: "editing", updatedAt: iso)

		guard case .success(let map) = StateJsonReader.readPerSessionDirectory(at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		XCTAssertEqual(
			Set(map.keys), ["cursor:s1"],
			"a filename lacking a parseable origin must be skipped, not crash the read")
	}

	func testMissingDirectoryFailsWithFileNotFound() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("no-such-\(UUID().uuidString)", isDirectory: true)
		guard case .failure(let err) = StateJsonReader.readPerSessionDirectory(at: missing.path)
		else { return XCTFail("a missing directory must fail") }
		XCTAssertEqual(err, .fileNotFound)
	}

	// MARK: - resolveRenderKeys

	func testSessionPetsOffCollapsesToLastWriterWinsPerOrigin() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		// Three sessions of one origin; s3 has the latest updated_at → wins.
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "idle",
			updatedAt: "2026-06-28T10:00:00.000Z")
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "thinking",
			updatedAt: "2026-06-28T10:00:01.000Z")
		try writeSlice(
			dir, filename: "claude_code:s3.json", origin: "claude_code", state: "implementing",
			updatedAt: "2026-06-28T10:00:02.000Z")

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(perSession: perSession, customization: customization())

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code"],
			"session-pets off must fold all of one origin's sessions to a single plain-origin key")
		XCTAssertEqual(
			resolution.states["claude_code"]?.activityState, .implementing,
			"the last-writer-wins winner is the session with the newest updated_at")
		XCTAssertEqual(
			resolution.identities["claude_code"],
			RenderKeyIdentity(origin: "claude_code", sessionId: "s3"),
			"the render key must recover the winning (origin, session_id) for downstream labeling")
	}

	/// Subagent-review F1: equal `updated_at` across sessions folding to one
	/// render key must resolve deterministically (sorted key iteration + strict
	/// `>` keeps the lexicographically smallest per-session key), not by
	/// unspecified Dictionary order.
	func testEqualTimestampTieBreaksToLexicographicallySmallestSessionKey() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = "2026-06-28T10:00:00.000Z"
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "thinking",
			updatedAt: iso)
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(perSession: perSession, customization: customization())

		XCTAssertEqual(
			resolution.identities["claude_code"],
			RenderKeyIdentity(origin: "claude_code", sessionId: "s1"),
			"equal-timestamp ties must deterministically keep the lexicographically smallest session key"
		)
		XCTAssertEqual(resolution.states["claude_code"]?.activityState, .implementing)
	}

	func testSessionPetsOnKeepsEachSessionKey() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "thinking",
			updatedAt: iso)

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(sessionPets: ["claude_code": true]))

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code:s1", "claude_code:s2"],
			"session-pets on must keep every origin:session_id key")
	}

	// MARK: - Grandfather/activity gate (P15-QC)

	func testGrandfatheredSessionRendersEvenWithNoActivitySinceActivation() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let activation = Date(timeIntervalSinceReferenceDate: 1000)
		// The grandfather's slice predates activation and has had zero activity
		// since — it must still render because it is the grandfather.
		try writeSlice(
			dir, filename: "claude_code:grandfather.json", origin: "claude_code", state: "idle",
			updatedAt: ISO8601DateFormatter().string(from: activation.addingTimeInterval(-500)))

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(at: dir.path)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(
				sessionPets: ["claude_code": true],
				activatedAt: ["claude_code": ISO8601DateFormatter().string(from: activation)],
				grandfathered: ["claude_code": "grandfather"]
			))

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code:grandfather"],
			"the grandfathered session must render even though it predates activation and is idle")
	}

	func testSiblingSessionPredatingActivationIsExcludedUntilNewActivity() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let activation = Date(timeIntervalSinceReferenceDate: 1000)
		// A non-grandfather sibling whose last write predates activation and
		// nothing has touched it since — must be excluded entirely, not merely
		// held back.
		try writeSlice(
			dir, filename: "claude_code:stale-sibling.json", origin: "claude_code", state: "idle",
			updatedAt: ISO8601DateFormatter().string(from: activation.addingTimeInterval(-500)))

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(at: dir.path)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(
				sessionPets: ["claude_code": true],
				activatedAt: ["claude_code": ISO8601DateFormatter().string(from: activation)],
				grandfathered: ["claude_code": "some-other-session"]
			))

		XCTAssertTrue(
			resolution.states.isEmpty,
			"a sibling session with no activity after the activation timestamp must be excluded entirely")
	}

	func testSiblingSessionWithActivityAfterActivationIsAdmitted() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let activation = Date(timeIntervalSinceReferenceDate: 1000)
		try writeSlice(
			dir, filename: "claude_code:fresh-sibling.json", origin: "claude_code", state: "implementing",
			updatedAt: ISO8601DateFormatter().string(from: activation.addingTimeInterval(500)))

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(at: dir.path)
		else { return XCTFail("read must succeed") }

		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(
				sessionPets: ["claude_code": true],
				activatedAt: ["claude_code": ISO8601DateFormatter().string(from: activation)],
				grandfathered: ["claude_code": "some-other-session"]
			))

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code:fresh-sibling"],
			"a sibling session with activity strictly after activation must be admitted")
	}

	func testOriginWithNoRecordedActivationAdmitsEverySessionUnconditionally() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "idle", updatedAt: iso)
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "idle", updatedAt: iso)

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		// session-pets on, but no activation ever recorded for this origin
		// (pre-existing data from before this gate existed) — must behave
		// exactly like the ungated testSessionPetsOnKeepsEachSessionKey case.
		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(sessionPets: ["claude_code": true]))

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code:s1", "claude_code:s2"],
			"an origin with no recorded activation must admit every session, matching pre-gate behavior")
	}

	func testCombinedOriginsFoldToCombinedRegardlessOfSessionPets() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		// Two combined-mode origins; cursor wins on updated_at.
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "implementing",
			updatedAt: "2026-06-28T10:00:00.000Z")
		try writeSlice(
			dir, filename: "cursor:s2.json", origin: "cursor", state: "thinking",
			updatedAt: "2026-06-28T10:00:01.000Z")

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		// session-pets on for both — combined fold must still win.
		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(
				modes: ["claude_code": .combined, "cursor": .combined],
				sessionPets: ["claude_code": true, "cursor": true]))

		XCTAssertEqual(
			Set(resolution.states.keys), ["combined"],
			"combined-mode origins fold to a single combined key regardless of session-pets")
		XCTAssertEqual(
			resolution.states["combined"]?.activityState, .thinking,
			"the combined winner is the newest updated_at across all folded origins")
		XCTAssertEqual(resolution.identities["combined"]?.origin, "cursor")
	}

	func testMixedPlatformsResolveIndependently() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		let iso = ISO8601DateFormatter().string(from: now)
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "implementing",
			updatedAt: iso)
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "thinking",
			updatedAt: iso)
		try writeSlice(
			dir, filename: "cursor:s9.json", origin: "cursor", state: "editing", updatedAt: iso)

		guard case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
			at: dir.path, now: now)
		else { return XCTFail("read must succeed") }

		// claude_code keeps its sessions (session-pets on); cursor folds (off).
		let resolution = resolveRenderKeys(
			perSession: perSession,
			customization: customization(sessionPets: ["claude_code": true]))

		XCTAssertEqual(
			Set(resolution.states.keys), ["claude_code:s1", "claude_code:s2", "cursor"],
			"each platform must resolve independently by its own mode/session-pets setting")
	}

	// MARK: - Byte-identical guarantee

	/// With an all-default customization, the collapse must reproduce today's
	/// per-origin map exactly — same keys, same winner snapshots. This is the
	/// safety property that lets Phase 15 land the composite-key foundation
	/// without regressing the shipping session-pets-off default.
	func testAllDefaultCollapseEqualsPerOriginMap() throws {
		let dir = makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let now = Date()
		// Representative state.d/: two origins, one with two sessions.
		try writeSlice(
			dir, filename: "claude_code:s1.json", origin: "claude_code", state: "idle",
			updatedAt: "2026-06-28T10:00:00.000Z")
		try writeSlice(
			dir, filename: "claude_code:s2.json", origin: "claude_code", state: "implementing",
			updatedAt: "2026-06-28T10:00:05.000Z")
		try writeSlice(
			dir, filename: "cursor:s1.json", origin: "cursor", state: "thinking",
			updatedAt: "2026-06-28T10:00:03.000Z")

		guard
			case .success(let perSession) = StateJsonReader.readPerSessionDirectory(
				at: dir.path, now: now),
			case .success(let perOrigin) = StateJsonReader.readPerPlatformDirectory(
				at: dir.path, now: now)
		else { return XCTFail("both reads must succeed") }

		let collapsed = resolveRenderKeys(perSession: perSession, customization: customization())
		let perOriginAsWindowKeys = Dictionary(
			uniqueKeysWithValues: perOrigin.map { (WindowKey.origin($0.key), $0.value) })

		XCTAssertEqual(
			collapsed.states, perOriginAsWindowKeys,
			"all-default collapse must be byte-identical to the pre-change per-origin map")
	}
}

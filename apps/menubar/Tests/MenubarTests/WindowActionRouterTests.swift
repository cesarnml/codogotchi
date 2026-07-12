import Foundation
import XCTest

@testable import Codogotchi

/// Targeting tests for `WindowActionRouter` — one case per action ×
/// `WindowKey` shape, asserting exactly which `state.d/` slices get
/// touched and that the pool-owned prompt timer resets before the
/// on-disk rewrite. Derived from the pre-router closure behavior and
/// comments in `MenubarApp` (P17.05).
@MainActor
final class WindowActionRouterTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("WindowActionRouterTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Helpers

	private func makeStateDir() -> URL {
		let dir = tmp.appendingPathComponent("state.d")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func writeSlice(_ filename: String, in dir: URL, activityState: String = "implementing", attention: Bool = true) {
		let url = dir.appendingPathComponent(filename)
		var json: [String: Any] = [
			"schema_version": 6,
			"activity_state": activityState,
			"source_event": ["origin": filename.split(separator: ":").first.map(String.init) ?? filename],
			"updated_at": ISO8601DateFormatter().string(from: Date()),
		]
		if attention {
			json["attention"] = ["message": "look at me"]
		}
		let data = try! JSONSerialization.data(withJSONObject: json)
		try! data.write(to: url)
	}

	private func readSlice(_ filename: String, in dir: URL) -> [String: Any]? {
		let url = dir.appendingPathComponent(filename)
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		return obj
	}

	/// Builds a router whose pool-facing dependencies record calls instead of
	/// touching a real pool, and whose `stateDir` points at `dir`. Returns the
	/// recording boxes alongside the router so tests can assert on them after
	/// the router's async actions settle.
	private func makeRouter(
		dir: URL,
		combinedOrigins: [String] = []
	) -> (router: WindowActionRouter, resets: Box<[WindowKey]>, clears: Box<[WindowKey]>) {
		let resets = Box<[WindowKey]>([])
		let clears = Box<[WindowKey]>([])
		let router = WindowActionRouter(
			stateDir: { dir.path },
			resetPromptTimer: { key in resets.value.append(key) },
			combinedModeOrigins: { combinedOrigins },
			clearAttentionBubbles: { key in clears.value.append(key) }
		)
		return (router, resets, clears)
	}

	/// Runs an async writer-backed router action and waits briefly for the
	/// background queue to finish, mirroring `StateJsonWriterTests`' pattern
	/// but without a completion hook on the router API itself.
	private func settle() {
		let expectation = expectation(description: "settle")
		DispatchQueue.global(qos: .userInitiated).async {
			DispatchQueue.main.async { expectation.fulfill() }
		}
		wait(for: [expectation], timeout: 5)
	}

	// MARK: - resolveWindowOrigins

	func testResolveWindowOriginsPlainOriginResolvesToItself() {
		let (router, _, _) = makeRouter(dir: makeStateDir())
		XCTAssertEqual(router.resolveWindowOrigins(.origin("claude_code")), ["claude_code"])
	}

	func testResolveWindowOriginsSessionResolvesToOwningOrigin() {
		let (router, _, _) = makeRouter(dir: makeStateDir())
		XCTAssertEqual(router.resolveWindowOrigins(.session(origin: "claude_code", id: "s1")), ["claude_code"])
	}

	func testResolveWindowOriginsCombinedExpandsToLiveCombinedSet() {
		let (router, _, _) = makeRouter(dir: makeStateDir(), combinedOrigins: ["claude_code", "cursor"])
		XCTAssertEqual(router.resolveWindowOrigins(.combined), ["claude_code", "cursor"])
	}

	// MARK: - handleAttentionDismissed

	func testAttentionDismissedPlainOriginClearsOnlyThatOriginsWinnerSlice() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir)
		writeSlice("cursor:s1.json", in: dir)
		let (router, resets, _) = makeRouter(dir: dir)

		router.handleAttentionDismissed(for: .origin("claude_code"))
		settle()

		XCTAssertNil(readSlice("claude_code:s1.json", in: dir)!["attention"])
		XCTAssertNotNil(readSlice("cursor:s1.json", in: dir)!["attention"], "sibling origin must be untouched")
		XCTAssertEqual(resets.value, [.origin("claude_code")], "prompt timer must reset for the dismissed window")
	}

	func testAttentionDismissedSessionKeyedIdlesEverySiblingSessionForThatOriginAndClearsBubbles() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir)
		writeSlice("claude_code:s2.json", in: dir)
		writeSlice("cursor:s1.json", in: dir)
		let (router, resets, clears) = makeRouter(dir: dir)
		let key = WindowKey.session(origin: "claude_code", id: "s1")

		router.handleAttentionDismissed(for: key)
		settle()

		XCTAssertNil(readSlice("claude_code:s1.json", in: dir)!["attention"])
		XCTAssertNil(
			readSlice("claude_code:s2.json", in: dir)!["attention"],
			"sibling session for the same origin must also be idled")
		XCTAssertNotNil(readSlice("cursor:s1.json", in: dir)!["attention"], "other origin must be untouched")
		XCTAssertEqual(clears.value, [key], "bubbles must be cleared immediately for the session-keyed window")
		XCTAssertEqual(resets.value, [key])
	}

	func testAttentionDismissedCombinedClearsExactlyTheLiveCombinedSet() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir)
		writeSlice("cursor:s1.json", in: dir)
		writeSlice("codex:s1.json", in: dir)
		let (router, _, _) = makeRouter(dir: dir, combinedOrigins: ["claude_code", "cursor"])

		router.handleAttentionDismissed(for: .combined)
		settle()

		XCTAssertNil(readSlice("claude_code:s1.json", in: dir)!["attention"])
		XCTAssertNil(readSlice("cursor:s1.json", in: dir)!["attention"])
		XCTAssertNotNil(readSlice("codex:s1.json", in: dir)!["attention"], "origin outside the combined set must be untouched")
	}

	// MARK: - handleForceIdle

	func testForceIdlePlainOriginResetsOnlyItsWinnerSlice() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir, activityState: "implementing", attention: false)
		writeSlice("cursor:s1.json", in: dir, activityState: "implementing", attention: false)
		let (router, _, _) = makeRouter(dir: dir)

		router.handleForceIdle(for: .origin("claude_code"))
		settle()

		XCTAssertEqual(readSlice("claude_code:s1.json", in: dir)!["activity_state"] as? String, "idle")
		XCTAssertEqual(
			readSlice("cursor:s1.json", in: dir)!["activity_state"] as? String, "implementing",
			"sibling origin must be untouched")
	}

	func testForceIdleSessionKeyedResetsExactlyItsOwnSliceNeverAFresherSibling() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir, activityState: "implementing", attention: false)
		writeSlice("claude_code:s2.json", in: dir, activityState: "implementing", attention: false)
		let (router, resets, _) = makeRouter(dir: dir)
		let key = WindowKey.session(origin: "claude_code", id: "s1")

		router.handleForceIdle(for: key)
		settle()

		XCTAssertEqual(readSlice("claude_code:s1.json", in: dir)!["activity_state"] as? String, "idle")
		XCTAssertEqual(
			readSlice("claude_code:s2.json", in: dir)!["activity_state"] as? String, "implementing",
			"a fresher sibling session must never be reset by another session's Force Idle")
		XCTAssertEqual(resets.value, [key])
	}

	func testForceIdleCombinedResetsExactlyTheLiveCombinedSetNeverAllSlices() {
		let dir = makeStateDir()
		writeSlice("claude_code:s1.json", in: dir, activityState: "implementing", attention: false)
		writeSlice("cursor:s1.json", in: dir, activityState: "implementing", attention: false)
		writeSlice("codex:s1.json", in: dir, activityState: "implementing", attention: false)
		let (router, _, _) = makeRouter(dir: dir, combinedOrigins: ["claude_code", "cursor"])

		router.handleForceIdle(for: .combined)
		settle()

		XCTAssertEqual(readSlice("claude_code:s1.json", in: dir)!["activity_state"] as? String, "idle")
		XCTAssertEqual(readSlice("cursor:s1.json", in: dir)!["activity_state"] as? String, "idle")
		XCTAssertEqual(
			readSlice("codex:s1.json", in: dir)!["activity_state"] as? String, "implementing",
			"never all slices — an origin outside the combined set must not be idled")
	}
}

/// Reference-type box so a `let router = makeRouter(...)` closure can mutate
/// a value captured before the router itself is constructed, without
/// fighting Swift's exclusivity rules on an `inout` var captured by escaping
/// closures.
private final class Box<T> {
	var value: T
	init(_ value: T) { self.value = value }
}

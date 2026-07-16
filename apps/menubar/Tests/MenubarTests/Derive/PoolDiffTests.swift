import XCTest

@testable import Codogotchi

/// Red-phase tests for P18.04's `diff(desired:current:)` — the mechanical set
/// comparison over `WindowKey` that partitions this tick's `DesiredWindows`
/// against the previous tick's rendered `DesiredWindow` values into
/// spawn/dismiss/update sets, per the ticket's Outcome:
///
/// "`diff(desired:current:)` is a mechanical set comparison: spawn / dismiss /
/// update sets keyed by `WindowKey`, with frame-inheritance directives passed
/// through as data — no policy branches (any needed decision is evidence of a
/// P18.03 gap, fixed there)."
///
/// `PoolDiff` and `WindowDiff` do not exist yet — this file only compiles once
/// P18.04's green phase adds `Sources/Pool/Derive/PoolDiff.swift`. Diff is pure
/// set algebra with no AppKit dependency, so it lives under `Pool/Derive/` and
/// is covered by `PoolDerivePurityGateTests`.
@MainActor
final class PoolDiffTests: XCTestCase {

	// MARK: - Helpers

	private func window(_ key: WindowKey, label: String = "", inheritedFrameFrom: WindowKey? = nil) -> DesiredWindow {
		var window = DesiredWindow(key: key)
		window.sessionLabel = label.isEmpty ? nil : label
		window.inheritedFrameFrom = inheritedFrameFrom
		return window
	}

	// MARK: - Spawn / dismiss / update partitioning

	func testPartitionsFreshDisappearedAndPersistingKeysCorrectly() {
		let current: [WindowKey: DesiredWindow] = [
			"claude_code": window("claude_code", label: "A"),
			"cursor": window("cursor", label: "B"),
		]
		var desired = DesiredWindows()
		desired.windows = [
			// "claude_code" persists (present in both) — belongs in toUpdate.
			"claude_code": window("claude_code", label: "A"),
			// "cursor" vanished — belongs in toDismiss.
			// "codex" is brand new — belongs in toSpawn.
			"codex": window("codex", label: "C"),
		]

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(Set(result.toSpawn.keys), ["codex"])
		XCTAssertEqual(result.toDismiss, ["cursor"])
		XCTAssertEqual(Set(result.toUpdate.keys), ["claude_code"])
	}

	func testUpdatePartitionIsKeyMembershipOnlyNotValueEquality() {
		// "no policy branches": a key present in both `current` and `desired`
		// belongs in `toUpdate` regardless of whether its DesiredWindow value
		// actually changed — diff does not decide whether a push is
		// "necessary", it only decides which controller method family
		// (spawn/dismiss/update) applies this tick.
		let unchanged = window("claude_code", label: "Same")
		let current: [WindowKey: DesiredWindow] = ["claude_code": unchanged]
		var desired = DesiredWindows()
		desired.windows = ["claude_code": unchanged]

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(Set(result.toUpdate.keys), ["claude_code"])
		XCTAssertTrue(result.toSpawn.isEmpty)
		XCTAssertTrue(result.toDismiss.isEmpty)
	}

	func testEmptyDesiredDismissesEveryCurrentKey() {
		let current: [WindowKey: DesiredWindow] = [
			"claude_code": window("claude_code"),
			"cursor": window("cursor"),
		]
		let desired = DesiredWindows()

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(result.toDismiss, ["claude_code", "cursor"])
		XCTAssertTrue(result.toSpawn.isEmpty)
		XCTAssertTrue(result.toUpdate.isEmpty)
	}

	func testEmptyCurrentSpawnsEveryDesiredKey() {
		let current: [WindowKey: DesiredWindow] = [:]
		var desired = DesiredWindows()
		desired.windows = [
			"claude_code": window("claude_code"),
			"cursor": window("cursor"),
		]

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(Set(result.toSpawn.keys), ["claude_code", "cursor"])
		XCTAssertTrue(result.toDismiss.isEmpty)
		XCTAssertTrue(result.toUpdate.isEmpty)
	}

	// MARK: - Frame-inheritance directive pass-through

	func testFreshlySpawningWindowCarriesItsInheritedFrameDirectiveUnchanged() {
		// P18.02/P18.03 already resolved WHICH torn-down window a fresh spawn
		// should inherit from (`inheritedFrameFrom`); `diff` must pass that
		// directive through as inert data on the `toSpawn` entry, never
		// resolve, drop, or reinterpret it — resolving the actual on-screen
		// frame from the donor is `apply`'s job (P18.04's `apply`, not `diff`).
		let current: [WindowKey: DesiredWindow] = [:]
		var desired = DesiredWindows()
		desired.windows = [
			"claude:s2": window("claude:s2", inheritedFrameFrom: "claude:s1")
		]

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(result.toSpawn["claude:s2"]?.inheritedFrameFrom, "claude:s1")
	}

	func testDiffCarriesFullDesiredWindowValueNotJustTheKey() {
		// Push completeness starts here: `toSpawn`/`toUpdate` must carry the
		// entire `DesiredWindow` value (every push-payload field `apply` will
		// need), not merely the `WindowKey` — otherwise `apply` would have to
		// re-derive push data itself, smuggling policy back in.
		let current: [WindowKey: DesiredWindow] = [:]
		var desired = DesiredWindows()
		var spawning = window("codex", label: "Session 1")
		spawning.sessionNumber = 1
		spawning.activityState = .implementing
		desired.windows = ["codex": spawning]

		let result = PoolDiff.diff(desired: desired, current: current)

		XCTAssertEqual(result.toSpawn["codex"], spawning)
	}
}

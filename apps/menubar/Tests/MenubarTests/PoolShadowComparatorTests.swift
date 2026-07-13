import XCTest

@testable import Codogotchi

/// Red-phase tests for P18.04's field-level shadow comparator. Per the
/// ticket's Outcome:
///
/// "A field-level comparator diffs recorded old-pipeline behavior + extracted
/// decision sets against a `(DesiredWindows, PoolMemory)` pair: asserts under
/// tests/debug, emits structured divergence records (tick-input fingerprint,
/// field path, both values) for log-only use. Frame directives compared
/// structurally, never CGRect values. The title-seam delay is a built-in
/// exemption."
///
/// and Review Focus: "Comparator exemption mechanism: exemptions must be
/// named and enumerated (currently exactly one), not pattern-matched loosely."
///
/// `PoolShadowComparator`, `DivergenceRecord`, and `ShadowCompareExemption` do
/// not exist yet.
///
/// Scope note (flagged, not silently assumed): the ticket's full contract
/// compares BOTH decision sets (membership, spawned modes, blocked/pending/
/// TTL-dismissed sets, session numbers, hidden keys — the `PoolMemory`-shaped
/// half) and push payloads (captured via the recording proxy) against the new
/// `(DesiredWindows, PoolMemory)` pair. Modeling a comparable "old decision
/// set" shape is a genuine architecture decision the ticket does not spell
/// out (what carries the old pipeline's equivalent of `PoolMemory`?) — this
/// file scopes to the per-window push-payload half only, representing "old"
/// as a `[WindowKey: DesiredWindow]` (the same shape `DesiredWindows.windows`
/// already uses, since the old pipeline's per-tick controller pushes are
/// field-equivalent to a `DesiredWindow`). The decision-set half is left for
/// the green phase / a follow-up ticket to design explicitly — see this
/// agent's final report.
@MainActor
final class PoolShadowComparatorTests: XCTestCase {

	private func window(_ key: WindowKey) -> DesiredWindow {
		DesiredWindow(key: key)
	}

	// MARK: - Seeded single-field divergence detection

	func testDetectsASeededSingleFieldDivergenceOnInheritedFrameDirective() {
		// Frame directives must be compared structurally (which `WindowKey`
		// inherits from which), never as a `CGRect` value — there is no
		// CGRect on `DesiredWindow` to begin with, so seeding the divergence
		// on `inheritedFrameFrom` directly exercises that structural
		// comparison.
		var old = window("claude:s2")
		old.inheritedFrameFrom = "claude:s1"
		var newWindow = window("claude:s2")
		newWindow.inheritedFrameFrom = "claude:s3"  // seeded divergence

		var desired = DesiredWindows()
		desired.windows = ["claude:s2": newWindow]

		let divergences = PoolShadowComparator.compare(
			old: ["claude:s2": old], new: desired, tickFingerprint: "tick-42")

		XCTAssertEqual(divergences.count, 1)
		let record = try! XCTUnwrap(divergences.first)
		XCTAssertEqual(record.tickFingerprint, "tick-42")
		XCTAssertEqual(record.windowKey, "claude:s2")
		XCTAssertEqual(record.fieldPath, "inheritedFrameFrom")
		XCTAssertTrue(record.oldValue.contains("claude:s1"))
		XCTAssertTrue(record.newValue.contains("claude:s3"))
	}

	func testIdenticalWindowsProduceNoDivergences() {
		let same = window("codex")
		var desired = DesiredWindows()
		desired.windows = ["codex": same]

		let divergences = PoolShadowComparator.compare(
			old: ["codex": same], new: desired, tickFingerprint: "tick-1")

		XCTAssertTrue(divergences.isEmpty)
	}

	// MARK: - Title-seam exemption

	func testTitleSeamDelayIsExemptedForAKeyWithAnInFlightTitleResolutionRequest() {
		// Grill-Me decision 3's documented, accepted divergence: a
		// freshly-resolved title lags ~1 tick behind the old (synchronous)
		// pipeline. `derive` signals "resolution is in flight this tick" via
		// `DesiredWindows.titleResolutionRequests` — the comparator must use
		// that data to scope the exemption to exactly the affected key,
		// never a loose "any sessionLabel mismatch is fine" pattern match.
		let key: WindowKey = "codex:abc"
		let identity = RenderKeyIdentity(origin: "codex", sessionId: "abc")

		var old = window(key)
		old.sessionLabel = "Refactor the diff module"  // old pipeline resolved synchronously

		var newWindow = window(key)
		newWindow.sessionLabel = "Session 1"  // new pipeline: still the fallback this tick

		var desired = DesiredWindows()
		desired.windows = [key: newWindow]
		desired.titleResolutionRequests = [identity]

		let divergences = PoolShadowComparator.compare(
			old: [key: old], new: desired, tickFingerprint: "tick-7")

		XCTAssertTrue(
			divergences.isEmpty,
			"a sessionLabel divergence on a key with an in-flight title-resolution request is the named title-seam exemption")
	}

	func testSessionLabelDivergenceWithoutAnInFlightTitleRequestIsNotExempted() {
		// The same field mismatch, but with NO title-resolution request in
		// flight for this key this tick: this must NOT be silently exempted
		// — otherwise the exemption would be a loose "sessionLabel" pattern
		// match rather than the one named, narrowly-scoped exemption the
		// ticket's Review Focus requires.
		let key: WindowKey = "codex:abc"
		var old = window(key)
		old.sessionLabel = "Old label"
		var newWindow = window(key)
		newWindow.sessionLabel = "Genuinely different label"

		var desired = DesiredWindows()
		desired.windows = [key: newWindow]
		desired.titleResolutionRequests = []  // no seam in flight

		let divergences = PoolShadowComparator.compare(
			old: [key: old], new: desired, tickFingerprint: "tick-8")

		XCTAssertEqual(divergences.count, 1)
		XCTAssertEqual(divergences.first?.fieldPath, "sessionLabel")
	}

	// MARK: - Exemption enumeration (named, not pattern-matched)

	func testExactlyOneNamedExemptionIsEnumerated() {
		XCTAssertEqual(ShadowCompareExemption.allCases.count, 1)
		XCTAssertEqual(ShadowCompareExemption.allCases.first, .titleResolutionDelay)
	}
}

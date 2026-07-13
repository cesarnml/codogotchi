import Foundation
import XCTest

@testable import Codogotchi

/// P18.05 subagent-review fix: `AttentionPayload.summary` is user-facing
/// free text (a submitted prompt's summary). Prior to this fix an
/// `attention` `DivergenceRecord` serialized the whole payload — summary
/// included — via `String(describing:)` into both NSLog and the on-disk
/// shadow-divergence log, unredacted. `PoolShadowComparator` now redacts
/// `summary` at the source (`describeAttention`), so the `DivergenceRecord`
/// itself never carries the secret — proven here end-to-end through the
/// logger's on-disk sink, which is the log hygiene surface this ticket's
/// Review Focus calls out ("no sensitive content").
final class ShadowDivergenceLoggerTests: XCTestCase {
	private var tempHome: URL!

	override func setUp() {
		super.setUp()
		tempHome = FileManager.default.temporaryDirectory
			.appendingPathComponent("ShadowDivergenceLoggerTests-\(UUID().uuidString)")
		setenv("CODOGOTCHI_HOME", tempHome.path, 1)
	}

	override func tearDown() {
		unsetenv("CODOGOTCHI_HOME")
		try? FileManager.default.removeItem(at: tempHome)
		tempHome = nil
		super.tearDown()
	}

	@MainActor
	func testAttentionSummarySecretIsAbsentFromComparatorOutputAndDiskLog() {
		let secret = "the user's confidential prompt about an unreleased feature"

		var old = DesiredWindow(key: "codex")
		old.attention = nil
		var newWindow = DesiredWindow(key: "codex")
		newWindow.attention = AttentionPayload(
			createdAt: "2026-07-13T00:00:00Z", expiresAt: nil, summary: secret, reasonKind: "needs_input")

		var desired = DesiredWindows()
		desired.windows = ["codex": newWindow]

		let divergences = PoolShadowComparator.compare(
			old: ["codex": old], new: desired, tickFingerprint: "tick-secret")

		let attentionDivergence = divergences.first { $0.fieldPath == "attention" }
		XCTAssertNotNil(attentionDivergence)
		XCTAssertFalse(
			attentionDivergence?.newValue.contains(secret) ?? true,
			"the secret must be redacted before it ever reaches a DivergenceRecord")
		XCTAssertTrue(
			attentionDivergence?.newValue.contains("reasonKind") ?? false,
			"safe structural fields must still be present for debugging")

		ShadowDivergenceLogger.log(divergences)

		let logURL = tempHome.appendingPathComponent("logs/shadow-divergence.log")
		let contents = try! String(contentsOf: logURL, encoding: .utf8)
		XCTAssertFalse(contents.contains(secret), "the secret must not be persisted to disk")
		XCTAssertTrue(contents.contains("attention"), "the divergence line itself must still be written")
	}
}

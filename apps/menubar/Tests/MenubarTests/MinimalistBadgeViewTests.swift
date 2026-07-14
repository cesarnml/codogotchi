import AppKit
import XCTest

@testable import Codogotchi

/// Regression coverage for a bug the P18.04 subagent-review found: `apply`'s
/// `applyPromptTimerPresentation` push landed correctly, but a *later*
/// same-tick push (e.g. `applyPlatform`, `applySessionNumber`) that also
/// triggers a badge redraw was clobbering it with a stale
/// `promptTimerStatus?.presentation()`, because the raw `promptTimerStatus`
/// is never updated on the presentation-only path. Fixed by
/// `promptTimerPresentationOverride`, which `configureBadge` now prefers.
@MainActor
final class MinimalistBadgeViewTests: XCTestCase {

	func testPresentationPushSurvivesASubsequentConfigureBadgeCall() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		let presentation = PromptTimerPresentation(label: "0:07", isRunning: true)

		badge.applyPromptTimerPresentation(presentation)
		// A later push in the same tick (e.g. PoolApply's applyPlatform-equivalent)
		// triggers another full badge redraw.
		badge.configureBadge(platform: PlatformAttribution(origin: "claude_code"), activity: .idle, metrics: metrics)

		XCTAssertEqual(
			badge.renderedPromptTimerPresentation, presentation,
			"a later configureBadge call must not clobber a presentation pushed via applyPromptTimerPresentation")
	}

	func testRawStatusPushTakesOverFromAPriorPresentationOverride() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		let staleOverride = PromptTimerPresentation(label: "0:99", isRunning: true)
		let rawStatus = PromptTimerStatus(startedAt: Date(timeIntervalSince1970: 0), endedAt: nil)

		badge.applyPromptTimerPresentation(staleOverride)
		badge.applyPromptTimerStatus(rawStatus)
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)

		XCTAssertEqual(
			badge.renderedPromptTimerPresentation, rawStatus.presentation(),
			"an explicit applyPromptTimerStatus call must clear a stale presentation override, not be shadowed by it"
		)
	}

	// MARK: - Mode-indicator badge (P19.04)

	func testModeIndicatorBadgeRendersProvidedText() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))

		badge.applyModeIndicatorBadge("Combined")

		XCTAssertEqual(badge.renderedModeIndicatorBadge, "Combined")
	}

	func testModeIndicatorBadgeHiddenWhenTextIsNil() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		badge.applyModeIndicatorBadge("Codex")

		badge.applyModeIndicatorBadge(nil)

		XCTAssertNil(badge.renderedModeIndicatorBadge, "nil text must hide the badge, not just clear its string")
	}
}

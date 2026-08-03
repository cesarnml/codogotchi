import AppKit
import XCTest

@testable import Codogotchi

/// Regression coverage for a bug the P18.04 subagent-review found: `apply`'s
/// `applyElapsedPresentation` push landed correctly, but a *later*
/// same-tick push (e.g. `applyPlatform`, `applySessionNumber`) that also
/// triggers a badge redraw was clobbering it with a stale
/// `promptTimerStatus?.presentation()`, because the raw `promptTimerStatus`
/// is never updated on the presentation-only path. Fixed by
/// `elapsedPresentationOverride`, which `configureBadge` now prefers.
@MainActor
final class MinimalistBadgeViewTests: XCTestCase {

	func testPresentationPushSurvivesASubsequentConfigureBadgeCall() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		let presentation = ElapsedPresentation(label: "0:07", isRunning: true, kind: .turn)

		badge.applyElapsedPresentation(presentation)
		// A later push in the same tick (e.g. PoolApply's applyPlatform-equivalent)
		// triggers another full badge redraw.
		badge.configureBadge(platform: PlatformAttribution(origin: "claude_code"), activity: .idle, metrics: metrics)

		XCTAssertEqual(
			badge.renderedElapsedPresentation, presentation,
			"a later configureBadge call must not clobber a presentation pushed via applyElapsedPresentation")
	}

	func testRawStatusPushTakesOverFromAPriorPresentationOverride() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		let staleOverride = ElapsedPresentation(label: "0:99", isRunning: true, kind: .turn)
		let rawStatus = PromptTimerStatus(startedAt: Date(timeIntervalSince1970: 0), endedAt: nil)

		badge.applyElapsedPresentation(staleOverride)
		badge.applyLocalPromptTimerStatus(rawStatus)
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)

		XCTAssertEqual(
			badge.renderedElapsedPresentation, rawStatus.presentation(),
			"an explicit applyLocalPromptTimerStatus call must clear a stale presentation override, not be shadowed by it"
		)
	}

	/// Minimalist has no scene and therefore no idle escalation to source a clock
	/// from — the idle chip reaches it only because the clock is slice-derived and
	/// pushed through the same controller method as the turn clock. Without this,
	/// nothing proves the idle kind survives the Minimalist render path at all.
	func testIdleKindPresentationRendersOnTheMinimalistBadge() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		let idle = ElapsedPresentation(label: "47:00", isRunning: true, kind: .idle)

		badge.applyElapsedPresentation(idle)
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)

		XCTAssertEqual(badge.renderedElapsedPresentation, idle)
		XCTAssertEqual(
			badge.renderedElapsedPresentation?.kind, .idle,
			"the idle kind must survive the Minimalist path — it drives the zzz glyph")
	}

	/// The idle chip appears in Minimalist cases where no chip appeared before, so
	/// it must widen the strip rather than be clipped.
	func testIdleChipWidensTheMinimalistStrip() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)
		let widthWithoutChip = badge.badgePreferredWidth

		badge.applyElapsedPresentation(
			ElapsedPresentation(label: "47:00", isRunning: true, kind: .idle))
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)

		XCTAssertGreaterThan(
			badge.badgePreferredWidth, widthWithoutChip,
			"an idle chip must widen the strip so the duration is not clipped")
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

	func testModeIndicatorWidensPreferredWidthBeyondActivityRow() {
		let badge = MinimalistBadgeView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let metrics = GateBadgeLayout.metrics(scale: 1.0)
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)
		let widthWithoutMode = badge.badgePreferredWidth

		badge.applyModeIndicatorBadge("Combined")
		badge.configureBadge(platform: nil, activity: .idle, metrics: metrics)

		XCTAssertGreaterThan(
			badge.badgePreferredWidth, widthWithoutMode,
			"a populated mode chip must widen the strip so Combined/platform text is not clipped")
	}
}

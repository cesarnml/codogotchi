import XCTest

@testable import Codogotchi

// P15.06 subagent-review Finding 1: `AnimationBadgePanel.ignoresMouseEvents`
// defaults to `true` (click-through) so AppKit never delivers the
// mouse-entered notification `NSView.toolTip` depends on — the session
// tooltip was wired but could never actually display. Fixed by toggling
// `ignoresMouseEvents` off only while a tooltip is present to show.
@MainActor
final class AnimationBadgePanelTests: XCTestCase {

	func testAcceptsMouseEventsWhenASessionTooltipIsPresent() {
		let panel = AnimationBadgePanel()
		XCTAssertTrue(panel.ignoresMouseEvents, "click-through by default, before any tooltip is applied")

		panel.reposition(
			label: "Idle",
			platform: nil,
			inFlight: false,
			sessionNumber: 1,
			sessionTooltip: "Refactor the renderer",
			relativeTo: CGRect(x: 0, y: 0, width: 220, height: 160),
			visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
		)

		XCTAssertFalse(
			panel.ignoresMouseEvents,
			"must accept mouse events while a tooltip is set, or AppKit never shows it")
	}

	func testRemainsClickThroughWithoutASessionTooltip() {
		let panel = AnimationBadgePanel()

		panel.reposition(
			label: "Idle",
			platform: nil,
			inFlight: false,
			sessionNumber: nil,
			sessionTooltip: nil,
			relativeTo: CGRect(x: 0, y: 0, width: 220, height: 160),
			visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
		)

		XCTAssertTrue(panel.ignoresMouseEvents, "no tooltip to show — must stay click-through")
	}

	func testStopsAcceptingMouseEventsWhenTheTooltipClears() {
		let panel = AnimationBadgePanel()
		let petFrame = CGRect(x: 0, y: 0, width: 220, height: 160)
		let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

		panel.reposition(
			label: "Idle", platform: nil, inFlight: false, sessionNumber: 1,
			sessionTooltip: "Refactor the renderer", relativeTo: petFrame, visibleFrame: visibleFrame)
		XCTAssertFalse(panel.ignoresMouseEvents)

		panel.reposition(
			label: "Idle", platform: nil, inFlight: false, sessionNumber: 1,
			sessionTooltip: nil, relativeTo: petFrame, visibleFrame: visibleFrame)
		XCTAssertTrue(panel.ignoresMouseEvents, "must revert to click-through once the tooltip clears")
	}
}

import XCTest

@testable import Codogotchi

// P15.06 subagent-review Finding 1 originally made `ignoresMouseEvents` toggle
// off only while a tooltip was present, since AppKit never delivers the
// mouse-entered notification `NSView.toolTip` depends on while a window is
// click-through. A later pass (right-click-from-any-chrome unification) made
// the panel unconditionally interactive instead — right-click and drag must
// reach the badge regardless of tooltip/session state — which is a strict
// superset of the tooltip fix, so it's still covered.
@MainActor
final class AnimationBadgePanelTests: XCTestCase {

	func testIsInteractiveRegardlessOfSessionTooltip() {
		let panel = AnimationBadgePanel()
		XCTAssertFalse(panel.ignoresMouseEvents, "must accept mouse events so right-click/drag work unconditionally")

		panel.reposition(
			label: "Idle",
			platform: nil,
			inFlight: false,
			sessionNumber: 1,
			sessionTooltip: "Refactor the renderer",
			relativeTo: CGRect(x: 0, y: 0, width: 220, height: 160),
			visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
		)
		XCTAssertFalse(panel.ignoresMouseEvents, "tooltip present — still interactive")

		panel.reposition(
			label: "Idle",
			platform: nil,
			inFlight: false,
			sessionNumber: nil,
			sessionTooltip: nil,
			relativeTo: CGRect(x: 0, y: 0, width: 220, height: 160),
			visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
		)
		XCTAssertFalse(panel.ignoresMouseEvents, "no tooltip — still interactive, not click-through")
	}
}

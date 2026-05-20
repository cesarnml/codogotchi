import XCTest

@testable import Menubar

/// Smoke tests for the menu-bar scaffold.
///
/// `testAppCanInstantiate` exists to wire the test scheme end-to-end so
/// `xcodebuild ... test` succeeds. It is intentionally not a behavior
/// contract — Phase 02 later tickets express behavior via their own tests.
final class MenubarTests: XCTestCase {
	func testAppCanInstantiate() {
		let delegate = MenubarApp()
		XCTAssertNotNil(delegate)
	}
}

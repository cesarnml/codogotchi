import AppKit
import XCTest

@testable import Menubar

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// The status item exposes exactly two items:
///   1. "Open log folder" — opens `~/.codogotchi/` via `NSWorkspace.open(_:)`
///   2. "Quit Menubar" — terminates the app
///
/// Tests inject a workspace stub and a termination spy so menu actions can be
/// invoked synchronously without touching Finder or actually quitting the
/// XCTest process.
final class MenuItemsTests: XCTestCase {
	final class WorkspaceOpenSpy: MenuWorkspaceOpening {
		var openedURLs: [URL] = []

		@discardableResult
		func open(_ url: URL) -> Bool {
			openedURLs.append(url)
			return true
		}
	}

	func testMenuHasExactlyTwoItemsInExpectedOrder() {
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests")
		)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, 2)
		XCTAssertEqual(menu.items[0].title, "Open log folder")
		XCTAssertEqual(menu.items[1].title, "Quit Menubar")
	}

	func testOpenLogFolderActionInvokesWorkspaceOpenWithExpectedURL() {
		let workspace = WorkspaceOpenSpy()
		let expectedURL = URL(fileURLWithPath: "/tmp/codogotchi-tests/logs")
		let builder = MenubarMenu(
			workspace: workspace,
			terminate: {},
			logFolderURL: expectedURL
		)
		let menu = builder.build()
		let openItem = menu.items[0]

		guard let action = openItem.action, let target = openItem.target else {
			return XCTFail("Open log folder menu item must have an action and target")
		}
		_ = target.perform(action, with: openItem)

		XCTAssertEqual(workspace.openedURLs, [expectedURL])
	}

	func testQuitMenubarActionInvokesTerminationSpy() {
		var terminationCount = 0
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: { terminationCount += 1 },
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests")
		)
		let menu = builder.build()
		let quitItem = menu.items[1]

		guard let action = quitItem.action, let target = quitItem.target else {
			return XCTFail("Quit Menubar menu item must have an action and target")
		}
		_ = target.perform(action, with: quitItem)

		XCTAssertEqual(terminationCount, 1)
	}
}

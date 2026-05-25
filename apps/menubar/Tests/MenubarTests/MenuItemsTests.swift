import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// The status item exposes exactly three items:
///   1. "Open log folder" — opens `~/.codogotchi/` via `NSWorkspace.open(_:)`
///   2. "Reveal pet folder" — opens `~/.codex/pets/` via `NSWorkspace.open(_:)`
///   3. "Quit Codogotchi" — terminates the app
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

	func testMenuHasExactlyThreeItemsInExpectedOrder() {
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets")
		)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, 3)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.openLogFolderTitle)
		XCTAssertEqual(menu.items[1].title, MenubarMenu.revealPetFolderTitle)
		XCTAssertEqual(menu.items[2].title, "Quit Codogotchi")
	}

	func testOpenLogFolderActionInvokesWorkspaceOpenWithExpectedURL() {
		let workspace = WorkspaceOpenSpy()
		let expectedURL = URL(fileURLWithPath: "/tmp/codogotchi-tests/logs")
		let builder = MenubarMenu(
			workspace: workspace,
			terminate: {},
			logFolderURL: expectedURL,
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets")
		)
		let menu = builder.build()
		let openItem = menu.items[0]

		guard let action = openItem.action, let target = openItem.target else {
			return XCTFail("Open log folder menu item must have an action and target")
		}
		_ = target.perform(action, with: openItem)

		XCTAssertEqual(workspace.openedURLs, [expectedURL])
	}

	func testRevealPetFolderActionInvokesWorkspaceOpenWithExpectedURL() {
		let workspace = WorkspaceOpenSpy()
		let expectedURL = URL(fileURLWithPath: "/tmp/codex-pets")
		let builder = MenubarMenu(
			workspace: workspace,
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/logs"),
			petFolderURL: expectedURL
		)
		let menu = builder.build()
		let revealItem = menu.items[1]

		guard let action = revealItem.action, let target = revealItem.target else {
			return XCTFail("Reveal pet folder menu item must have an action and target")
		}
		_ = target.perform(action, with: revealItem)

		XCTAssertEqual(workspace.openedURLs, [expectedURL])
	}

	func testDefaultPetFolderURLPointsToCodexPets() {
		XCTAssertTrue(MenubarMenu.defaultPetFolderURL().path.hasSuffix("/.codex/pets"))
	}

	func testQuitCodogotchiActionInvokesTerminationSpy() {
		var terminationCount = 0
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: { terminationCount += 1 },
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets")
		)
		let menu = builder.build()
		let quitItem = menu.items[2]

		guard let action = quitItem.action, let target = quitItem.target else {
			return XCTFail("Quit Codogotchi menu item must have an action and target")
		}
		_ = target.perform(action, with: quitItem)

		XCTAssertEqual(terminationCount, 1)
	}
}

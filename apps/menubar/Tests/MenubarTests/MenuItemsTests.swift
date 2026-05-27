import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// The status item exposes four items:
///   1. "Open log folder" — opens `~/.codogotchi/` via `NSWorkspace.open(_:)`
///   2. "Reveal pet folder" — opens `~/.codex/pets/` via `NSWorkspace.open(_:)`
///   3. "Show/Hide Floating Pet" — toggles the desktop pet surface
///   4. "Quit Codogotchi" — terminates the app
///
/// Tests inject a workspace stub and a termination spy so menu actions can be
/// invoked synchronously without touching Finder or actually quitting the
/// XCTest process.
@MainActor
final class MenuItemsTests: XCTestCase {
	final class WorkspaceOpenSpy: MenuWorkspaceOpening {
		var openedURLs: [URL] = []

		@discardableResult
		func open(_ url: URL) -> Bool {
			openedURLs.append(url)
			return true
		}
	}

	final class FloatingPetVisibilitySpy: FloatingPetVisibilityControlling {
		var isFloatingPetVisible: Bool
		var visibilityRequests: [Bool] = []

		init(isFloatingPetVisible: Bool) {
			self.isFloatingPetVisible = isFloatingPetVisible
		}

		func setFloatingPetVisible(_ visible: Bool) {
			isFloatingPetVisible = visible
			visibilityRequests.append(visible)
		}
	}

	func testMenuHasFloatingPetToggleBeforeQuit() {
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets"),
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, 4)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.openLogFolderTitle)
		XCTAssertEqual(menu.items[1].title, MenubarMenu.revealPetFolderTitle)
		XCTAssertEqual(menu.items[2].title, MenubarMenu.showFloatingPetTitle)
		XCTAssertEqual(menu.items[3].title, "Quit Codogotchi")
	}

	func testFloatingPetToggleTitleReflectsVisibleState() {
		let visibleBuilder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets"),
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: true)
		)
		let hiddenBuilder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets"),
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		)

		XCTAssertEqual(visibleBuilder.build().items[2].title, MenubarMenu.hideFloatingPetTitle)
		XCTAssertEqual(hiddenBuilder.build().items[2].title, MenubarMenu.showFloatingPetTitle)
	}

	func testRefreshFloatingPetMenuItemTitleAfterExternalHide() {
		let controller = FloatingPetVisibilitySpy(isFloatingPetVisible: true)
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets"),
			floatingPetController: controller
		)
		let menu = builder.build()
		let toggleItem = menu.items[2]
		XCTAssertEqual(toggleItem.title, MenubarMenu.hideFloatingPetTitle)

		controller.setFloatingPetVisible(false)
		builder.refreshFloatingPetMenuItemTitle()

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
	}

	func testFloatingPetToggleCallsControllerAndRefreshesTitle() {
		let controller = FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets"),
			floatingPetController: controller
		)
		let menu = builder.build()
		let toggleItem = menu.items[2]

		guard let action = toggleItem.action, let target = toggleItem.target else {
			return XCTFail("Floating pet menu item must have an action and target")
		}
		_ = target.perform(action, with: toggleItem)

		XCTAssertEqual(controller.visibilityRequests, [true])
		XCTAssertEqual(toggleItem.title, MenubarMenu.hideFloatingPetTitle)
	}

	func testFloatingPetToggleIsPresentButDisabledWhenControllerIsMissing() {
		let builder = MenubarMenu(
			workspace: WorkspaceOpenSpy(),
			terminate: {},
			logFolderURL: URL(fileURLWithPath: "/tmp/codogotchi-tests"),
			petFolderURL: URL(fileURLWithPath: "/tmp/codex-pets")
		)
		let menu = builder.build()
		let toggleItem = menu.items[2]

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertFalse(toggleItem.isEnabled)
		XCTAssertEqual(menu.items[3].title, MenubarMenu.quitTitle)
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
		let quitItem = menu.items[3]

		guard let action = quitItem.action, let target = quitItem.target else {
			return XCTFail("Quit Codogotchi menu item must have an action and target")
		}
		_ = target.perform(action, with: quitItem)

		XCTAssertEqual(terminationCount, 1)
	}
}

import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// The status item exposes four items:
///   1. "Show/Hide Pet" — toggles the desktop pet surface
///   2. "Settings…" — opens the Settings panel (⌘,)
///   3. "Quit Codogotchi" — terminates the app
///   4. "⚠ Hooks not active — Retry install" — hidden until post-onboarding hooks are inactive
///
/// (Folder shortcuts moved into Settings → Developer / Pet — see
/// `CodogotchiFoldersTests`.)
///
/// Tests inject a termination spy so menu actions can be invoked synchronously
/// without actually quitting the XCTest process.
@MainActor
final class MenuItemsTests: XCTestCase {
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

	func testMenuItemOrder() {
		let builder = MenubarMenu(
			terminate: {},
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, 4)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.showFloatingPetTitle)
		XCTAssertEqual(menu.items[1].title, MenubarMenu.settingsTitle)
		XCTAssertEqual(menu.items[2].title, MenubarMenu.quitTitle)
		XCTAssertEqual(menu.items[3].title, MenubarMenu.hooksNotActiveTitle)
		XCTAssertTrue(menu.items[3].isHidden, "Hooks not active item should start hidden")
	}

	func testFloatingPetToggleTitleReflectsVisibleState() {
		let visibleBuilder = MenubarMenu(
			terminate: {},
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: true)
		)
		let hiddenBuilder = MenubarMenu(
			terminate: {},
			floatingPetController: FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		)

		XCTAssertEqual(visibleBuilder.build().items[0].title, MenubarMenu.hideFloatingPetTitle)
		XCTAssertEqual(hiddenBuilder.build().items[0].title, MenubarMenu.showFloatingPetTitle)
	}

	func testRefreshFloatingPetMenuItemTitleAfterExternalHide() {
		let controller = FloatingPetVisibilitySpy(isFloatingPetVisible: true)
		let builder = MenubarMenu(terminate: {}, floatingPetController: controller)
		let menu = builder.build()
		let toggleItem = menu.items[0]
		XCTAssertEqual(toggleItem.title, MenubarMenu.hideFloatingPetTitle)

		controller.setFloatingPetVisible(false)
		builder.refreshFloatingPetMenuItemTitle()

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
	}

	func testFloatingPetToggleCallsControllerAndRefreshesTitle() {
		let controller = FloatingPetVisibilitySpy(isFloatingPetVisible: false)
		let builder = MenubarMenu(terminate: {}, floatingPetController: controller)
		let menu = builder.build()
		let toggleItem = menu.items[0]

		guard let action = toggleItem.action, let target = toggleItem.target else {
			return XCTFail("Floating pet menu item must have an action and target")
		}
		_ = target.perform(action, with: toggleItem)

		XCTAssertEqual(controller.visibilityRequests, [true])
		XCTAssertEqual(toggleItem.title, MenubarMenu.hideFloatingPetTitle)
	}

	func testFloatingPetToggleIsPresentButDisabledWhenControllerIsMissing() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		let toggleItem = menu.items[0]

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertFalse(toggleItem.isEnabled)
		XCTAssertEqual(menu.items[2].title, MenubarMenu.quitTitle)
	}

	func testSettingsItemInvokesOpenSettingsCallback() {
		var settingsOpenCount = 0
		let builder = MenubarMenu(terminate: {}, openSettings: { settingsOpenCount += 1 })
		let menu = builder.build()
		let settingsItem = menu.items[1]
		XCTAssertEqual(settingsItem.title, MenubarMenu.settingsTitle)
		XCTAssertTrue(settingsItem.isEnabled)

		guard let action = settingsItem.action, let target = settingsItem.target else {
			return XCTFail("Settings menu item must have an action and target")
		}
		_ = target.perform(action, with: settingsItem)
		XCTAssertEqual(settingsOpenCount, 1)
	}

	func testSettingsItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[1].isEnabled)
	}

	func testQuitCodogotchiActionInvokesTerminationSpy() {
		var terminationCount = 0
		let builder = MenubarMenu(terminate: { terminationCount += 1 })
		let menu = builder.build()
		let quitItem = menu.items[2]

		guard let action = quitItem.action, let target = quitItem.target else {
			return XCTFail("Quit Codogotchi menu item must have an action and target")
		}
		_ = target.perform(action, with: quitItem)

		XCTAssertEqual(terminationCount, 1)
	}
}

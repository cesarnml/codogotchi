import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// Tests inject `FloatingPetWindowPool` (with stub windows) in place of the
/// old single-controller spy. The pool drives the pet section: nil pool →
/// disabled "Show Pet"; 0 origins → disabled "Show Pet"; 1 origin → "Hide Pet";
/// 2+ origins → per-origin hide items.
@MainActor
final class MenuItemsTests: XCTestCase {
	// Minimal stub that conforms to FloatingPetWindowControlling for test injection.
	private final class StubWindow: FloatingPetWindowControlling {
		var isFloatingPetVisible: Bool = false
		func setFloatingPetVisible(_ visible: Bool) { isFloatingPetVisible = visible }
		func apply(state: ActivityState, visualMode: VisualMode) {}
		func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
		func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
		func applyGateBadge(content: GateBadgeContent?) {}
		func applyPlatform(origin: String?) {}
		func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
	}

	private func makePool(origins: [String]) -> FloatingPetWindowPool {
		let pool = FloatingPetWindowPool(
			customizationReader: { .safeDefault },
			windowFactory: { _ in StubWindow() }
		)
		if !origins.isEmpty {
			let perPlatform = Dictionary(
				uniqueKeysWithValues: origins.map { origin in
					(origin, StateSnapshot(
						schemaVersion: EXPECTED_STATE_SCHEMA_VERSION,
						activityState: .idle,
						updatedAt: "2026-06-28T10:00:00.000Z",
						sourceEvent: nil,
						attention: nil
					))
				}
			)
			pool.update(snapshot: PerPlatformSnapshot(
				perPlatform: perPlatform,
				rpgSnapshot: .safeDefault
			))
		}
		return pool
	}

	func testMenuItemOrderWithNilPool() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, 4)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.showFloatingPetTitle)
		XCTAssertEqual(menu.items[1].title, MenubarMenu.settingsTitle)
		XCTAssertEqual(menu.items[2].title, MenubarMenu.quitTitle)
		XCTAssertEqual(menu.items[3].title, MenubarMenu.hooksNotActiveTitle)
		XCTAssertTrue(menu.items[3].isHidden, "Hooks not active item should start hidden")
	}

	func testFloatingPetToggleTitleReflectsVisibleState() {
		// MenubarMenu stores pool weakly; retain pool strongly in a local var.
		let pool = makePool(origins: ["cursor"])
		let visibleBuilder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let hiddenBuilder = MenubarMenu(terminate: {})

		XCTAssertEqual(visibleBuilder.build().items[0].title, MenubarMenu.hideFloatingPetTitle)
		XCTAssertEqual(hiddenBuilder.build().items[0].title, MenubarMenu.showFloatingPetTitle)
		_ = pool  // keep alive
	}

	func testRefreshFloatingPetMenuItemTitleAfterExternalHide() {
		let pool = makePool(origins: ["cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()
		XCTAssertEqual(menu.items[0].title, MenubarMenu.hideFloatingPetTitle)

		// Simulate external hide: pool removes origin
		pool.setVisible(false, for: "cursor")
		builder.refreshFloatingPetMenuItemTitle()

		// After rebuild the first item reflects "Show Pet"
		XCTAssertEqual(menu.items[0].title, MenubarMenu.showFloatingPetTitle)
	}

	func testFloatingPetToggleIsPresentButDisabledWhenPoolIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		let toggleItem = menu.items[0]

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertFalse(toggleItem.isEnabled)
		XCTAssertEqual(menu.items[2].title, MenubarMenu.quitTitle)
	}

	func testTwoOriginsExpandToTwoPetItems() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		// 2 pet items + settings + quit + hooks = 5
		XCTAssertEqual(menu.items.count, 5)
		let titles = Set(menu.items.prefix(2).map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code Pet"))
		XCTAssertTrue(titles.contains("Hide Cursor Pet"))
		_ = pool  // keep alive
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

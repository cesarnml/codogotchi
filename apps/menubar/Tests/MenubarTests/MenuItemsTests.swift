import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// Layout: header (disabled "Codogotchi"), separator, the dynamic pet
/// section, separator, "Show All Pets", "Hide All Pets", separator, "Pets",
/// "Customization", "Settings", separator, "Quit Codogotchi", and a
/// hidden "Hooks not active" item.
///
/// Tests inject `FloatingPetWindowPool` (with stub windows) in place of the
/// old single-controller spy. The pool drives the pet section: nil pool →
/// disabled "Show Pet"; 0 origins → disabled "Show Pet"; 1 origin → "Hide Pet";
/// 2+ origins → per-origin hide items.
@MainActor
final class MenuItemsTests: XCTestCase {
	// Fixed item count surrounding the variable-length pet section:
	// header, separator, [pet section], separator, showAll, hideAll,
	// separator, pets, customization, settings, separator, quit, hooksItem.
	private static let petSectionStartIndex = 2
	private static let fixedItemCount = 12

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

	private func makePool(
		origins: [String],
		renderKeyIdentities: [String: RenderKeyIdentity] = [:],
		sessionLabelReader: @escaping FloatingPetWindowPool.SessionLabelReader = { _ in nil }
	) -> FloatingPetWindowPool {
		let pool = FloatingPetWindowPool(
			customizationReader: { .safeDefault },
			windowFactory: { _, _ in StubWindow() },
			sessionLabelReader: sessionLabelReader
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
				gateBadges: [:],
				rpgSnapshot: .safeDefault,
				renderKeyIdentities: renderKeyIdentities
			))
		}
		return pool
	}

	/// Index of the trailing (non-pet-section) items, offset by however many
	/// pet-section items are currently rendered.
	private func trailingIndex(_ offset: Int, petItemCount: Int) -> Int {
		Self.petSectionStartIndex + petItemCount + offset
	}

	func testMenuItemOrderWithNilPool() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, Self.fixedItemCount + 1)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.headerTitle)
		XCTAssertFalse(menu.items[0].isEnabled, "Header item should be a non-actionable label")
		XCTAssertTrue(menu.items[1].isSeparatorItem)

		let petIndex = Self.petSectionStartIndex
		XCTAssertEqual(menu.items[petIndex].title, MenubarMenu.showFloatingPetTitle)

		let sepIndex = trailingIndex(0, petItemCount: 1)
		XCTAssertTrue(menu.items[sepIndex].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(1, petItemCount: 1)].title, MenubarMenu.showAllPetsTitle)
		XCTAssertEqual(menu.items[trailingIndex(2, petItemCount: 1)].title, MenubarMenu.hideAllPetsTitle)
		XCTAssertTrue(menu.items[trailingIndex(3, petItemCount: 1)].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(4, petItemCount: 1)].title, MenubarMenu.petsTitle)
		XCTAssertEqual(menu.items[trailingIndex(5, petItemCount: 1)].title, MenubarMenu.customizationTitle)
		XCTAssertEqual(menu.items[trailingIndex(6, petItemCount: 1)].title, MenubarMenu.settingsTitle)
		XCTAssertTrue(menu.items[trailingIndex(7, petItemCount: 1)].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(8, petItemCount: 1)].title, MenubarMenu.quitTitle)
		XCTAssertEqual(menu.items[trailingIndex(9, petItemCount: 1)].title, MenubarMenu.hooksNotActiveTitle)
		XCTAssertTrue(menu.items[trailingIndex(9, petItemCount: 1)].isHidden, "Hooks not active item should start hidden")
	}

	func testFloatingPetToggleTitleReflectsVisibleState() {
		// MenubarMenu stores pool weakly; retain pool strongly in a local var.
		let pool = makePool(origins: ["cursor"])
		let visibleBuilder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let hiddenBuilder = MenubarMenu(terminate: {})

		let petIndex = Self.petSectionStartIndex
		XCTAssertEqual(visibleBuilder.build().items[petIndex].title, MenubarMenu.hideFloatingPetTitle)
		XCTAssertEqual(hiddenBuilder.build().items[petIndex].title, MenubarMenu.showFloatingPetTitle)
		_ = pool  // keep alive
	}

	func testRefreshFloatingPetMenuItemTitleAfterExternalHide() {
		let pool = makePool(origins: ["cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()
		let petIndex = Self.petSectionStartIndex
		XCTAssertEqual(menu.items[petIndex].title, MenubarMenu.hideFloatingPetTitle)

		// Simulate external hide: pool removes origin
		pool.setVisible(false, for: "cursor")
		builder.refreshFloatingPetMenuItemTitle()

		// After rebuild the pet item reflects "Show Pet"
		XCTAssertEqual(menu.items[petIndex].title, MenubarMenu.showFloatingPetTitle)
	}

	func testFloatingPetToggleIsPresentButDisabledWhenPoolIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		let toggleItem = menu.items[Self.petSectionStartIndex]

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertFalse(toggleItem.isEnabled)
	}

	func testTwoOriginsExpandToTwoPetItems() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, Self.fixedItemCount + 2)
		let titles = Set(menu.items[Self.petSectionStartIndex..<(Self.petSectionStartIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code Pet"))
		XCTAssertTrue(titles.contains("Hide Cursor Pet"))
		_ = pool  // keep alive
	}

	func testPetsItemInvokesOpenSettingsWithPetTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let petsItem = menu.items[trailingIndex(4, petItemCount: 1)]
		XCTAssertEqual(petsItem.title, MenubarMenu.petsTitle)
		XCTAssertTrue(petsItem.isEnabled)

		guard let action = petsItem.action, let target = petsItem.target else {
			return XCTFail("Pets menu item must have an action and target")
		}
		_ = target.perform(action, with: petsItem)
		XCTAssertEqual(openedTab, .pet)
	}

	func testPetsItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[trailingIndex(4, petItemCount: 1)].isEnabled)
	}

	func testCustomizationItemInvokesOpenSettingsWithCustomizationTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let customizationIndex = trailingIndex(5, petItemCount: 1)
		let customizationItem = menu.items[customizationIndex]
		XCTAssertEqual(customizationItem.title, MenubarMenu.customizationTitle)
		XCTAssertTrue(customizationItem.isEnabled)

		guard let action = customizationItem.action, let target = customizationItem.target else {
			return XCTFail("Customization menu item must have an action and target")
		}
		_ = target.perform(action, with: customizationItem)
		XCTAssertEqual(openedTab, .customization)
	}

	func testCustomizationItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[trailingIndex(5, petItemCount: 1)].isEnabled)
	}

	func testSettingsItemInvokesOpenSettingsCallback() {
		var settingsOpenCount = 0
		let builder = MenubarMenu(terminate: {}, openSettings: { _ in settingsOpenCount += 1 })
		let menu = builder.build()
		let settingsIndex = trailingIndex(6, petItemCount: 1)
		let settingsItem = menu.items[settingsIndex]
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
		XCTAssertFalse(menu.items[trailingIndex(6, petItemCount: 1)].isEnabled)
	}

	func testQuitCodogotchiActionInvokesTerminationSpy() {
		var terminationCount = 0
		let builder = MenubarMenu(terminate: { terminationCount += 1 })
		let menu = builder.build()
		let quitItem = menu.items[trailingIndex(8, petItemCount: 1)]

		guard let action = quitItem.action, let target = quitItem.target else {
			return XCTFail("Quit Codogotchi menu item must have an action and target")
		}
		_ = target.perform(action, with: quitItem)

		XCTAssertEqual(terminationCount, 1)
	}

	func testShowAllPetsShowsEveryHiddenKey() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		pool.setVisible(false, for: "claude_code")
		pool.setVisible(false, for: "cursor")
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		_ = builder.build()

		builder.showAllPets(nil)
		XCTAssertTrue(pool.hiddenWindowKeys.isEmpty)
	}

	func testHideAllPetsHidesEveryActiveOrigin() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		_ = builder.build()

		builder.hideAllPets(nil)
		XCTAssertTrue(pool.activeOrigins.isEmpty)
		XCTAssertEqual(Set(pool.hiddenWindowKeys), Set(["claude_code", "cursor"]))
	}

	func testHiddenPetEnablesShowPetItem() {
		// After setVisible(false), the menu must show an enabled "Show Pet" item.
		let pool = makePool(origins: ["cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()
		let petIndex = Self.petSectionStartIndex
		XCTAssertEqual(menu.items[petIndex].title, MenubarMenu.hideFloatingPetTitle)

		pool.setVisible(false, for: "cursor")
		builder.refreshFloatingPetMenuItemTitle()

		let item = menu.items[petIndex]
		XCTAssertEqual(item.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertTrue(item.isEnabled, "Show Pet must be enabled when a hidden key exists")
		XCTAssertNotNil(item.action, "Show Pet must have an action wired so clicking it works")
	}

	func testMixedActiveAndHiddenExpandsToPerItemList() {
		// 1 active + 1 hidden → 2 items ("Hide X Pet" + "Show X Pet")
		let pool = makePool(origins: ["claude_code", "cursor"])
		pool.setVisible(false, for: "cursor")
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, Self.fixedItemCount + 2)
		let petTitles = Set(menu.items[Self.petSectionStartIndex..<(Self.petSectionStartIndex + 2)].map { $0.title })
		XCTAssertTrue(petTitles.contains("Hide Claude Code Pet"), "active origin must have a Hide item")
		XCTAssertTrue(petTitles.contains("Show Cursor Pet"), "hidden origin must have a Show item")
	}

	func testSessionKeyedOriginFallsBackToSessionNumberWhenNoLabelIsSet() {
		let sessionKey = "claude_code:B116CB55-356F-47CB-B61E-DA8F25636A54"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				sessionKey: RenderKeyIdentity(origin: "claude_code", sessionId: "B116CB55-356F-47CB-B61E-DA8F25636A54")
			]
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.petSectionStartIndex..<(Self.petSectionStartIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code - Session 1 Pet"), "session-keyed item must show the raw origin's platform name and an ordinal, never the raw UUID; got \(titles)")
		_ = pool  // keep alive
	}

	func testSessionKeyedOriginPrefersCustomSessionLabelOverSessionNumber() {
		let sessionKey = "claude_code:B116CB55-356F-47CB-B61E-DA8F25636A54"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				sessionKey: RenderKeyIdentity(origin: "claude_code", sessionId: "B116CB55-356F-47CB-B61E-DA8F25636A54")
			],
			sessionLabelReader: { key in key == sessionKey ? "Refactor Sprint" : nil }
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.petSectionStartIndex..<(Self.petSectionStartIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code - Refactor Sprint Pet"), "got \(titles)")
		_ = pool  // keep alive
	}
}

import AppKit
import XCTest

@testable import Codogotchi

/// Behavior tests for the menu-bar `NSStatusItem` menu.
///
/// Layout: header (disabled "Codogotchi"), separator, the dynamic pet
/// section, separator, "Show All Pets", "Hide All Pets", separator, "Pets",
/// "Customization", "Sessions", "RPG", "Settings", separator, "Quit
/// Codogotchi", and a hidden "Hooks not active" item.
///
/// The pet section is: a disabled "Active Pets" header, one Show/Hide row per
/// active pet (a single row collapses to a plain "Show Pet"/"Hide Pet"
/// title), then the "Live Pets" and "Capped Sessions" submenu items. With no
/// `SessionsTabViewModel` wired (as in most of these tests), active rows fall
/// back to the pool's raw active/hidden sets and both submenus are empty.
@MainActor
final class MenuItemsTests: XCTestCase {
	// Fixed item count surrounding the variable-length pet section:
	// header, separator, [pet section], separator, showAll, hideAll,
	// separator, pets, customization, sessions, rpg, settings, separator,
	// quit, hooksItem.
	private static let petSectionStartIndex = 2
	private static let fixedItemCount = 14
	/// Pet-section items that exist regardless of how many pet rows render:
	/// the "Active Pets" header plus the "Live Pets" and "Capped Sessions"
	/// submenu items.
	private static let petSectionOverhead = 3
	/// Section size for the single-row cases (nil pool, one active, one hidden).
	private static let singleRowSectionCount = petSectionOverhead + 1
	/// Index of the first pet row, just after the "Active Pets" header.
	private static let firstPetRowIndex = petSectionStartIndex + 1

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
		renderKeyIdentities: [WindowKey: RenderKeyIdentity] = [:],
		sessionLabelReader: @escaping SessionLabelReader = { _ in nil },
		sessionTitleReader: @escaping SessionTitleReader = { _, _ in nil },
		retrievedSessionTitleReader: @escaping RetrievedSessionTitleReader = { _ in nil },
		// P18.06: `derive` re-derives (never trusts) whether a key should be
		// session-shaped from `sessionPetsEnabled`, mirroring
		// `resolveRenderKeys`'s own fold rule exactly (see `PoolDerive
		// .desiredWindowKey`'s doc) — unlike the legacy pipeline, which never
		// re-checks a render key's shape once handed one. A caller feeding a
		// raw `.session(...)` key directly into `perPlatform` (bypassing
		// `resolveRenderKeys`, as this helper does) must also enable
		// session-pets for that key's origin, or `derive` correctly folds it
		// down to plain-origin — the same combination a real
		// `resolveRenderKeys` pass would never produce in the first place.
		sessionPetsEnabledOrigins: Set<String> = []
	) -> FloatingPetWindowPool {
		let customization = CustomizationSnapshot(
			platformModes: [:], idleDismissTtlSeconds: 300, menubarIconMonochrome: false,
			combinedMinimalistEnabled: false, minimalistBadgeScale: 1.0,
			sessionPetsEnabled: Dictionary(uniqueKeysWithValues: sessionPetsEnabledOrigins.map { ($0, true) }),
			sessionCap: [:], idleImpatientSeconds: 300, idleFrustratedSeconds: 600, evictSessionPetsEnabled: true)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindow() },
			sessionLabelReader: sessionLabelReader,
			sessionTitleReader: sessionTitleReader,
			retrievedSessionTitleReader: retrievedSessionTitleReader
		)
		if !origins.isEmpty {
			let perPlatform = Dictionary(
				uniqueKeysWithValues: origins.map { origin in
					(WindowKey(rawValue: origin) ?? .origin(origin), StateSnapshot(
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
	/// pet-section items (header + rows + submenus) are currently rendered.
	private func trailingIndex(_ offset: Int, petItemCount: Int) -> Int {
		Self.petSectionStartIndex + petItemCount + offset
	}

	/// Pet-section size for `rowCount` pet rows.
	private func sectionCount(rows rowCount: Int) -> Int {
		Self.petSectionOverhead + rowCount
	}

	func testMenuItemOrderWithNilPool() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()

		let petItemCount = Self.singleRowSectionCount
		XCTAssertEqual(menu.items.count, Self.fixedItemCount + petItemCount)
		XCTAssertEqual(menu.items[0].title, MenubarMenu.headerTitle)
		XCTAssertFalse(menu.items[0].isEnabled, "Header item should be a non-actionable label")
		XCTAssertTrue(menu.items[1].isSeparatorItem)

		let sectionHeader = menu.items[Self.petSectionStartIndex]
		XCTAssertEqual(sectionHeader.title, MenubarMenu.activePetsSectionTitle)
		XCTAssertFalse(sectionHeader.isEnabled, "Active Pets header should be a non-actionable label")
		XCTAssertEqual(menu.items[Self.firstPetRowIndex].title, MenubarMenu.showFloatingPetTitle)
		XCTAssertEqual(menu.items[Self.firstPetRowIndex + 1].title, MenubarMenu.livePetsTitle)
		XCTAssertEqual(menu.items[Self.firstPetRowIndex + 2].title, MenubarMenu.cappedSessionsTitle)

		let sepIndex = trailingIndex(0, petItemCount: petItemCount)
		XCTAssertTrue(menu.items[sepIndex].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(1, petItemCount: petItemCount)].title, MenubarMenu.showAllPetsTitle)
		XCTAssertEqual(menu.items[trailingIndex(2, petItemCount: petItemCount)].title, MenubarMenu.hideAllPetsTitle)
		XCTAssertTrue(menu.items[trailingIndex(3, petItemCount: petItemCount)].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(4, petItemCount: petItemCount)].title, MenubarMenu.petsTitle)
		XCTAssertEqual(menu.items[trailingIndex(5, petItemCount: petItemCount)].title, MenubarMenu.customizationTitle)
		XCTAssertEqual(menu.items[trailingIndex(6, petItemCount: petItemCount)].title, MenubarMenu.sessionsTitle)
		XCTAssertEqual(menu.items[trailingIndex(7, petItemCount: petItemCount)].title, MenubarMenu.rpgTitle)
		XCTAssertEqual(menu.items[trailingIndex(8, petItemCount: petItemCount)].title, MenubarMenu.settingsTitle)
		XCTAssertTrue(menu.items[trailingIndex(9, petItemCount: petItemCount)].isSeparatorItem)
		XCTAssertEqual(menu.items[trailingIndex(10, petItemCount: petItemCount)].title, MenubarMenu.quitTitle)
		XCTAssertEqual(menu.items[trailingIndex(11, petItemCount: petItemCount)].title, MenubarMenu.hooksNotActiveTitle)
		XCTAssertTrue(
			menu.items[trailingIndex(11, petItemCount: petItemCount)].isHidden,
			"Hooks not active item should start hidden")
	}

	func testFloatingPetToggleTitleReflectsVisibleState() {
		// MenubarMenu stores pool weakly; retain pool strongly in a local var.
		let pool = makePool(origins: ["cursor"])
		let visibleBuilder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let hiddenBuilder = MenubarMenu(terminate: {})

		let petIndex = Self.firstPetRowIndex
		XCTAssertEqual(visibleBuilder.build().items[petIndex].title, MenubarMenu.hideFloatingPetTitle)
		XCTAssertEqual(hiddenBuilder.build().items[petIndex].title, MenubarMenu.showFloatingPetTitle)
		_ = pool  // keep alive
	}

	func testRefreshFloatingPetMenuItemTitleAfterExternalHide() {
		let pool = makePool(origins: ["cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()
		let petIndex = Self.firstPetRowIndex
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
		let toggleItem = menu.items[Self.firstPetRowIndex]

		XCTAssertEqual(toggleItem.title, MenubarMenu.showFloatingPetTitle)
		XCTAssertFalse(toggleItem.isEnabled)
	}

	func testTwoOriginsExpandToTwoPetItems() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		XCTAssertEqual(menu.items.count, Self.fixedItemCount + sectionCount(rows: 2))
		let titles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code Pet"))
		XCTAssertTrue(titles.contains("Hide Cursor Pet"))
		_ = pool  // keep alive
	}

	func testPetsItemInvokesOpenSettingsWithPetTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let petsItem = menu.items[trailingIndex(4, petItemCount: Self.singleRowSectionCount)]
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
		XCTAssertFalse(menu.items[trailingIndex(4, petItemCount: Self.singleRowSectionCount)].isEnabled)
	}

	func testCustomizationItemInvokesOpenSettingsWithCustomizationTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let customizationIndex = trailingIndex(5, petItemCount: Self.singleRowSectionCount)
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
		XCTAssertFalse(menu.items[trailingIndex(5, petItemCount: Self.singleRowSectionCount)].isEnabled)
	}

	func testSessionsItemInvokesOpenSettingsWithSessionsTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let sessionsIndex = trailingIndex(6, petItemCount: Self.singleRowSectionCount)
		let sessionsItem = menu.items[sessionsIndex]
		XCTAssertEqual(sessionsItem.title, MenubarMenu.sessionsTitle)
		XCTAssertTrue(sessionsItem.isEnabled)

		guard let action = sessionsItem.action, let target = sessionsItem.target else {
			return XCTFail("Sessions menu item must have an action and target")
		}
		_ = target.perform(action, with: sessionsItem)
		XCTAssertEqual(openedTab, .sessions)
	}

	func testSessionsItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[trailingIndex(6, petItemCount: Self.singleRowSectionCount)].isEnabled)
	}

	func testRPGItemInvokesOpenSettingsWithRPGTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let rpgIndex = trailingIndex(7, petItemCount: Self.singleRowSectionCount)
		let rpgItem = menu.items[rpgIndex]
		XCTAssertEqual(rpgItem.title, MenubarMenu.rpgTitle)
		XCTAssertTrue(rpgItem.isEnabled)

		guard let action = rpgItem.action, let target = rpgItem.target else {
			return XCTFail("RPG menu item must have an action and target")
		}
		_ = target.perform(action, with: rpgItem)
		XCTAssertEqual(openedTab, .rpg)
	}

	func testRPGItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[trailingIndex(7, petItemCount: Self.singleRowSectionCount)].isEnabled)
	}

	func testSettingsItemInvokesOpenSettingsWithGeneralTab() {
		var openedTab: SettingsTab??
		let builder = MenubarMenu(terminate: {}, openSettings: { openedTab = $0 })
		let menu = builder.build()
		let settingsIndex = trailingIndex(8, petItemCount: Self.singleRowSectionCount)
		let settingsItem = menu.items[settingsIndex]
		XCTAssertEqual(settingsItem.title, MenubarMenu.settingsTitle)
		XCTAssertTrue(settingsItem.isEnabled)

		guard let action = settingsItem.action, let target = settingsItem.target else {
			return XCTFail("Settings menu item must have an action and target")
		}
		_ = target.perform(action, with: settingsItem)
		XCTAssertEqual(openedTab, .general)
	}

	func testSettingsItemIsDisabledWhenCallbackIsNil() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()
		XCTAssertFalse(menu.items[trailingIndex(8, petItemCount: Self.singleRowSectionCount)].isEnabled)
	}

	func testQuitCodogotchiActionInvokesTerminationSpy() {
		var terminationCount = 0
		let builder = MenubarMenu(terminate: { terminationCount += 1 })
		let menu = builder.build()
		let quitItem = menu.items[trailingIndex(10, petItemCount: Self.singleRowSectionCount)]

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

	func testShowAllPetsRefreshesTtlForEveryHiddenKeyBeforeUnhiding() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		pool.setVisible(false, for: "claude_code")
		pool.setVisible(false, for: "cursor")
		var refreshed: [WindowKey] = []
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool,
			refreshTtlForShow: { refreshed.append($0) })
		_ = builder.build()

		builder.showAllPets(nil)

		// Without the refresh, a key whose slice TTL-expired while hidden would
		// be un-hidden but never re-spawn — an invisible "Show All".
		XCTAssertEqual(Set(refreshed), Set(["claude_code", "cursor"]))
		XCTAssertTrue(pool.hiddenWindowKeys.isEmpty)
	}

	func testShowPetItemRefreshesTtlForExactlyItsOwnKey() {
		let pool = makePool(origins: ["claude_code", "cursor"])
		var refreshed: [WindowKey] = []
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool,
			refreshTtlForShow: { refreshed.append($0) })
		let menu = builder.build()
		pool.setVisible(false, for: "cursor")
		builder.refreshFloatingPetMenuItemTitle()

		let showItem = menu.items.first {
			($0.representedObject as? WindowKey) == "cursor" && $0.title.hasPrefix("Show")
		}
		XCTAssertNotNil(showItem, "hidden cursor must have a Show item carrying its window key")
		_ = (showItem!.target as AnyObject?)?.perform(showItem!.action!, with: showItem!)

		XCTAssertEqual(
			refreshed, ["cursor"],
			"only the clicked key's TTL clock restarts — never a sibling's")
		XCTAssertFalse(pool.hiddenWindowKeys.contains("cursor"))
	}

	func testMenuWillOpenPrunesOrphanHiddenKeysThenRebuildsThePetSection() {
		// A hidden pet whose slice SlicePruner deleted from disk must vanish
		// from the dropdown at open time — its "Show" entry is a no-op lie.
		let pool = makePool(origins: ["claude_code", "cursor"])
		pool.setVisible(false, for: "cursor")
		var pruneCalls = 0
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool,
			pruneOrphanHiddenKeys: {
				pruneCalls += 1
				// Stand-in for pruneHiddenKeysWithoutBackingSlice finding no
				// slice on disk: the hidden key is gone when the rebuild runs.
				pool.setVisible(true, for: "cursor")
			})
		let menu = builder.build()
		builder.refreshFloatingPetMenuItemTitle()
		XCTAssertTrue(
			menu.items.contains { $0.title == "Show Cursor Pet" },
			"precondition: the zombie Show entry exists before the menu opens")

		builder.menuWillOpen(menu)

		XCTAssertEqual(pruneCalls, 1)
		XCTAssertFalse(
			menu.items.contains { $0.title == "Show Cursor Pet" },
			"the culled key's Show entry must not survive the open-time rebuild")
	}

	func testMenuWillOpenIgnoresForeignMenus() {
		let pool = makePool(origins: ["claude_code"])
		var pruneCalls = 0
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool,
			pruneOrphanHiddenKeys: { pruneCalls += 1 })
		_ = builder.build()

		builder.menuWillOpen(NSMenu())

		XCTAssertEqual(pruneCalls, 0, "a submenu or foreign menu must not trigger the prune")
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
		let petIndex = Self.firstPetRowIndex
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

		XCTAssertEqual(menu.items.count, Self.fixedItemCount + sectionCount(rows: 2))
		let petTitles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(petTitles.contains("Hide Claude Code Pet"), "active origin must have a Hide item")
		XCTAssertTrue(petTitles.contains("Show Cursor Pet"), "hidden origin must have a Show item")
	}

	func testSessionKeyedOriginFallsBackToSessionNumberWhenNoLabelIsSet() {
		let sessionKey = "claude_code:B116CB55-356F-47CB-B61E-DA8F25636A54"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				WindowKey(rawValue: sessionKey)!: RenderKeyIdentity(origin: "claude_code", sessionId: "B116CB55-356F-47CB-B61E-DA8F25636A54")
			],
			sessionPetsEnabledOrigins: ["claude_code"]
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code - Session 1 Pet"), "session-keyed item must show the raw origin's platform name and an ordinal, never the raw UUID; got \(titles)")
		_ = pool  // keep alive
	}

	func testSessionKeyedOriginPrefersCustomSessionLabelOverSessionNumber() {
		let sessionKey = "claude_code:B116CB55-356F-47CB-B61E-DA8F25636A54"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				WindowKey(rawValue: sessionKey)!: RenderKeyIdentity(origin: "claude_code", sessionId: "B116CB55-356F-47CB-B61E-DA8F25636A54")
			],
			sessionLabelReader: { key in key.rawValue == sessionKey ? "Refactor Sprint" : nil },
			sessionPetsEnabledOrigins: ["claude_code"]
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Claude Code - Refactor Sprint Pet"), "got \(titles)")
		_ = pool  // keep alive
	}

	func testSessionKeyedOriginUsesRetrievedSessionTitleBeforeSessionNumber() {
		let sessionKey = "codex:s1"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				WindowKey(rawValue: sessionKey)!: RenderKeyIdentity(origin: "codex", sessionId: "s1")
			],
			retrievedSessionTitleReader: { key in key.rawValue == sessionKey ? "Rename testing prompts" : nil },
			sessionPetsEnabledOrigins: ["codex"]
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Codex - Rename testing prompts Pet"), "got \(titles)")
		_ = pool  // keep alive
	}

	func testSessionKeyedOriginPrefersCustomSessionLabelOverRetrievedSessionTitle() {
		let sessionKey = "codex:s1"
		let pool = makePool(
			origins: ["cursor", sessionKey],
			renderKeyIdentities: [
				WindowKey(rawValue: sessionKey)!: RenderKeyIdentity(origin: "codex", sessionId: "s1")
			],
			sessionLabelReader: { key in key.rawValue == sessionKey ? "Manual label" : nil },
			retrievedSessionTitleReader: { key in key.rawValue == sessionKey ? "Rename testing prompts" : nil },
			sessionPetsEnabledOrigins: ["codex"]
		)
		let builder = MenubarMenu(terminate: {}, floatingPetPool: pool)
		let menu = builder.build()

		let titles = Set(menu.items[Self.firstPetRowIndex..<(Self.firstPetRowIndex + 2)].map { $0.title })
		XCTAssertTrue(titles.contains("Hide Codex - Manual label Pet"), "got \(titles)")
		XCTAssertFalse(titles.contains("Hide Codex - Rename testing prompts Pet"), "got \(titles)")
		_ = pool  // keep alive
	}

	// MARK: - Lifecycle tiering (shared SessionsTabViewModel)

	/// Writes a slice file into `dir` and back-dates its mtime by `age`.
	private func writeSlice(named name: String, in dir: String, age: TimeInterval) throws {
		let path = (dir as NSString).appendingPathComponent(name)
		try #"{"schema_version": 6}"#.write(toFile: path, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: path)
	}

	private func makeTempStateDir() throws -> String {
		let dir = NSTemporaryDirectory() + "menu-items-tests-" + UUID().uuidString
		try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
		return dir
	}

	func testViewModelWiredMenuDropsStaleHiddenKeysFromActiveAndShowsFreshOnes() throws {
		// Two hidden keys: one fresh (<2h) and one stale (>2h but <24h). The
		// old pool-only menu listed both; the tiered menu must list only the
		// fresh one under Active — the stale one belongs to Settings > Sessions
		// (Archived), not the dropdown.
		let dir = try makeTempStateDir()
		try writeSlice(named: "claude_code:fresh.json", in: dir, age: 60)
		try writeSlice(named: "claude_code:stale.json", in: dir, age: 3 * 60 * 60)
		let pool = makePool(origins: [])
		pool.setVisible(false, for: "claude_code:fresh")
		pool.setVisible(false, for: "claude_code:stale")
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel)
		let menu = builder.build()

		let showTitles = menu.items.filter { $0.title.hasPrefix("Show") }.map(\.title)
		XCTAssertTrue(
			menu.items.contains { ($0.representedObject as? WindowKey) == "claude_code:fresh" },
			"the fresh hidden key must keep its Show entry; got \(showTitles)")
		XCTAssertFalse(
			menu.items.contains { ($0.representedObject as? WindowKey) == "claude_code:stale" },
			"a hidden key past the 2h fresh window must not appear under Active Pets; got \(showTitles)")
	}

	func testLivePetsSubmenuListsFreshUnrenderedSessionsWithShowActions() throws {
		// A fresh slice that is neither rendered nor hidden (e.g. its platform
		// is folded into Combined, or it never spawned) is Live: reachable via
		// the Live Pets submenu with a real Show action.
		let dir = try makeTempStateDir()
		try writeSlice(named: "codex:live-one.json", in: dir, age: 60)
		let pool = makePool(origins: [])
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		var refreshed: [WindowKey] = []
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel,
			refreshTtlForShow: { refreshed.append($0) })
		let menu = builder.build()

		guard let liveItem = menu.items.first(where: { $0.title == MenubarMenu.livePetsTitle }),
			let submenu = liveItem.submenu
		else {
			return XCTFail("menu must carry a Live Pets item with a submenu")
		}
		let rowItem = submenu.items.first { ($0.representedObject as? WindowKey) == "codex:live-one" }
		XCTAssertNotNil(rowItem, "the live session must have a submenu row; got \(submenu.items.map(\.title))")

		_ = (rowItem!.target as AnyObject?)?.perform(rowItem!.action!, with: rowItem!)
		XCTAssertEqual(
			refreshed, [.origin("codex")],
			"Show on a Live row must refresh the platform's rendered window key")
	}

	func testLivePetShowTargetsHiddenCombinedWindow() throws {
		let dir = try makeTempStateDir()
		try writeSlice(named: "codex:one.json", in: dir, age: 30)
		try writeSlice(named: "codex:two.json", in: dir, age: 60)
		let customization = CustomizationSnapshot(
			platformModes: ["codex": .combined], idleDismissTtlSeconds: 300,
			menubarIconMonochrome: false, combinedMinimalistEnabled: true,
			minimalistBadgeScale: 1.0, sessionPetsEnabled: ["codex": true],
			sessionCap: ["codex": 2], idleImpatientSeconds: 300,
			idleFrustratedSeconds: 600, evictSessionPetsEnabled: true)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindow() })
		pool.setVisible(false, for: .combined)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		var refreshed: [WindowKey] = []
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel,
			refreshTtlForShow: { refreshed.append($0) })
		let menu = builder.build()
		let liveItem = try XCTUnwrap(menu.items.first { $0.title == MenubarMenu.livePetsTitle })
		let rowItem = try XCTUnwrap(liveItem.submenu?.items.first)

		_ = (rowItem.target as AnyObject?)?.perform(rowItem.action!, with: rowItem)

		XCTAssertFalse(pool.hiddenWindowKeys.contains(.combined))
		XCTAssertEqual(refreshed, [.combined])
	}

	func testShowAllPetsIncludesHiddenCombinedTargetRepresentedByLiveRows() throws {
		let dir = try makeTempStateDir()
		try writeSlice(named: "codex:one.json", in: dir, age: 30)
		try writeSlice(named: "codex:two.json", in: dir, age: 60)
		let customization = CustomizationSnapshot(
			platformModes: ["codex": .combined], idleDismissTtlSeconds: 300,
			menubarIconMonochrome: false, combinedMinimalistEnabled: true,
			minimalistBadgeScale: 1.0, sessionPetsEnabled: ["codex": true],
			sessionCap: ["codex": 2], idleImpatientSeconds: 300,
			idleFrustratedSeconds: 600, evictSessionPetsEnabled: true)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindow() })
		pool.setVisible(false, for: .combined)
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		var refreshed: [WindowKey] = []
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel,
			refreshTtlForShow: { refreshed.append($0) })
		_ = builder.build()

		builder.showAllPets(nil)

		XCTAssertFalse(pool.hiddenWindowKeys.contains(.combined))
		XCTAssertEqual(refreshed, [.combined])
	}

	func testLivePetsSubmenuShowsDisabledPlaceholderWhenEmpty() {
		let builder = MenubarMenu(terminate: {})
		let menu = builder.build()

		guard let liveItem = menu.items.first(where: { $0.title == MenubarMenu.livePetsTitle }),
			let submenu = liveItem.submenu
		else {
			return XCTFail("menu must carry a Live Pets item with a submenu")
		}
		XCTAssertEqual(submenu.items.map(\.title), [MenubarMenu.noLivePetsTitle])
		XCTAssertFalse(submenu.items[0].isEnabled)
	}

	func testTtlDismissedPetRegistersAsActiveHiddenNotLive() throws {
		// A pet hidden by the "Hide Idle Pet After" idle-dismiss TTL must show
		// under Active Pets with a Show entry — same treatment as a user Hide
		// — and must NOT appear in the Live Pets submenu.
		let dir = try makeTempStateDir()
		try writeSlice(named: "claude_code.json", in: dir, age: 120)
		try writeSlice(named: "cursor.json", in: dir, age: 30)
		let customization = CustomizationSnapshot(
			platformModes: [:],
			idleDismissTtlSeconds: 60,
			menubarIconMonochrome: false,
			combinedMinimalistEnabled: false,
			minimalistBadgeScale: 1.0
		)
		var currentTime = Date(timeIntervalSinceReferenceDate: 0)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindow() },
			now: { currentTime }
		)
		let snapshot = { (cursorUpdated: String) in
			PerPlatformSnapshot(
				perPlatform: [
					"claude_code": StateSnapshot(
						schemaVersion: EXPECTED_STATE_SCHEMA_VERSION, activityState: .idle,
						updatedAt: "2026-07-01T10:00:00.000Z", sourceEvent: nil, attention: nil),
					"cursor": StateSnapshot(
						schemaVersion: EXPECTED_STATE_SCHEMA_VERSION, activityState: .implementing,
						updatedAt: cursorUpdated, sourceEvent: nil, attention: nil),
				],
				gateBadges: [:], rpgSnapshot: .safeDefault, renderKeyIdentities: [:])
		}
		pool.update(snapshot: snapshot("2026-07-01T10:00:01.000Z"))
		currentTime = currentTime.addingTimeInterval(61)
		pool.update(snapshot: snapshot("2026-07-01T10:01:30.000Z"))
		XCTAssertEqual(pool.ttlDismissedWindowKeys, ["claude_code"], "precondition: the idle pet must be TTL-dismissed")

		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel)
		let menu = builder.build()

		let activeShowItem = menu.items.first {
			($0.representedObject as? WindowKey) == "claude_code" && $0.title.hasPrefix("Show")
		}
		XCTAssertNotNil(
			activeShowItem,
			"the TTL-dismissed pet must have a Show entry under Active Pets; got \(menu.items.map(\.title))")

		guard let liveItem = menu.items.first(where: { $0.title == MenubarMenu.livePetsTitle }),
			let liveSubmenu = liveItem.submenu
		else {
			return XCTFail("menu must carry a Live Pets item with a submenu")
		}
		XCTAssertFalse(
			liveSubmenu.items.contains { ($0.representedObject as? WindowKey) == "claude_code" },
			"a TTL-dismissed pet is Active (hidden), not Live; got \(liveSubmenu.items.map(\.title))")
	}

	func testCappedSessionsSubmenuIsStatusOnlyWithCustomizationJump() throws {
		// Two fresh session-keyed slices for one origin, cap 1: the loser of
		// the cap fight must surface under Capped Sessions as a status row
		// (no Show — the cap partition would silently ignore it) plus an
		// "Open Customization…" jump.
		let dir = try makeTempStateDir()
		try writeSlice(named: "claude_code:winner.json", in: dir, age: 30)
		try writeSlice(named: "claude_code:capped.json", in: dir, age: 60)
		let customization = CustomizationSnapshot(
			platformModes: [:],
			idleDismissTtlSeconds: 300,
			menubarIconMonochrome: false,
			combinedMinimalistEnabled: false,
			minimalistBadgeScale: 1.0,
			sessionPetsEnabled: ["claude_code": true],
			sessionCap: ["claude_code": 1],
			idleImpatientSeconds: 300,
			idleFrustratedSeconds: 600,
			evictSessionPetsEnabled: true
		)
		let pool = FloatingPetWindowPool(
			customizationReader: { customization },
			windowFactory: { _, _ in StubWindow() }
		)
		let perSession = [
			"claude_code:winner": StateSnapshot(
				schemaVersion: EXPECTED_STATE_SCHEMA_VERSION, activityState: .implementing,
				updatedAt: "2026-07-01T10:00:01.000Z", sourceEvent: nil, attention: nil),
			"claude_code:capped": StateSnapshot(
				schemaVersion: EXPECTED_STATE_SCHEMA_VERSION, activityState: .idle,
				updatedAt: "2026-07-01T10:00:00.000Z", sourceEvent: nil, attention: nil),
		]
		let resolution = resolveRenderKeys(perSession: perSession, customization: customization)
		pool.update(snapshot: PerPlatformSnapshot(
			perPlatform: resolution.states,
			gateBadges: [:],
			rpgSnapshot: .safeDefault,
			renderKeyIdentities: resolution.identities
		))
		XCTAssertEqual(pool.pendingSessionKeys, ["claude_code:capped"], "precondition: cap 1 must hold the idle session")

		var openedTab: SettingsTab??
		let viewModel = SessionsTabViewModel(stateDirectoryPath: dir, pool: pool)
		let builder = MenubarMenu(
			terminate: {}, floatingPetPool: pool, sessionsTabViewModel: viewModel,
			openSettings: { openedTab = $0 })
		let menu = builder.build()

		guard let cappedItem = menu.items.first(where: { $0.title == MenubarMenu.cappedSessionsTitle }),
			let submenu = cappedItem.submenu
		else {
			return XCTFail("menu must carry a Capped Sessions item with a submenu")
		}
		let statusRow = submenu.items.first { $0.title.hasSuffix("session cap reached") }
		XCTAssertNotNil(statusRow, "the capped session must have a status row; got \(submenu.items.map(\.title))")
		XCTAssertNil(statusRow?.action, "a capped row must be status-only — Show would be a silent no-op")

		guard let liveItem = menu.items.first(where: { $0.title == MenubarMenu.livePetsTitle }),
			let liveSubmenu = liveItem.submenu
		else {
			return XCTFail("menu must carry a Live Pets item with a submenu")
		}
		XCTAssertFalse(
			liveSubmenu.items.contains { ($0.representedObject as? WindowKey) == "claude_code:capped" },
			"a cap-pending session must appear under Capped Sessions, not Live Pets")

		guard let openItem = submenu.items.first(where: { $0.title == MenubarMenu.openCustomizationTitle }),
			let action = openItem.action, let target = openItem.target
		else {
			return XCTFail("Capped Sessions submenu must end with an Open Customization… jump")
		}
		_ = target.perform(action, with: openItem)
		XCTAssertEqual(openedTab, .customization, "the jump must open Settings > Customization (the session-cap control)")
	}
}

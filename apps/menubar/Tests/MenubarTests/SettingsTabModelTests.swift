import XCTest

@testable import Codogotchi

final class SettingsTabModelTests: XCTestCase {

	func testHasSixTabsInOrder() {
		let model = SettingsTabModel()
		XCTAssertEqual(model.tabs.count, 6)
		XCTAssertEqual(model.tabs, [.general, .pet, .customization, .rpg, .developer, .about])
	}

	func testCustomizationTabIsAtIndexTwo() {
		let tabs = SettingsTab.allCases
		XCTAssertEqual(tabs.count, 6)
		XCTAssertEqual(tabs[2], .customization, "customization must appear between pet and rpg")
	}

	func testDefaultSelectionIsGeneral() {
		let model = SettingsTabModel()
		XCTAssertEqual(model.selected, .general)
	}

	func testSelectionChangeIsObservable() {
		let model = SettingsTabModel()
		var observed: [SettingsTab] = []
		model.onSelectionChange = { observed.append($0) }
		model.select(.developer)
		model.select(.about)
		XCTAssertEqual(model.selected, .about)
		XCTAssertEqual(observed, [.developer, .about])
	}

	func testSelectingCurrentTabDoesNotNotify() {
		let model = SettingsTabModel()
		var count = 0
		model.onSelectionChange = { _ in count += 1 }
		model.select(.general)
		XCTAssertEqual(count, 0)
	}

	func testTabTitles() {
		XCTAssertEqual(SettingsTab.general.title, "General")
		XCTAssertEqual(SettingsTab.pet.title, "Pet")
		XCTAssertEqual(SettingsTab.customization.title, "Customization")
		XCTAssertEqual(SettingsTab.rpg.title, "RPG")
		XCTAssertEqual(SettingsTab.developer.title, "Developer")
		XCTAssertEqual(SettingsTab.about.title, "About")
	}
}

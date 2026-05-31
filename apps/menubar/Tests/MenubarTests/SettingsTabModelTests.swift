import XCTest

@testable import Codogotchi

final class SettingsTabModelTests: XCTestCase {

	func testHasFourTabsInOrder() {
		let model = SettingsTabModel()
		XCTAssertEqual(model.tabs, [.general, .pet, .developer, .about])
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
		XCTAssertEqual(SettingsTab.developer.title, "Developer")
		XCTAssertEqual(SettingsTab.about.title, "About")
	}
}

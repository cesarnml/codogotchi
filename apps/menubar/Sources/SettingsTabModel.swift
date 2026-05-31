import Foundation

// RED stub — real implementation lands in the green step of P8.03.

enum SettingsTab: Int, CaseIterable {
	case general
	case pet
	case developer
	case about

	var title: String { "" }
}

final class SettingsTabModel {
	let tabs: [SettingsTab] = []
	private(set) var selected: SettingsTab = .general
	var onSelectionChange: ((SettingsTab) -> Void)?

	init(selected: SettingsTab = .general) {
		self.selected = selected
	}

	func select(_ tab: SettingsTab) {}
}

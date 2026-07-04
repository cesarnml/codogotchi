import Foundation

/// The selectable tabs in the Settings window, in display order.
enum SettingsTab: Int, CaseIterable {
	case general
	case pet
	case customization
	case rpg
	case developer
	case about

	var title: String {
		switch self {
		case .general: return "General"
		case .pet: return "Pet"
		case .customization: return "Customization"
		case .rpg: return "RPG"
		case .developer: return "Developer"
		case .about: return "About"
		}
	}

	/// SF Symbol name for the custom tab-strip control. Kept as a plain string
	/// (no `NSImage`) so this file stays AppKit-free and unit-testable.
	var symbolName: String {
		switch self {
		case .general: return "gearshape"
		case .pet: return "pawprint"
		case .customization: return "wand.and.stars"
		case .rpg: return "gamecontroller.fill"
		case .developer: return "chevron.left.forwardslash.chevron.right"
		case .about: return "info.circle"
		}
	}
}

/// Observable selection state for the Settings tab container.
///
/// Pure model with no AppKit dependency so tab order and selection behaviour are
/// unit-testable independent of window/layout concerns (`SettingsWindowController`
/// owns the AppKit `NSTabView` and forwards selection through this model).
final class SettingsTabModel {
	/// All tabs in display order.
	let tabs: [SettingsTab] = SettingsTab.allCases

	private(set) var selected: SettingsTab

	/// Fired only when `select(_:)` actually changes the selection.
	var onSelectionChange: ((SettingsTab) -> Void)?

	init(selected: SettingsTab = .general) {
		self.selected = selected
	}

	/// Selects `tab`. No-op (and no notification) when it is already selected.
	func select(_ tab: SettingsTab) {
		guard tab != selected else { return }
		selected = tab
		onSelectionChange?(tab)
	}
}

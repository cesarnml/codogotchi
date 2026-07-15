import XCTest

@testable import Codogotchi

/// Prune menu copy uses the bare `pruneTitle`; fold-display threading is
/// deleted end-to-end (P21.02) now that mode/session badges carry identity.
final class FloatingPetPromptBuilderTests: XCTestCase {
	private func makeCapabilities(
		hasActiveSession: Bool = true
	) -> FloatingPetPromptCapabilities {
		FloatingPetPromptCapabilities(
			offersForceIdle: false,
			sessionLabel: "Session 1",
			hasActiveSession: hasActiveSession,
			modeSwitchTitle: FloatingPetHidePrompt.minimalistModeTitle,
			offersPanelSize: false,
			hideItemTitle: FloatingPetHidePrompt.title,
			// Red asserts this property is gone; production still has it until green.
			foldedSessionDisplay: nil
		)
	}

	private func noopHandlers() -> FloatingPetPromptHandlers {
		FloatingPetPromptHandlers(
			forceIdle: {}, rename: {}, syncLabel: {}, prune: {}, modeSwitch: {}, panelSize: {},
			hideAllOtherPets: {}, hideThis: {})
	}

	private func pruneTitle(from items: [FloatingPetPromptItem]) -> String? {
		items.first { $0.title.hasPrefix("Prune") }?.title
	}

	func testPruneMenuTitleIsBareConstant() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: makeCapabilities(), handlers: noopHandlers())
		XCTAssertEqual(pruneTitle(from: items), FloatingPetHidePrompt.pruneTitle)
	}

	func testPromptCapabilitiesHasNoFoldedSessionDisplayProperty() {
		let labels = Set(Mirror(reflecting: makeCapabilities()).children.compactMap(\.label))
		XCTAssertFalse(
			labels.contains("foldedSessionDisplay"),
			"foldedSessionDisplay must be removed from FloatingPetPromptCapabilities")
	}

	func testDesiredWindowHasNoFoldedSessionDisplayProperty() {
		let labels = Set(Mirror(reflecting: DesiredWindow(key: "codex")).children.compactMap(\.label))
		XCTAssertFalse(
			labels.contains("foldedSessionDisplay"),
			"foldedSessionDisplay must be removed from DesiredWindow")
	}
}

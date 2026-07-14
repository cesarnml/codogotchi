import XCTest

@testable import Codogotchi

/// Prune menu copy: fold windows used to expand with
/// `"(platform · label)"` (P19.03); that expansion is retired now that
/// mode/session badges already surface the same identity on the panel.
final class FloatingPetPromptBuilderTests: XCTestCase {
	private func makeCapabilities(
		hasActiveSession: Bool = true,
		foldedSessionDisplay: String? = nil
	) -> FloatingPetPromptCapabilities {
		FloatingPetPromptCapabilities(
			offersForceIdle: false,
			sessionLabel: "Session 1",
			hasActiveSession: hasActiveSession,
			modeSwitchTitle: FloatingPetHidePrompt.minimalistModeTitle,
			offersPanelSize: false,
			hideItemTitle: FloatingPetHidePrompt.title,
			foldedSessionDisplay: foldedSessionDisplay
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

	func testFoldWindowPruneTitleStaysBareWhenBadgesCarryIdentity() {
		let capabilities = makeCapabilities(
			foldedSessionDisplay: "Claude Code · refactor the diff module")
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: noopHandlers())

		XCTAssertEqual(pruneTitle(from: items), FloatingPetHidePrompt.pruneTitle)
	}

	func testNonFoldWindowPruneTitleStaysBare() {
		let capabilities = makeCapabilities(foldedSessionDisplay: nil)
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: noopHandlers())

		XCTAssertEqual(pruneTitle(from: items), FloatingPetHidePrompt.pruneTitle)
	}

	func testPruneMenuTitleHelperIgnoresFoldedDisplay() {
		XCTAssertEqual(
			FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay: "Codex · fix flaky test"),
			FloatingPetHidePrompt.pruneTitle)
		XCTAssertEqual(
			FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay: nil),
			FloatingPetHidePrompt.pruneTitle)
	}
}

import XCTest

@testable import Codogotchi

/// P19.03 — the Prune menu item names the resolved session's identity for a
/// fold window (`resolvedIdentity != key`), and stays the existing bare form
/// for a genuinely solo window (`resolvedIdentity == key`).
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

	func testFoldWindowPruneTitleIncludesResolvedSessionIdentity() {
		let capabilities = makeCapabilities(foldedSessionDisplay: "Claude Code · refactor the diff module")
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: noopHandlers())

		XCTAssertEqual(pruneTitle(from: items), "Prune Session (Claude Code · refactor the diff module)")
	}

	func testNonFoldWindowPruneTitleStaysBare() {
		let capabilities = makeCapabilities(foldedSessionDisplay: nil)
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: noopHandlers())

		XCTAssertEqual(pruneTitle(from: items), FloatingPetHidePrompt.pruneTitle)
	}

	func testPruneMenuTitleHelperFormatsFoldedDisplay() {
		XCTAssertEqual(
			FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay: "Codex · fix flaky test"),
			"Prune Session (Codex · fix flaky test)")
	}

	func testPruneMenuTitleHelperStaysBareWithoutFoldedDisplay() {
		XCTAssertEqual(FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay: nil), "Prune Session")
	}
}

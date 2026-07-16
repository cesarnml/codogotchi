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
			hideItemTitle: FloatingPetHidePrompt.title
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

	/// Source-scan complement to `testPoolApplyDoesNotPushFoldedSessionDisplay`:
	/// that test only Mirrors `DesiredWindow`. A regression that restores only
	/// `applyFoldedSessionDisplay` on the pool-facing protocols would evade it.
	func testPoolFacingProtocolsDoNotDeclareApplyFoldedSessionDisplay() throws {
		let repoRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // MenubarTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // menubar
			.deletingLastPathComponent() // apps
			.deletingLastPathComponent() // repository root
		let source = try String(
			contentsOf: repoRoot.appendingPathComponent(
				"apps/menubar/Sources/Windows/FloatingPetController.swift"),
			encoding: .utf8)
		XCTAssertFalse(
			source.contains("func applyFoldedSessionDisplay("),
			"FloatingPetWindowControlling / PanelManaging must not declare applyFoldedSessionDisplay (P21.02)")
	}
}

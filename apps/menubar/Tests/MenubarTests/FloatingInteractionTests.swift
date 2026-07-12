import AppKit
import XCTest

@testable import Codogotchi

/// P4.07 — Mouse-reactive reserved Codex rows.
///
/// These tests assert that the reserved Codex rows (`running-right`,
/// `running-left`, `jumping`) are exposed by `CodexPet` independently of
/// `ActivityState`, that the `FloatingPetScene` honours them as a transient
/// interaction overlay above the activity-driven animation, that missing
/// reserved rows degrade gracefully to the current activity frames, and
/// that the menu-bar renderer never consumes the reserved rows because the
/// `ActivityState`-keyed row map does not reference them.
@MainActor
final class FloatingInteractionTests: XCTestCase {
	// MARK: - Fixture path helpers

	private func maliFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/mali")
			.path
	}

	private func maewFixtureDirectory() -> String {
		let thisFile = URL(fileURLWithPath: #file)
		return thisFile
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/maew")
			.path
	}

	private func makeScene(
		size: CGSize = CGSize(width: 180, height: 140),
		codexPet: CodexPet? = nil,
		codogotchiPet: CodogotchiPet? = nil,
		interactionFramesProvider: ((FloatingInteraction) -> [CodexPet.Frame])? = nil
	) throws -> FloatingPetScene {
		try FloatingPetScene(
			size: size,
			codexPet: codexPet ?? CodexPet(petDirectory: maliFixtureDirectory()),
			codogotchiPet: codogotchiPet ?? CodogotchiPet(petDirectory: maewFixtureDirectory()),
			interactionFramesProvider: interactionFramesProvider
		)
	}

	// MARK: - CodexPet reserved-row exposure

	func testInteractionRowMapRunningRightRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.runningRight]?.rowIndex,
			1,
			"running-right must use Codex row 1 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapRunningLeftRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.runningLeft]?.rowIndex,
			2,
			"running-left must use Codex row 2 per the animation-state-vocabulary contract"
		)
	}

	func testInteractionRowMapJumpingRowIndex() {
		XCTAssertEqual(
			CodexPet.interactionRowMap[.jumping]?.rowIndex,
			4,
			"jumping must use Codex row 4 per the animation-state-vocabulary contract"
		)
	}

	func testReservedRowsAbsentFromActivityRowMap() {
		let reservedRowIndices: Set<Int> = [1, 2, 4]
		let activityRowIndices = Set(CodexPet.rowMap.values.map(\.rowIndex))
		XCTAssertTrue(
			activityRowIndices.isDisjoint(with: reservedRowIndices),
			"ActivityState row map must not consume reserved rows \(reservedRowIndices); found \(activityRowIndices)"
		)
	}

	func testInteractionFramesNonEmptyFromFixture() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for interaction in FloatingInteraction.allCases {
			let frames = pet.frames(forInteraction: interaction)
			XCTAssertFalse(
				frames.isEmpty,
				"\(interaction) must yield non-empty frames from the Codex fixture"
			)
		}
	}

	func testFloatingInteractionFramesReuseCachedBackingImages() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for interaction in FloatingInteraction.allCases {
			let first = pet.floatingFrames(forInteraction: interaction)
			let second = pet.floatingFrames(forInteraction: interaction)
			XCTAssertEqual(first.count, second.count)
			for (a, b) in zip(first, second) {
				XCTAssertTrue(
					a.cgImage === b.cgImage,
					"\(interaction) floating frames must come from the load-time cache"
				)
			}
		}
	}

	func testInteractionFramesNotExposedViaActivityState() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		for activity in ActivityState.allCases {
			guard let spec = CodexPet.rowMap[activity] else { continue }
			XCTAssertFalse(
				[1, 2, 4].contains(spec.rowIndex),
				"ActivityState.\(activity) must not resolve to a reserved interaction row (got row \(spec.rowIndex))"
			)
			XCTAssertFalse(pet.frames(for: activity).isEmpty)
		}
	}

	// MARK: - Hide floating pet prompt (right-click pill)

	func testHidePromptTitleMatchesCodexLabel() {
		XCTAssertEqual(FloatingPetHidePrompt.title, "Hide pet")
	}

	func testHidePromptPreferredSizeFitsTitle() {
		let size = FloatingPetHidePrompt.preferredSize()
		XCTAssertGreaterThan(size.width, 70)
		XCTAssertGreaterThan(size.height, 24)
	}

	func testHidePanelPromptTitleForMinimalistBadge() {
		XCTAssertEqual(FloatingPetHidePrompt.panelTitle, "Hide panel")
	}

	func testHidePanelPromptPreferredSizeFitsTitle() {
		let size = FloatingPetHidePrompt.preferredSize(title: FloatingPetHidePrompt.panelTitle)
		XCTAssertGreaterThan(size.width, 70)
		XCTAssertGreaterThan(size.height, 24)
	}

	// MARK: - Force Idle escape-hatch gate

	func testOffersForceIdleForEveryNonIdleState() {
		for state in ActivityState.allCases where state != .idle {
			XCTAssertTrue(
				FloatingPetHidePrompt.offersForceIdle(for: state),
				"\(state.rawValue) should offer Force Idle")
		}
	}

	func testDoesNotOfferForceIdleWhenIdle() {
		// The idle "set" (idle / impatient / frustrated) all share the .idle wire
		// state, so this single check suppresses Force Idle for all three.
		XCTAssertFalse(FloatingPetHidePrompt.offersForceIdle(for: .idle))
	}

	func testForceIdlePromptTitle() {
		XCTAssertEqual(FloatingPetHidePrompt.forceIdleTitle, "Force Idle")
	}

	// MARK: - Mode-switch affordances (Pet Mode ↔ Minimalist Mode)

	func testMinimalistModePromptTitle() {
		XCTAssertEqual(FloatingPetHidePrompt.minimalistModeTitle, "Minimalist Mode")
	}

	func testPetModePromptTitle() {
		XCTAssertEqual(FloatingPetHidePrompt.petModeTitle, "Pet Mode")
	}

	func testModeSwitchPromptPreferredSizesFitTitles() {
		for title in [FloatingPetHidePrompt.minimalistModeTitle, FloatingPetHidePrompt.petModeTitle] {
			let size = FloatingPetHidePrompt.preferredSize(title: title)
			XCTAssertGreaterThan(size.width, 70, "\(title) pill must fit its label")
			XCTAssertGreaterThan(size.height, 24)
		}
	}

	func testStackSizeWithModeSwitchRowFitsItsWiderTitle() {
		// "Minimalist Mode" is the widest title the Own-mode prompt can stack;
		// the stack must widen to fit it, not clip to "Hide pet"'s width.
		let titles = [FloatingPetHidePrompt.minimalistModeTitle, FloatingPetHidePrompt.title]
		let stacked = FloatingPetHidePrompt.stackSize(titles: titles)
		let widest = titles
			.map { FloatingPetHidePrompt.preferredSize(title: $0).width }
			.max() ?? 0
		XCTAssertEqual(stacked.width, widest, accuracy: 0.5)
		XCTAssertGreaterThan(
			FloatingPetHidePrompt.preferredSize(title: FloatingPetHidePrompt.minimalistModeTitle).width,
			FloatingPetHidePrompt.preferredSize(title: FloatingPetHidePrompt.title).width,
			"sanity: the mode-switch title is the row driving the stack width")
	}

	// MARK: - Panel Size pill

	func testPanelSizePromptTitleUsesEllipsisConvention() {
		// Ellipsis marks "opens follow-up UI", matching "Rename…".
		XCTAssertEqual(FloatingPetHidePrompt.panelSizeTitle, "Panel Size…")
	}

	func testPanelSizePillSliderRangeMatchesCustomizationSlider() {
		// The pill and the Customization tab's slider drive the same global
		// minimalist_badge_scale, so their ranges must never drift apart.
		XCTAssertEqual(MinimalistPanelSizePill.minScale, Double(GateBadgeLayout.achievableMinScale))
		XCTAssertEqual(MinimalistPanelSizePill.maxScale, Double(GateBadgeLayout.achievableMaxScale))
	}

	func testStackSizeSingleTitleMatchesPreferredSize() {
		let single = FloatingPetHidePrompt.preferredSize(title: FloatingPetHidePrompt.title)
		let stacked = FloatingPetHidePrompt.stackSize(titles: [FloatingPetHidePrompt.title])
		XCTAssertEqual(stacked.width, single.width, accuracy: 0.5)
		XCTAssertEqual(stacked.height, single.height, accuracy: 0.5)
	}

	func testStackSizeTwoRowsIsTallerAndFitsWidestTitle() {
		let titles = [FloatingPetHidePrompt.forceIdleTitle, FloatingPetHidePrompt.title]
		let rowHeight = FloatingPetHidePrompt.preferredSize().height
		let stacked = FloatingPetHidePrompt.stackSize(titles: titles)
		// Two rows plus one inter-row gap.
		XCTAssertEqual(
			stacked.height,
			rowHeight * 2 + FloatingPetHidePrompt.rowSpacing,
			accuracy: 0.5)
		let widest = titles
			.map { FloatingPetHidePrompt.preferredSize(title: $0).width }
			.max() ?? 0
		XCTAssertEqual(stacked.width, widest, accuracy: 0.5)
	}

	// MARK: - Stacked-row layout geometry

	func testRowFrameTopRowPinnedToTopEdge() {
		let panelSize = FloatingPetHidePrompt.stackSize(
			titles: [FloatingPetHidePrompt.forceIdleTitle, FloatingPetHidePrompt.title])
		let top = FloatingPetHidePrompt.rowFrame(index: 0, count: 2, panelSize: panelSize)
		XCTAssertEqual(top.maxY, panelSize.height, accuracy: 0.5,
			"the first row (Force Idle) must sit flush against the top edge of the panel")
		XCTAssertGreaterThan(top.minY, 0,
			"the top row must not start at the bottom — a non-zero origin is exactly what the hitTest bug tripped on")
	}

	func testRowFrameBottomRowPinnedToBottomEdge() {
		let panelSize = FloatingPetHidePrompt.stackSize(
			titles: [FloatingPetHidePrompt.forceIdleTitle, FloatingPetHidePrompt.title])
		let bottom = FloatingPetHidePrompt.rowFrame(index: 1, count: 2, panelSize: panelSize)
		XCTAssertEqual(bottom.minY, 0, accuracy: 0.5,
			"the last row (Hide) must sit flush against the bottom edge")
	}

	func testRowFramesDoNotOverlapAndLeaveSpacingGap() {
		let panelSize = FloatingPetHidePrompt.stackSize(
			titles: [FloatingPetHidePrompt.forceIdleTitle, FloatingPetHidePrompt.title])
		let top = FloatingPetHidePrompt.rowFrame(index: 0, count: 2, panelSize: panelSize)
		let bottom = FloatingPetHidePrompt.rowFrame(index: 1, count: 2, panelSize: panelSize)
		XCTAssertEqual(
			top.minY - bottom.maxY,
			FloatingPetHidePrompt.rowSpacing,
			accuracy: 0.5,
			"rows must be separated by exactly rowSpacing with no overlap")
	}

	// MARK: - Shared prompt item builder (P17.02)
	//
	// Table-driven against `docs/contracts/window-capability-matrix.md` §1:
	// per-shape differences are expressed only as `FloatingPetPromptCapabilities`
	// fields (never a shape-identity boolean), and Combined is not a distinct
	// row here — it inherits whichever shape's capabilities it is routed
	// through, so only Own and Minimalist rows are exercised.

	private func noopPromptHandlers() -> FloatingPetPromptHandlers {
		FloatingPetPromptHandlers(
			forceIdle: {}, rename: {}, syncLabel: {}, prune: {},
			modeSwitch: {}, panelSize: {}, hideAllOtherPets: {}, hideThis: {}
		)
	}

	private func ownPromptCapabilities(
		offersForceIdle: Bool = false,
		sessionLabel: String? = nil,
		hasActiveSession: Bool = false
	) -> FloatingPetPromptCapabilities {
		FloatingPetPromptCapabilities(
			offersForceIdle: offersForceIdle,
			sessionLabel: sessionLabel,
			hasActiveSession: hasActiveSession,
			modeSwitchTitle: FloatingPetHidePrompt.minimalistModeTitle,
			offersPanelSize: false,
			hideItemTitle: FloatingPetHidePrompt.title
		)
	}

	private func minimalistPromptCapabilities(
		offersForceIdle: Bool = false,
		sessionLabel: String? = nil,
		hasActiveSession: Bool = false
	) -> FloatingPetPromptCapabilities {
		FloatingPetPromptCapabilities(
			offersForceIdle: offersForceIdle,
			sessionLabel: sessionLabel,
			hasActiveSession: hasActiveSession,
			modeSwitchTitle: FloatingPetHidePrompt.petModeTitle,
			offersPanelSize: true,
			hideItemTitle: FloatingPetHidePrompt.panelTitle
		)
	}

	func testOwnBuilderMinimalCapabilitiesProducesUnconditionalItemsOnly() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: ownPromptCapabilities(), handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.minimalistModeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.title,
		])
	}

	func testOwnBuilderOffersForceIdleFirst() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: ownPromptCapabilities(offersForceIdle: true), handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.forceIdleTitle,
			FloatingPetHidePrompt.minimalistModeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.title,
		])
	}

	func testOwnBuilderPlainOriginLabelOffersRenameOnly() {
		// R1.4/R1.5: a labeled-but-not-session-keyed window (plain-origin or
		// combined) offers Rename but not Sync Label / Prune.
		let items = FloatingPetPromptBuilder.items(
			capabilities: ownPromptCapabilities(sessionLabel: "codex"), handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.renameTitle,
			FloatingPetHidePrompt.minimalistModeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.title,
		])
	}

	func testOwnBuilderSessionKeyedOffersRenameSyncLabelAndPrune() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: ownPromptCapabilities(sessionLabel: "Session 3", hasActiveSession: true),
			handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.renameTitle,
			FloatingPetHidePrompt.syncLabelTitle,
			FloatingPetHidePrompt.pruneTitle,
			FloatingPetHidePrompt.minimalistModeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.title,
		])
	}

	func testOwnBuilderNeverOffersPanelSize() {
		// R1.7: Own has no analogous size concept.
		let items = FloatingPetPromptBuilder.items(
			capabilities: ownPromptCapabilities(
				offersForceIdle: true, sessionLabel: "x", hasActiveSession: true),
			handlers: noopPromptHandlers())
		XCTAssertFalse(items.map(\.title).contains(FloatingPetHidePrompt.panelSizeTitle))
	}

	func testMinimalistBuilderMinimalCapabilitiesIncludesUnconditionalPanelSize() {
		// R1.7: Minimalist offers Panel Size… unconditionally.
		let items = FloatingPetPromptBuilder.items(
			capabilities: minimalistPromptCapabilities(), handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.petModeTitle,
			FloatingPetHidePrompt.panelSizeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.panelTitle,
		])
	}

	func testMinimalistBuilderOffersForceIdleFirst() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: minimalistPromptCapabilities(offersForceIdle: true),
			handlers: noopPromptHandlers())
		XCTAssertEqual(items.first?.title, FloatingPetHidePrompt.forceIdleTitle)
	}

	func testMinimalistBuilderSessionKeyedOffersRenameSyncLabelAndPrune() {
		let items = FloatingPetPromptBuilder.items(
			capabilities: minimalistPromptCapabilities(sessionLabel: "Session 2", hasActiveSession: true),
			handlers: noopPromptHandlers())
		XCTAssertEqual(items.map(\.title), [
			FloatingPetHidePrompt.renameTitle,
			FloatingPetHidePrompt.syncLabelTitle,
			FloatingPetHidePrompt.pruneTitle,
			FloatingPetHidePrompt.petModeTitle,
			FloatingPetHidePrompt.panelSizeTitle,
			FloatingPetHidePrompt.hideAllOtherPetsTitle,
			FloatingPetHidePrompt.panelTitle,
		])
	}

	func testMinimalistBuilderUsesHidePanelTitleNotHidePet() {
		// R1.9: cosmetic title-only difference; same last-item semantics.
		let items = FloatingPetPromptBuilder.items(
			capabilities: minimalistPromptCapabilities(), handlers: noopPromptHandlers())
		XCTAssertEqual(items.last?.title, FloatingPetHidePrompt.panelTitle)
		XCTAssertFalse(items.map(\.title).contains(FloatingPetHidePrompt.title))
	}

	func testBuilderActivatingEachItemInvokesOnlyItsOwnHandlerInOrder() {
		var fired: [String] = []
		let handlers = FloatingPetPromptHandlers(
			forceIdle: { fired.append("forceIdle") },
			rename: { fired.append("rename") },
			syncLabel: { fired.append("syncLabel") },
			prune: { fired.append("prune") },
			modeSwitch: { fired.append("modeSwitch") },
			panelSize: { fired.append("panelSize") },
			hideAllOtherPets: { fired.append("hideAllOtherPets") },
			hideThis: { fired.append("hideThis") }
		)
		let items = FloatingPetPromptBuilder.items(
			capabilities: minimalistPromptCapabilities(
				offersForceIdle: true, sessionLabel: "x", hasActiveSession: true),
			handlers: handlers)
		for item in items { item.onActivate() }
		XCTAssertEqual(fired, [
			"forceIdle", "rename", "syncLabel", "prune", "modeSwitch", "panelSize", "hideAllOtherPets",
			"hideThis",
		])
	}

	// MARK: - Prompt coordinator (single active prompt across panels)

	func testCoordinatorDismissesOtherOwnerWhenPresentingElsewhere() {
		let coordinator = FloatingPetPromptCoordinator()
		let ownerA = NSObject()
		let ownerB = NSObject()
		var dismissedA = false

		coordinator.willPresent(owner: ownerA) { dismissedA = true }
		XCTAssertFalse(dismissedA, "presenting A must not immediately dismiss A")

		coordinator.willPresent(owner: ownerB) { }
		XCTAssertTrue(
			dismissedA,
			"presenting on a different owner (right-clicking a different panel) must dismiss the previously active owner's prompt")
	}

	func testCoordinatorRepresentingSameOwnerDoesNotSelfDismiss() {
		let coordinator = FloatingPetPromptCoordinator()
		let owner = NSObject()
		var dismissCount = 0

		coordinator.willPresent(owner: owner) { dismissCount += 1 }
		coordinator.willPresent(owner: owner) { dismissCount += 1 }

		XCTAssertEqual(
			dismissCount, 0,
			"re-presenting on the same owner (double right-click on one panel) must not fire either dismiss closure")
	}

	func testCoordinatorDidDismissFromNonActiveOwnerIsNoOp() {
		let coordinator = FloatingPetPromptCoordinator()
		let ownerA = NSObject()
		let ownerB = NSObject()
		var dismissedB = false

		coordinator.willPresent(owner: ownerB) { dismissedB = true }
		// ownerA was never registered active; its dismiss must not clear B's state.
		coordinator.didDismiss(owner: ownerA)

		coordinator.willPresent(owner: NSObject()) { }
		XCTAssertTrue(
			dismissedB,
			"an unrelated owner's didDismiss must not clear a different owner's active registration")
	}

	func testCoordinatorDidDismissClearsActiveOwnerSoNextPresentDoesNotRefire() {
		let coordinator = FloatingPetPromptCoordinator()
		let owner = NSObject()
		var dismissCount = 0

		coordinator.willPresent(owner: owner) { dismissCount += 1 }
		coordinator.didDismiss(owner: owner)

		coordinator.willPresent(owner: NSObject()) { }
		XCTAssertEqual(
			dismissCount, 0,
			"once an owner's own dismiss has run, the coordinator must not invoke its stale dismiss closure again")
	}

	func testHidePromptFrameAnchorsTopLeftAtClick() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let anchor = CGPoint(x: 48, y: 120)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: anchor,
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertEqual(frame.minX, anchor.x, accuracy: 0.5)
		XCTAssertEqual(frame.maxY, anchor.y, accuracy: 0.5)
		XCTAssertTrue(bounds.contains(frame))
	}

	func testHidePromptFrameKeepsTopLeftAnchorWhenExtendingPastRightEdge() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let anchor = CGPoint(x: 170, y: 120)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: anchor,
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertEqual(frame.minX, anchor.x, accuracy: 0.5)
		XCTAssertEqual(frame.maxY, anchor.y, accuracy: 0.5)
		XCTAssertGreaterThan(frame.maxX, bounds.maxX)
	}

	func testHidePromptFrameClampsTopLeftWhenAgainstLeftEdge() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		let promptSize = FloatingPetHidePrompt.preferredSize()
		let frame = FloatingPetHidePrompt.frame(
			anchor: CGPoint(x: 2, y: 120),
			promptSize: promptSize,
			in: bounds
		)
		XCTAssertGreaterThanOrEqual(frame.minX, 4)
		XCTAssertTrue(bounds.contains(frame))
	}

	func testHidePromptShouldNotPresentDuringActivePointerInteraction() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		XCTAssertFalse(
			FloatingPetHidePrompt.shouldPresent(
				at: CGPoint(x: 100, y: 80),
				in: bounds,
				hasActivePointerInteraction: true
			)
		)
	}

	func testHidePromptShouldPresentInsideBoundsWhenIdle() {
		let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
		XCTAssertTrue(
			FloatingPetHidePrompt.shouldPresent(
				at: CGPoint(x: 100, y: 80),
				in: bounds,
				hasActivePointerInteraction: false
			)
		)
	}

	// MARK: - FloatingPetScene interaction overlay

	func testSettingInteractionRunningRightSwapsFrames() throws {
		let pet = try CodexPet(petDirectory: maliFixtureDirectory())
		let scene = try makeScene(codexPet: pet)
		scene.update(state: .idle, visualMode: .normal)
		let idleFirstFrame = try XCTUnwrap(pet.frames(for: .idle).first?.image.tiffRepresentation)

		scene.setInteraction(.runningRight)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
		let interactionFirstFrame = try XCTUnwrap(scene.currentFramesForTesting.first?.tiffRepresentation)
		XCTAssertNotEqual(
			interactionFirstFrame, idleFirstFrame,
			"running-right interaction frames must come from a different Codex row than .idle"
		)
		XCTAssertEqual(scene.currentFrameIndexForTesting, 0)
	}

	func testSettingInteractionRunningLeftSwapsFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.runningLeft)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningLeft)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
	}

	func testSettingInteractionJumpingSwapsFrames() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.jumping)

		XCTAssertEqual(scene.currentInteractionForTesting, .jumping)
		XCTAssertFalse(scene.currentFramesForTesting.isEmpty)
	}

	func testMissingInteractionFramesFallBackToActivityFrames() throws {
		let scene = try makeScene(interactionFramesProvider: { _ in [] })
		scene.update(state: .implementing, visualMode: .normal)
		let activityFrameCount = scene.currentFramesForTesting.count
		XCTAssertGreaterThan(activityFrameCount, 0)

		scene.setInteraction(.runningRight)

		XCTAssertNil(
			scene.currentInteractionForTesting,
			"missing reserved-row frames must drop the interaction back to nil so activity frames remain authoritative"
		)
		XCTAssertEqual(
			scene.currentFramesForTesting.count, activityFrameCount,
			"missing reserved rows must fall back to the current activity-state frame loop"
		)
	}

	func testClearingInteractionRestoresActivityFrames() throws {
		let scene = try makeScene()
		scene.update(state: .implementing, visualMode: .normal)
		let activityFrameCount = scene.currentFramesForTesting.count

		scene.setInteraction(.runningRight)
		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)

		scene.setInteraction(nil)

		XCTAssertNil(scene.currentInteractionForTesting)
		XCTAssertEqual(
			scene.currentFramesForTesting.count, activityFrameCount,
			"ending interaction must restore the ordinary activity-state animation"
		)
	}

	func testActivityStateUpdateWhileInteractingDefersUntilCleared() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)

		scene.setInteraction(.runningRight)
		let interactionFrameCount = scene.currentFramesForTesting.count

		// While an interaction is active, an incoming activity-state change must
		// not interrupt the interaction's frame loop — interaction wins for the
		// duration the user is manipulating the pet.
		scene.update(state: .implementing, visualMode: .normal)
		XCTAssertEqual(scene.currentFramesForTesting.count, interactionFrameCount)
		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)

		// On clear, the latest activity-state frames take over.
		scene.setInteraction(nil)
		XCTAssertEqual(scene.currentStateForTesting, .implementing)
		XCTAssertGreaterThan(scene.currentFramesForTesting.count, 0)
	}

	// MARK: - Interaction direction policy

	func testRightwardStepSelectsRunningRight() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningRight)
	}

	func testLeftwardStepSelectsRunningLeft() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: -12, height: 0),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(interaction, .runningLeft)
	}

	func testVerticalStepWithNoPreviousRunningHasNoInteraction() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 0, height: 30),
			hitTarget: .dragRegion
		)
		XCTAssertNil(
			interaction,
			"vertical-only step with no prior running interaction stays nil"
		)
	}

	func testVerticalStepHoldsPreviousRunningDirection() {
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 0, height: 8),
				hitTarget: .dragRegion,
				previous: .runningLeft
			),
			.runningLeft
		)
	}

	func testVerticalStepHoldsJumpingDuringTranslate() {
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 0, height: 8),
				hitTarget: .dragRegion,
				previous: .jumping
			),
			.jumping,
			"first drag ticks are often vertical-only; must not clear click jumping"
		)
	}

	func testDraggedFrameKeepsGrabPointUnderCursor() {
		let grabOffset = CGPoint(x: 40, y: 30)
		let windowSize = CGSize(width: 160, height: 160)
		let mouse = CGPoint(x: 500, y: 400)
		let visible = CGRect(x: 0, y: 0, width: 2000, height: 2000)
		let frame = FloatingInteractionPolicy.draggedFrame(
			mouseLocationInScreen: mouse,
			grabOffsetInScreen: grabOffset,
			windowSize: windowSize,
			visibleFrame: visible
		)
		XCTAssertEqual(frame.origin.x, mouse.x - grabOffset.x, accuracy: 0.001)
		XCTAssertEqual(frame.origin.y, mouse.y - grabOffset.y, accuracy: 0.001)
		XCTAssertEqual(frame.size, windowSize)
	}

	func testStepReversalFlipsRunningWithoutCumulativeUndo() {
		// Cumulative delta from mouseDown would still be leftward after a small
		// rightward reversal; per-event step must flip immediately.
		XCTAssertEqual(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 4, height: 0),
				hitTarget: .dragRegion,
				previous: .runningLeft
			),
			.runningRight
		)
	}

	func testDiagonalStepWithHorizontalComponentSelectsRunning() {
		let interaction = FloatingInteractionPolicy.interaction(
			forStepDelta: CGSize(width: 12, height: 30),
			hitTarget: .dragRegion
		)
		XCTAssertEqual(
			interaction, .runningRight,
			"any non-zero horizontal step selects a running row"
		)
	}

	func testClickOnDragRegionSelectsJumping() {
		XCTAssertEqual(
			FloatingInteractionPolicy.clickInteraction(hitTarget: .dragRegion),
			.jumping
		)
	}

	func testClickOnResizeAffordanceHasNoInteraction() {
		XCTAssertNil(
			FloatingInteractionPolicy.clickInteraction(hitTarget: .resizeAffordance)
		)
	}

	func testResizeAffordanceHasNoInteraction() {
		// Resizing must not animate the pet: dragging the affordance clears any
		// interaction so the activity-state animation already playing stays put,
		// regardless of drag direction or the previous interaction.
		XCTAssertNil(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 12, height: 12),
				hitTarget: .resizeAffordance
			)
		)
		XCTAssertNil(
			FloatingInteractionPolicy.interaction(
				forStepDelta: CGSize(width: 0, height: 8),
				hitTarget: .resizeAffordance,
				previous: .jumping
			)
		)
	}

	func testJumpingToRunningPreservesFrameIndex() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		scene.setInteraction(.jumping)
		for _ in 0 ..< 2 {
			scene.advanceFrameForTesting()
		}
		let indexBefore = scene.currentFrameIndexForTesting
		XCTAssertGreaterThan(indexBefore, 0)

		scene.setInteraction(.runningRight)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningRight)
		XCTAssertEqual(
			scene.currentFrameIndexForTesting, indexBefore % 8,
			"jumping → running must not reset the frame cycle on drag start"
		)
	}

	func testRunningDirectionFlipPreservesFrameIndex() throws {
		let scene = try makeScene()
		scene.update(state: .idle, visualMode: .normal)
		scene.setInteraction(.runningRight)
		for _ in 0 ..< 3 {
			scene.advanceFrameForTesting()
		}
		let indexBeforeFlip = scene.currentFrameIndexForTesting
		XCTAssertGreaterThan(indexBeforeFlip, 0)

		scene.setInteraction(.runningLeft)

		XCTAssertEqual(scene.currentInteractionForTesting, .runningLeft)
		XCTAssertEqual(
			scene.currentFrameIndexForTesting, indexBeforeFlip,
			"running-left ↔ running-right must not reset the frame cycle"
		)
	}
}

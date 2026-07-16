import AppKit
import XCTest

@testable import Codogotchi

/// Layout-invariant guard for the Pet tab card grid. Rather than compare golden
/// pixels (brittle across OS/font/appearance), it builds the real Settings
/// window, selects the Pet tab, and asserts the structural promises of the
/// redesigned card: a fixed-size thumbnail pinned to the top, the first action
/// button in the upper portion of the card, and a multi-line description.
///
/// Cards and their description labels are located by the identifiers
/// `PetTabView` stamps on them (`"petCard"` / `"petCardDescription"`).
@MainActor
final class PetTabLayoutTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("PetTabLayoutTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		for window in NSApp.windows
		where window.title == SettingsWindowController.windowTitle {
			window.close()
		}
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	private func makePet(_ id: String, in root: URL, description: String) {
		let dir = root.appendingPathComponent(id)
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let json: [String: String] = [
			"id": id, "displayName": id, "description": description,
			"spritesheetPath": "spritesheet.webp",
		]
		let data = try! JSONSerialization.data(withJSONObject: json)
		try! data.write(to: dir.appendingPathComponent("pet.json"))
		try! Data("fakewebp".utf8).write(to: dir.appendingPathComponent("spritesheet.webp"))
	}

	private func views(in root: NSView, identifier: String) -> [NSView] {
		var found: [NSView] = []
		if root.identifier?.rawValue == identifier { found.append(root) }
		for sub in root.subviews { found.append(contentsOf: views(in: sub, identifier: identifier)) }
		return found
	}

	private func firstSubview<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
		for sub in root.subviews {
			if let match = sub as? T { return match }
			if let nested = firstSubview(type, in: sub) { return nested }
		}
		return nil
	}

	func testPetCardLayoutInvariants() {
		let codexRoot = tmp.appendingPathComponent("codex/pets")
		let canonicalRoot = tmp.appendingPathComponent("codogotchi/pets")
		try! FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
		try! FileManager.default.createDirectory(
			at: canonicalRoot, withIntermediateDirectories: true)
		let longDescription =
			"A compact Codex digital pet inspired by a long-winded backstory that "
			+ "wraps across several lines so the description box has to grow taller."
		// Bundled maew is always present in the catalog; seed it so every card
		// has a real description to assert against.
		makePet(DEFAULT_PET_NAME, in: canonicalRoot, description: longDescription)
		makePet("felix", in: canonicalRoot, description: longDescription)
		makePet("zeta", in: codexRoot, description: longDescription)

		let vm = PetTabViewModel(
			codexPetsRoot: codexRoot,
			canonicalPetsRoot: canonicalRoot,
			configURL: tmp.appendingPathComponent("config.json"),
			assignmentsURL: tmp.appendingPathComponent("assignments.json")
		)
		let controller = SettingsWindowController(petTabViewModel: vm)
		controller.show()

		guard
			let window = NSApp.windows.last(where: {
				$0.title == SettingsWindowController.windowTitle
			})
		else { return XCTFail("settings window not found") }
		window.setContentSize(NSSize(width: 1040, height: 760))

		func findTabView(_ v: NSView) -> NSTabView? {
			if let t = v as? NSTabView { return t }
			for s in v.subviews { if let f = findTabView(s) { return f } }
			return nil
		}
		guard let content = window.contentView, let tabView = findTabView(content) else {
			return XCTFail("tab view not found")
		}
		tabView.selectTabViewItem(at: 1)  // Pet
		content.layoutSubtreeIfNeeded()

		let cards = views(in: content, identifier: "petCard")
		XCTAssertEqual(cards.count, 3, "one card per pet (maew, felix, zeta)")

		let feedbackLabels = views(in: content, identifier: "petTabFeedback")
		XCTAssertEqual(feedbackLabels.count, 1, "Pet tab should expose one inline feedback label")
		if let feedback = feedbackLabels.first as? NSTextField {
			XCTAssertTrue(feedback.isHidden, "feedback starts hidden until an action reports status")
			XCTAssertEqual(feedback.stringValue, "")
		}

		for card in cards {
			guard let thumb = firstSubview(NSImageView.self, in: card) else {
				return XCTFail("card missing thumbnail")
			}
			guard let button = firstSubview(NSButton.self, in: card) else {
				return XCTFail("card missing action button")
			}

			// Thumbnail is a fixed 64×64 tile.
			XCTAssertEqual(thumb.frame.width, 64, accuracy: 0.5)
			XCTAssertEqual(thumb.frame.height, 64, accuracy: 0.5)

			// Thumbnail is top-aligned: its top edge is within 20pt of the card top.
			// In non-flipped AppKit coords, visual top = bounds.height (maxY).
			let thumbTopGap = card.bounds.height - thumb.frame.maxY
			XCTAssertLessThan(thumbTopGap, 20, "thumbnail should be top-aligned in the card")

			// Convert to card coordinates — the assign button is nested inside nameRow.
			let buttonRectInCard: CGRect
			if let parent = button.superview {
				buttonRectInCard = card.convert(button.frame, from: parent)
			} else {
				buttonRectInCard = button.frame
			}

			// Assign button (installed pet, nested in name row) should be in the
			// upper half of the card. Import icon (importable pet, below thumbnail)
			// is intentionally in the lower visual area — only check it stays within
			// the card bounds.
			let isDirectSubview = button.superview === card
			if isDirectSubview {
				// Import icon button — must be visible within the card.
				XCTAssertTrue(
					card.bounds.intersects(buttonRectInCard),
					"import icon should be within card bounds")
			} else {
				// Assign button — lives in the name row at the top of the card.
				let cardMidY = card.bounds.midY
				XCTAssertGreaterThan(
					buttonRectInCard.midY, cardMidY,
					"assign button should be in the upper half of the card")
			}

			// Button sits inside the card's right edge (in card coordinates).
			XCTAssertLessThanOrEqual(buttonRectInCard.maxX, card.bounds.maxX)

			// Description wraps to more than one line for long text.
			let desc = views(in: card, identifier: "petCardDescription").first
			XCTAssertNotNil(desc, "card missing description label")
			XCTAssertGreaterThan(
				desc!.frame.height, 28,
				"long description should wrap to multiple lines")
		}
	}

	func testAssignmentChromeUpdatesBadgePillsWithoutGridRebuild() throws {
		let codexRoot = tmp.appendingPathComponent("codex/pets")
		let canonicalRoot = tmp.appendingPathComponent("codogotchi/pets")
		try! FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
		try! FileManager.default.createDirectory(
			at: canonicalRoot, withIntermediateDirectories: true)
		makePet("mew", in: canonicalRoot, description: "Chinese-inspired companion")
		makePet("meaw", in: canonicalRoot, description: "Thai-inspired companion")

		let assignmentsURL = tmp.appendingPathComponent("assignments.json")
		try AssignmentsJsonWriter.write(badge: "cursor", petId: "mew", to: assignmentsURL)
		let vm = PetTabViewModel(
			codexPetsRoot: codexRoot,
			canonicalPetsRoot: canonicalRoot,
			configURL: tmp.appendingPathComponent("config.json"),
			assignmentsURL: assignmentsURL
		)

		let petTab = PetTabView(viewModel: vm, onImportPet: { _ in })
		petTab.frame = NSRect(x: 0, y: 0, width: 980, height: 640)
		petTab.layoutSubtreeIfNeeded()

		func pills(forPetId id: String, in root: NSView) -> NSStackView? {
			let cards = views(in: root, identifier: "petCard")
			for card in cards {
				let names = views(in: card, identifier: "petCardDescription")
					.compactMap { $0 as? NSTextField }
					.map(\.stringValue)
				// Cards don't stamp pet id; match via description seed text.
				let match: Bool
				switch id {
				case "mew": match = names.contains(where: { $0.contains("Chinese") })
				case "meaw": match = names.contains(where: { $0.contains("Thai") })
				default: match = false
				}
				guard match else { continue }
				return views(in: card, identifier: "petCardBadgePills").first as? NSStackView
			}
			return nil
		}

		guard let mewPillsBefore = pills(forPetId: "mew", in: petTab),
			let meawPillsBefore = pills(forPetId: "meaw", in: petTab)
		else {
			return XCTFail("expected mew and meaw badge pill rows")
		}
		XCTAssertEqual(
			mewPillsBefore.arrangedSubviews.count, 1,
			"cursor assignment should seed one pill on mew")
		XCTAssertEqual(
			meawPillsBefore.arrangedSubviews.count, 0,
			"meaw starts with no platform pills")

		try vm.assign(badge: "cursor", to: "meaw")
		// Stale chrome until live refresh — documents the pre-fix lag.
		XCTAssertEqual(mewPillsBefore.arrangedSubviews.count, 1)
		XCTAssertEqual(meawPillsBefore.arrangedSubviews.count, 0)

		petTab.refreshAssignmentChrome()

		guard let mewPillsAfter = pills(forPetId: "mew", in: petTab),
			let meawPillsAfter = pills(forPetId: "meaw", in: petTab)
		else {
			return XCTFail("expected mew and meaw badge pill rows after refresh")
		}
		XCTAssertEqual(
			mewPillsAfter.arrangedSubviews.count, 0,
			"cursor logo must leave mew immediately after refresh")
		XCTAssertEqual(
			meawPillsAfter.arrangedSubviews.count, 1,
			"cursor logo must appear on meaw without dismissing an assign popover")
	}
}

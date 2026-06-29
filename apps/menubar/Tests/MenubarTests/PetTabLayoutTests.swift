import AppKit
import XCTest

@testable import Codogotchi

/// Layout-invariant guard for the Pet tab card grid. Rather than compare golden
/// pixels (brittle across OS/font/appearance), it builds the real Settings
/// window, selects the Pet tab, and asserts the structural promises of the
/// Codex-style card: a fixed-size thumbnail, the thumbnail and action button
/// vertically centered (the balanced row), and a multi-line description.
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
		let json: [String: String] = ["id": id, "displayName": id, "description": description]
		let data = try! JSONSerialization.data(withJSONObject: json)
		try! data.write(to: dir.appendingPathComponent("pet.json"))
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
			configURL: tmp.appendingPathComponent("config.json")
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

			// Thumbnail and button are vertically centered in the card — the
			// "balanced row" symmetry.
			let cardMidY = card.bounds.midY
			XCTAssertEqual(thumb.frame.midY, cardMidY, accuracy: 1.0)
			XCTAssertEqual(button.frame.midY, cardMidY, accuracy: 1.0)

			// Button sits inside the card's right edge.
			XCTAssertLessThanOrEqual(button.frame.maxX, card.bounds.maxX)

			// Description wraps to more than one line for long text.
			let desc = views(in: card, identifier: "petCardDescription").first
			XCTAssertNotNil(desc, "card missing description label")
			XCTAssertGreaterThan(
				desc!.frame.height, 28,
				"long description should wrap to multiple lines")
		}
	}
}

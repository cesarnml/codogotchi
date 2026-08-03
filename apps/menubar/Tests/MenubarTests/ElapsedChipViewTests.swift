import AppKit
import XCTest

@testable import Codogotchi

/// The two views that actually put the chip on screen. Neither had any coverage
/// when the idle clock was added, so the kind-switching and the deliberate
/// "no glyph until configured" initializer were both documented-but-unproven.
@MainActor
final class ElapsedChipViewTests: XCTestCase {
	private let metrics = GateBadgeLayout.metrics(scale: 1.0)

	/// `imageView` is private; reach it structurally rather than widening the
	/// production API for a test.
	private func glyphImage(in view: NSView) -> NSImage? {
		if let imageView = view as? NSImageView { return imageView.image }
		for subview in view.subviews {
			if let found = glyphImage(in: subview) { return found }
		}
		return nil
	}

	// MARK: - ElapsedGlyphView

	/// The initializer sets no symbol on purpose, so a chip can never flash the
	/// wrong glyph for a frame before its kind is known.
	func testGlyphIsEmptyUntilConfigured() {
		let glyph = ElapsedGlyphView(frame: .zero)

		XCTAssertNil(
			glyphImage(in: glyph),
			"the initializer must not pick a default symbol — kind is not known yet")
	}

	func testGlyphSwapsSymbolWithKind() {
		let glyph = ElapsedGlyphView(frame: .zero)

		glyph.configure(metrics: metrics, isRunning: true, kind: .turn)
		XCTAssertEqual(glyphImage(in: glyph)?.accessibilityDescription, "Prompt timer")

		glyph.configure(metrics: metrics, isRunning: true, kind: .idle)
		XCTAssertEqual(
			glyphImage(in: glyph)?.accessibilityDescription, "Idle timer",
			"switching kind must swap the glyph, not keep the previous symbol")
	}

	/// Pins the `guard kind != currentKind` short-circuit: a same-kind
	/// reconfigure must not rebuild the image. Inverting that guard would make
	/// every one-second tick allocate a fresh NSImage.
	func testSameKindReconfigureReusesTheImage() {
		let glyph = ElapsedGlyphView(frame: .zero)
		glyph.configure(metrics: metrics, isRunning: true, kind: .idle)
		let first = try? XCTUnwrap(glyphImage(in: glyph))

		glyph.configure(metrics: metrics, isRunning: false, kind: .idle)
		let second = glyphImage(in: glyph)

		XCTAssertTrue(first === second, "a same-kind reconfigure must not re-resolve the symbol")
	}

	/// A frozen clock dims; a running one does not. Shared by both kinds.
	func testGlyphDimsWhenNotRunning() {
		let glyph = ElapsedGlyphView(frame: .zero)

		glyph.configure(metrics: metrics, isRunning: true, kind: .turn)
		let running = glyph.subviews.compactMap { $0 as? NSImageView }.first?.alphaValue

		glyph.configure(metrics: metrics, isRunning: false, kind: .turn)
		let frozen = glyph.subviews.compactMap { $0 as? NSImageView }.first?.alphaValue

		XCTAssertEqual(running, 1.0)
		XCTAssertLessThan(try XCTUnwrap(frozen), try XCTUnwrap(running))
	}

	// MARK: - ElapsedChipView

	private func labelText(in view: NSView) -> String? {
		if let field = view as? NSTextField, !field.stringValue.isEmpty { return field.stringValue }
		for subview in view.subviews {
			if let found = labelText(in: subview) { return found }
		}
		return nil
	}

	func testChipRendersLabelAndGlyphForTheIdleKind() {
		let chip = ElapsedChipView(frame: .zero)

		chip.configure(
			presentation: ElapsedPresentation(label: "47:00", isRunning: true, kind: .idle),
			metrics: metrics)

		XCTAssertEqual(labelText(in: chip), "47:00")
		XCTAssertEqual(glyphImage(in: chip)?.accessibilityDescription, "Idle timer")
	}

	/// The same chip instance is reused across a turn ending and the session
	/// falling idle, so it must fully re-dress rather than keep the turn glyph.
	func testChipReDressesWhenTheKindChanges() {
		let chip = ElapsedChipView(frame: .zero)

		chip.configure(
			presentation: ElapsedPresentation(label: "0:12", isRunning: true, kind: .turn),
			metrics: metrics)
		XCTAssertEqual(glyphImage(in: chip)?.accessibilityDescription, "Prompt timer")

		chip.configure(
			presentation: ElapsedPresentation(label: "0:03", isRunning: true, kind: .idle),
			metrics: metrics)

		XCTAssertEqual(labelText(in: chip), "0:03")
		XCTAssertEqual(glyphImage(in: chip)?.accessibilityDescription, "Idle timer")
	}

	/// A longer label must claim more width — the idle clock routinely renders
	/// wider strings ("2h 15m") than a turn clock ever did.
	func testChipWidthGrowsWithLabelLength() {
		let chip = ElapsedChipView(frame: .zero)

		chip.configure(
			presentation: ElapsedPresentation(label: "0:07", isRunning: true, kind: .turn),
			metrics: metrics)
		let narrow = chip.intrinsicContentSize.width

		chip.configure(
			presentation: ElapsedPresentation(label: "2h 15m", isRunning: true, kind: .idle),
			metrics: metrics)

		XCTAssertGreaterThan(chip.intrinsicContentSize.width, narrow)
	}
}

import AppKit

final class FloatingPetHidePromptPanel: NSPanel {
	private var rowViews: [FloatingPetHidePromptView] = []

	init(frame: CGRect, items: [FloatingPetPromptItem]) {
		super.init(
			contentRect: frame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		// A right-click context menu must sit ABOVE the pet chrome (platform chip,
		// animation badge, attention bubble — all `.floating`). Those panels are
		// re-ordered front on every ~1s poll tick, which would otherwise bury this
		// prompt seconds after it appears, so left-clicks on "Force Idle" / "Hide"
		// landed on the buried-under chrome instead of the pill. `.popUpMenu`
		// (level 101 vs `.floating` = 3) keeps the prompt reliably on top.
		level = .popUpMenu
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true

		let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
		container.autoresizingMask = [.width, .height]
		// All rows share the same font/padding, so each is one preferred-height
		// tall. Lay them top-to-bottom (AppKit origin is bottom-left) so items[0]
		// renders at the top of the stack.
		for (index, item) in items.enumerated() {
			let rowFrame = FloatingPetHidePrompt.rowFrame(
				index: index,
				count: items.count,
				panelSize: frame.size
			)
			let row = FloatingPetHidePromptView(
				frame: rowFrame,
				title: item.title,
				onActivate: item.onActivate
			)
			container.addSubview(row)
			rowViews.append(row)
		}
		contentView = container
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}


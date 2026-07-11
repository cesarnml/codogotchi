import AppKit

final class ActionButton: NSButton {
	private let handler: () -> Void

	init(title: String, tint: NSColor, action: @escaping () -> Void) {
		self.handler = action
		super.init(frame: .zero)
		self.title = title
		translatesAutoresizingMaskIntoConstraints = false
		isBordered = false
		wantsLayer = true
		layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
		layer?.cornerRadius = 6
		font = .systemFont(ofSize: 11, weight: .semibold)
		contentTintColor = tint
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [.foregroundColor: tint, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)])
		target = self
		self.action = #selector(tapped)
		heightAnchor.constraint(equalToConstant: 22).isActive = true
		widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
	}

	/// Real horizontal padding. The 52pt min width alone only pads titles
	/// shorter than it ("Show", "Prune"); a longer title ("Prune All
	/// Archived") would otherwise render its text flush with the pill edges.
	override var intrinsicContentSize: NSSize {
		var size = super.intrinsicContentSize
		size.width += 20
		return size
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	@objc private func tapped() { handler() }
}


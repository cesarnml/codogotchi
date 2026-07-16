import AppKit

final class RPGMiniXPBadgeView: NSView {
	override init(frame: NSRect) {
		super.init(frame: frame)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 17
		layer?.borderWidth = 4
		layer?.borderColor = NSColor.systemGreen.cgColor
		let label = NSTextField(labelWithString: "XP")
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: 11, weight: .heavy)
		label.textColor = .white
		addSubview(label)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 34),
			heightAnchor.constraint(equalToConstant: 34),
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

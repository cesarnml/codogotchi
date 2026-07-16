import AppKit

final class RPGHUDIconTileView: NSView {
	init(icon: NSView) {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
		layer?.borderWidth = 1
		layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
		icon.translatesAutoresizingMaskIntoConstraints = false
		addSubview(icon)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 54),
			heightAnchor.constraint(equalToConstant: 54),
			icon.centerXAnchor.constraint(equalTo: centerXAnchor),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

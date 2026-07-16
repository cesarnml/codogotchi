import AppKit

final class RPGProgressBarView: NSView {
	private let fill = NSView()
	private let fraction: Double

	init(fraction: Double) {
		self.fraction = fraction.isFinite ? max(0, min(1, fraction)) : 0
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 5
		layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
		fill.translatesAutoresizingMaskIntoConstraints = false
		fill.wantsLayer = true
		fill.layer?.cornerRadius = 5
		fill.layer?.backgroundColor = NSColor.systemYellow.cgColor
		addSubview(fill)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 10),
			fill.leadingAnchor.constraint(equalTo: leadingAnchor),
			fill.topAnchor.constraint(equalTo: topAnchor),
			fill.bottomAnchor.constraint(equalTo: bottomAnchor),
			fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: self.fraction),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

import AppKit

final class RPGHeartStripView: NSView {
	private let hearts: [HeartState]
	private let heartSize: CGFloat
	private let spacing: CGFloat = 6

	init(hearts: [HeartState], heartSize: CGFloat) {
		self.hearts = hearts
		self.heartSize = heartSize
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		let stack = NSStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .horizontal
		stack.spacing = spacing
		addSubview(stack)
		for state in hearts {
			let heart = RPGHeartView(frame: .zero)
			heart.translatesAutoresizingMaskIntoConstraints = false
			heart.setState(state)
			stack.addArrangedSubview(heart)
			NSLayoutConstraint.activate([
				heart.widthAnchor.constraint(equalToConstant: heartSize),
				heart.heightAnchor.constraint(equalToConstant: heartSize),
			])
		}
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	override var intrinsicContentSize: NSSize {
		let count = CGFloat(hearts.count)
		let width = count * heartSize + max(0, count - 1) * spacing
		return NSSize(width: width, height: heartSize)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}


import AppKit

final class RPGHUDPreviewView: NSView {
	private let hearts: RPGHeartStripView
	private let ring = RPGRingView(frame: .zero)
	private let petView = NSImageView()
	private let fallbackLabel = settingsBodyLabel("Default pet preview unavailable")
	private let ringFraction: Double
	private let level: Int

	init(viewModel: RPGTabViewModel) {
		self.hearts = RPGHeartStripView(hearts: viewModel.hearts, heartSize: 24)
		self.ringFraction = viewModel.ringFraction
		self.level = viewModel.level
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.borderWidth = 1
		layer?.borderColor = SettingsTheme.cardBorder.cgColor
		layer?.backgroundColor = SettingsTheme.windowBackground.withAlphaComponent(0.55).cgColor

		for view in [hearts, ring, petView, fallbackLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		petView.image = viewModel.petImage
		petView.imageScaling = .scaleProportionallyUpOrDown
		fallbackLabel.alignment = .center
		fallbackLabel.isHidden = viewModel.petImage != nil
		ring.configure(fraction: ringFraction, level: level, ringDiameter: 96)

		// Geometry is tuned against the 320pt preview panel (see RPGTabView's
		// column constraints): the HUD column (hearts + ring) sits compact on
		// the left, and the pet takes the reclaimed space — pinned to the
		// preview's vertical bounds rather than a fixed height so it always
		// renders as large as the panel allows without overflowing it.
		NSLayoutConstraint.activate([
			hearts.topAnchor.constraint(equalTo: topAnchor, constant: 32),
			hearts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
			hearts.widthAnchor.constraint(equalToConstant: 90),
			hearts.heightAnchor.constraint(equalToConstant: 28),

			ring.topAnchor.constraint(equalTo: hearts.bottomAnchor, constant: 18),
			ring.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 46),
			ring.widthAnchor.constraint(equalToConstant: 96),
			ring.heightAnchor.constraint(equalToConstant: 96),

			petView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
			petView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
			petView.leadingAnchor.constraint(equalTo: ring.trailingAnchor, constant: 36),
			petView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
			petView.widthAnchor.constraint(equalToConstant: 210),

			fallbackLabel.centerXAnchor.constraint(equalTo: petView.centerXAnchor),
			fallbackLabel.centerYAnchor.constraint(equalTo: petView.centerYAnchor),
			fallbackLabel.widthAnchor.constraint(lessThanOrEqualTo: petView.widthAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }
}

import AppKit

// MARK: - DynamicStatusPanelView

/// Single status/feedback panel for the Hooks section. Shows the current
/// registration state by default (up to date, or an attention message when
/// stale/a new tool was detected) and temporarily reflects the result of an
/// install/update/remove action while one is in flight or just completed.
/// Replaces the old always-hidden-unless-stale `UpdateBannerView` plus a
/// separate plain-text feedback label with one view, one state.
final class DynamicStatusPanelView: NSView {
	enum State: Equatable {
		case upToDate
		case attention(String)
		case working(String)
		case success(String)
		case error(String)
	}

	var state: State = .upToDate {
		didSet {
			guard state != oldValue else { return }
			render()
		}
	}

	private let iconView = NSImageView()
	private let spinner = NSProgressIndicator()
	private let headlineLabel = NSTextField(labelWithString: "")
	private let subtextLabel = NSTextField(labelWithString: "")

	init() {
		super.init(frame: .zero)
		setupViews()
		render()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func setupViews() {
		wantsLayer = true
		layer?.cornerRadius = 6

		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.imageScaling = .scaleProportionallyUpOrDown
		addSubview(iconView)

		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.isDisplayedWhenStopped = false
		spinner.translatesAutoresizingMaskIntoConstraints = false
		addSubview(spinner)

		headlineLabel.font = .systemFont(ofSize: 12, weight: .semibold)
		headlineLabel.lineBreakMode = .byWordWrapping

		subtextLabel.font = .systemFont(ofSize: 11)
		subtextLabel.textColor = .secondaryLabelColor
		subtextLabel.lineBreakMode = .byWordWrapping

		// Headline + optional subtext live in one stack centered on the panel's
		// vertical axis, so single-line states (attention/success/error, which
		// hide the subtext) align with the icon instead of hugging the top edge.
		let textStack = NSStackView(views: [headlineLabel, subtextLabel])
		textStack.orientation = .vertical
		textStack.alignment = .leading
		textStack.spacing = 2
		textStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(textStack)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 26),
			iconView.heightAnchor.constraint(equalToConstant: 26),

			spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
			spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
			textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
			textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
		])
	}

	private func render() {
		let symbolName: String?
		let tint: NSColor
		let headline: String
		let subtext: String?

		switch state {
		case .upToDate:
			symbolName = "checkmark.circle"
			tint = .secondaryLabelColor
			headline = "Hooks are up to date"
			subtext = "All supported tools are registered and ready."
		case .attention(let message):
			symbolName = "exclamationmark.triangle.fill"
			tint = .systemYellow
			headline = message
			subtext = nil
		case .working(let message):
			symbolName = nil
			tint = .secondaryLabelColor
			headline = message
			subtext = "This may take a few moments."
		case .success(let message):
			symbolName = "checkmark.circle.fill"
			tint = .systemGreen
			headline = message
			subtext = nil
		case .error(let message):
			symbolName = "exclamationmark.triangle.fill"
			tint = .systemRed
			headline = message
			subtext = nil
		}

		layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
		headlineLabel.textColor = .labelColor
		headlineLabel.stringValue = headline
		subtextLabel.stringValue = subtext ?? ""
		subtextLabel.isHidden = subtext == nil

		if let symbolName {
			iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
			iconView.contentTintColor = tint
			iconView.isHidden = false
			spinner.stopAnimation(nil)
		} else {
			iconView.isHidden = true
			spinner.startAnimation(nil)
		}
	}
}

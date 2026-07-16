import AppKit

/// Frosted chrome shared by the animation badge's label pill and platform chip:
/// a dark `hudWindow` material matching the attention bubble, with a hairline
/// white border and soft drop shadow. The frosted body doubles as the contrast
/// backdrop that lets a single white glyph / mono label read over any window
/// behind the transparent pet frame.
enum AnimationBadgeChrome {
	static let textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
	/// Dark overlay layered above the frosted material to guarantee a readable
	/// dark floor when the pet sits over a light desktop or app background.
	/// Matches the opacity level of the SoA gate badge's neutral dark pill.
	static let badgeTint = NSColor(calibratedWhite: 0.0, alpha: 0.55)

	static func makeEffectView() -> NSVisualEffectView {
		let view = NSVisualEffectView(frame: .zero)
		view.material = .hudWindow
		view.blendingMode = .behindWindow
		view.state = .active
		view.appearance = NSAppearance(named: .darkAqua)
		view.wantsLayer = true
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}

	static func makeTintView() -> NSView {
		let view = NSView(frame: .zero)
		view.wantsLayer = true
		view.layer?.backgroundColor = badgeTint.cgColor
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}

	static func apply(
		to host: NSView,
		effect: NSVisualEffectView,
		tint: NSView? = nil,
		cornerRadius: CGFloat
	) {
		effect.layer?.cornerRadius = cornerRadius
		effect.layer?.masksToBounds = true
		tint?.layer?.cornerRadius = cornerRadius
		tint?.layer?.masksToBounds = true
		host.layer?.cornerRadius = cornerRadius
		host.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		host.layer?.borderWidth = 1
		host.layer?.shadowColor = NSColor.black.cgColor
		host.layer?.shadowOpacity = 0.32
		host.layer?.shadowRadius = 8
		host.layer?.shadowOffset = CGSize(width: 0, height: -2)
	}
}


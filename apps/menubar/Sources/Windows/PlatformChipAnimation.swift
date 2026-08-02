import AppKit

/// The in-flight logo animation for one platform's chip glyph.
///
/// Every animation here is a whole-layer transform on the existing monochrome
/// template asset — no per-shape choreography, no second piece of art. Two
/// families:
///
/// - **Z-spin** (`spin`): rotation in the screen plane, optionally with a
///   scale breathe. Reserved for glyphs that are radially symmetric enough that
///   spinning doesn't visibly change their bounding box (Claude's asterisk,
///   OpenAI's knot, Cursor's cube, the default star).
/// - **Axis flip** (`flip`): rotation about an axis lying *in* the screen plane,
///   so the glyph turns like a card. Accelerates through a couple of
///   revolutions, decelerates to a halt, then unwinds the other way. Only valid
///   for a mark that is mirror-symmetric about the chosen axis, since the layer
///   is double-sided and shows the same art on its back face.
enum PlatformChipAnimation: Equatable {
	/// Screen-plane rotation. `scalePulse` shrinks to that fraction at the
	/// midpoint and regrows, `nil` for a constant size.
	case spin(period: CFTimeInterval, scalePulse: CGFloat?)
	/// In-plane-axis flip that winds up, halts, and unwinds.
	case flip(axis: Axis, period: CFTimeInterval, turns: Double)

	enum Axis: Equatable {
		/// Rotation about the horizontal axis — a top-to-bottom page flip.
		case horizontal
		/// Rotation about the vertical axis — a card turning on its spine.
		case vertical

		var keyPath: String {
			switch self {
			case .horizontal: "transform.rotation.x"
			case .vertical: "transform.rotation.y"
			}
		}
	}

	/// The animation for a platform, or `nil` for one that stays static.
	///
	/// Axis choice follows each mark's own line of symmetry: VS Code's ribbon
	/// mirrors about the horizontal, Antigravity's arch about the vertical.
	static func forPlatform(_ platform: PlatformAttribution) -> PlatformChipAnimation? {
		switch platform {
		case .claudeCode:
			// Mirrors Claude Code's own in-flight indicator: a slow, even rotation.
			.spin(period: 3.2, scalePulse: nil)
		case .codex:
			.spin(period: 2.4, scalePulse: 0.72)
		case .cursor:
			.spin(period: 2.8, scalePulse: nil)
		case .vscode:
			.flip(axis: .horizontal, period: 4.0, turns: 2)
		case .antigravity:
			.flip(axis: .vertical, period: 4.0, turns: 2)
		case .default:
			// The idle/combined star is shown while nothing is driving the pet, so
			// it has no in-flight state of its own to signal.
			nil
		}
	}

	/// Builds the repeating `CAAnimation` for this descriptor.
	func makeAnimation() -> CAAnimation {
		switch self {
		case let .spin(period, scalePulse):
			let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
			rotation.fromValue = 0
			rotation.toValue = -2 * Double.pi  // negative == clockwise on screen
			rotation.duration = period
			rotation.repeatCount = .infinity
			rotation.timingFunction = CAMediaTimingFunction(name: .linear)
			guard let scalePulse else { return rotation }

			let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
			pulse.values = [1.0, scalePulse, 1.0]
			pulse.keyTimes = [0, 0.5, 1]
			pulse.duration = period
			pulse.repeatCount = .infinity
			pulse.timingFunctions = [
				CAMediaTimingFunction(name: .easeInEaseOut),
				CAMediaTimingFunction(name: .easeInEaseOut),
			]

			let group = CAAnimationGroup()
			group.animations = [rotation, pulse]
			group.duration = period
			group.repeatCount = .infinity
			return group

		case let .flip(axis, period, turns):
			// 0 → n turns → 0. Ease-in-out on both legs gives the wind-up,
			// deceleration to a halt at the midpoint, and the reverse unwind; the
			// shared 0 endpoints make the repeat seamless.
			let flip = CAKeyframeAnimation(keyPath: axis.keyPath)
			flip.values = [0, -2 * Double.pi * turns, 0]
			flip.keyTimes = [0, 0.5, 1]
			flip.duration = period
			flip.repeatCount = .infinity
			flip.timingFunctions = [
				CAMediaTimingFunction(name: .easeInEaseOut),
				CAMediaTimingFunction(name: .easeInEaseOut),
			]
			return flip
		}
	}
}

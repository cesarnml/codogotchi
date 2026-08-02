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
/// - **Axis rock** (`rock`): rotation about an axis lying *in* the screen plane,
///   so the glyph tilts like a card on a hinge, easing to a halt at each extreme
///   and swinging back. Only valid for a mark that is mirror-symmetric about the
///   chosen axis.
///
/// `rock` deliberately does *not* complete revolutions. Rotating a flat mark by
/// θ about an in-plane axis scales its apparent width by |cos θ|, so a full turn
/// necessarily passes through 90° — edge-on, zero width, no logo. Slowing that
/// down makes it worse rather than better: the legible share of the sweep is
/// fixed by geometry at ~67%, so a longer period only stretches how long the
/// mark spends as an unreadable sliver. Capping the angle below 90° is the only
/// thing that keeps the mark identifiable, and it still reads as a real 3D tilt.
enum PlatformChipAnimation: Equatable {
	/// Screen-plane rotation. `scalePulse` shrinks to that fraction at the
	/// midpoint and regrows, `nil` for a constant size.
	case spin(period: CFTimeInterval, scalePulse: CGFloat?)
	/// In-plane-axis tilt that swings to `maxAngleDegrees`, eases to a halt, and
	/// swings back through the opposite extreme. Never reaches 90°.
	case rock(axis: Axis, period: CFTimeInterval, maxAngleDegrees: Double)

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

	/// Shrink depth shared by all three spinning marks — the glyph breathes down
	/// to this fraction at the midpoint and back. One value so the spinners read
	/// as one family rather than three separately tuned animations.
	static let spinScalePulse: CGFloat = 0.72

	/// Tilt limit for the rocking marks. Stays well clear of the 90° edge-on
	/// point: at 55° the mark still presents ~57% of its full width, so it never
	/// collapses to an unreadable sliver.
	static let rockMaxAngleDegrees: Double = 55

	/// The animation for a platform, or `nil` for one that stays static.
	///
	/// Axis choice follows each mark's own line of symmetry: VS Code's ribbon
	/// mirrors about the horizontal, Antigravity's arch about the vertical.
	static func forPlatform(_ platform: PlatformAttribution) -> PlatformChipAnimation? {
		switch platform {
		case .claudeCode:
			// Mirrors Claude Code's own in-flight indicator: a slow, even rotation.
			.spin(period: 3.2, scalePulse: spinScalePulse)
		case .codex:
			.spin(period: 2.4, scalePulse: spinScalePulse)
		case .cursor:
			.spin(period: 2.8, scalePulse: spinScalePulse)
		case .vscode:
			.rock(axis: .horizontal, period: 3.6, maxAngleDegrees: rockMaxAngleDegrees)
		case .antigravity:
			.rock(axis: .vertical, period: 3.6, maxAngleDegrees: rockMaxAngleDegrees)
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

		case let .rock(axis, period, maxAngleDegrees):
			// 0 → +max → 0 → −max → 0. Easing at every extreme gives the swing its
			// pendulum feel — quickest through the flat-on centre, decelerating to a
			// halt at each tilt — and the shared 0 endpoints make the repeat
			// seamless. Four legs, so the cycle is symmetric in both directions.
			let maxAngle = maxAngleDegrees * Double.pi / 180
			let rock = CAKeyframeAnimation(keyPath: axis.keyPath)
			rock.values = [0, maxAngle, 0, -maxAngle, 0]
			rock.keyTimes = [0, 0.25, 0.5, 0.75, 1]
			rock.duration = period
			rock.repeatCount = .infinity
			rock.timingFunctions = Array(
				repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
			return rock
		}
	}
}

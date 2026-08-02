import AppKit

/// The in-flight logo animation for one platform's chip glyph.
///
/// Every animation is a whole-layer transform on the existing monochrome
/// template asset — no per-shape choreography and no second piece of art. All
/// marks share the same scale breathe; the only question per platform is
/// whether a rotation rides on top of it.
///
/// **The rule: spin only when the mark's rotational symmetry order is 3 or
/// more.** A mark that maps onto itself every 120° or less (Claude's asterisk,
/// OpenAI's knot, Cursor's cube silhouette) reads as spinning *in place* —
/// the eye registers motion without the shape appearing to change. A mark with
/// symmetry order 1 (VS Code's ribbon, Antigravity's arch) has no rotation but
/// the identity that maps it onto itself, so spinning it does not read as
/// rotation at all: it tumbles, and spends half of every cycle upside down,
/// which looks broken rather than busy. Those two breathe only. Pure scale is
/// symmetry-agnostic — it preserves orientation and silhouette exactly, so the
/// mark stays identifiable whatever its shape.
///
/// An earlier revision instead gave those two a 3D tilt about their line of
/// mirror symmetry. Abandoned: rotating a flat mark by θ about an axis lying
/// *in* the screen plane scales its apparent width by |cos θ|, squashing it
/// toward an unreadable sliver. Capping the angle short of edge-on kept it
/// legible on paper but still looked wrong in motion, and slowing it down makes
/// it worse — the legible share of the sweep is fixed by geometry, so a longer
/// period only stretches out the bad part.
enum PlatformChipAnimation: Equatable {
	/// Screen-plane rotation with the shared breathe riding on top.
	case spin(period: CFTimeInterval, scalePulse: CGFloat)
	/// Breathe with no rotation — for marks that would tumble rather than spin.
	case breathe(period: CFTimeInterval, scalePulse: CGFloat)

	/// Shrink depth shared by every mark — the glyph breathes down to this
	/// fraction at the midpoint and back. One value so the set reads as a family
	/// rather than five separately tuned animations.
	static let scalePulse: CGFloat = 0.72

	/// The animation for a platform, or `nil` for one that stays static.
	///
	/// Periods are spread 0.2s apart so two pets working at once don't lock into
	/// visible unison, without any of them reading as faster or slower "moods".
	static func forPlatform(_ platform: PlatformAttribution) -> PlatformChipAnimation? {
		switch platform {
		// Rotational symmetry order >= 3 — these spin.
		case .codex:
			.spin(period: 2.4, scalePulse: scalePulse)
		case .cursor:
			.spin(period: 2.8, scalePulse: scalePulse)
		case .claudeCode:
			// Mirrors Claude Code's own in-flight indicator: a slow, even rotation.
			.spin(period: 3.2, scalePulse: scalePulse)
		// Rotational symmetry order 1 — spinning these tumbles them, so breathe only.
		case .antigravity:
			.breathe(period: 2.6, scalePulse: scalePulse)
		case .vscode:
			.breathe(period: 3.0, scalePulse: scalePulse)
		case .default:
			// The idle/combined star is shown while nothing is driving the pet, so
			// it has no in-flight state of its own to signal.
			nil
		}
	}

	/// Builds the repeating `CAAnimation` for this descriptor.
	func makeAnimation() -> CAAnimation {
		switch self {
		case let .breathe(period, scalePulse):
			return Self.makePulse(period: period, scalePulse: scalePulse)

		case let .spin(period, scalePulse):
			let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
			rotation.fromValue = 0
			rotation.toValue = -2 * Double.pi  // negative == clockwise on screen
			rotation.duration = period
			rotation.repeatCount = .infinity
			rotation.timingFunction = CAMediaTimingFunction(name: .linear)

			let group = CAAnimationGroup()
			group.animations = [rotation, Self.makePulse(period: period, scalePulse: scalePulse)]
			group.duration = period
			group.repeatCount = .infinity
			return group
		}
	}

	/// Shrink to `scalePulse` at the midpoint and back, easing at both ends.
	private static func makePulse(period: CFTimeInterval, scalePulse: CGFloat) -> CAKeyframeAnimation {
		let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
		pulse.values = [1.0, scalePulse, 1.0]
		pulse.keyTimes = [0, 0.5, 1]
		pulse.duration = period
		pulse.repeatCount = .infinity
		pulse.timingFunctions = [
			CAMediaTimingFunction(name: .easeInEaseOut),
			CAMediaTimingFunction(name: .easeInEaseOut),
		]
		return pulse
	}
}

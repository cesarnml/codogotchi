import Foundation

/// Floating-only mouse-reactive interaction animations.
///
/// These are deliberately **not** modeled as `ActivityState` cases. The hook
/// emits agent activity; mouse-driven interaction is a transient floating-
/// surface concern (drag direction, hover/resize affordance) and never enters
/// `state.json`. Keeping them off `ActivityState` also keeps the menu-bar
/// renderer's row map free of the reserved Codex rows (1, 2, 4) — only the
/// floating scene consumes them.
///
/// Per `docs/contracts/animation-state-vocabulary.md`:
/// - `.runningRight` → Codex row 1 (rightward drag/movement feedback)
/// - `.runningLeft`  → Codex row 2 (leftward drag/movement feedback)
/// - `.jumping`      → Codex row 4 (hover, resize, attention feedback)
enum FloatingInteraction: Equatable, CaseIterable {
	case runningRight
	case runningLeft
	case jumping
}

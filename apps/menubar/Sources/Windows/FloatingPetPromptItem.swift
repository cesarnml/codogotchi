import AppKit

/// One activatable row in the right-click prompt. A prompt with a single item is
/// the classic single "Hide" pill; multiple items stack vertically (e.g. a
/// "Force Idle" escape hatch above "Hide pet").
struct FloatingPetPromptItem {
	let title: String
	let onActivate: () -> Void
}


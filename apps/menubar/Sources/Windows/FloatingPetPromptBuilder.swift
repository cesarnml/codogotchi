import AppKit

/// Capabilities that vary per window shape (Own vs Minimalist), per
/// `docs/contracts/window-capability-matrix.md` §1. Named per capability, not
/// per shape — Combined is not a distinct capability set here: it inherits
/// whichever shape it is currently routed through and calls the builder with
/// that shape's capabilities.
struct FloatingPetPromptCapabilities {
	/// R1.2 — pet/badge is not idle.
	var offersForceIdle: Bool
	/// R1.3 gate — the window's current session-label badge text, or `nil`
	/// when no label is shown at all. Rename… is offered whenever non-nil, OR
	/// whenever `hasActiveSession` — a live session whose upstream platform
	/// never auto-titled the thread (`SessionTitleResolver` returned `nil`)
	/// still needs a way to acquire a label, and Rename is the only affordance
	/// that can supply one from scratch.
	var sessionLabel: String?
	/// R1.4/R1.5 gate — the window currently resolves to a real backing
	/// session, including folded plain-origin and Combined windows; offers
	/// Sync Label and Prune Session.
	var hasActiveSession: Bool
	/// R1.6 — "Minimalist Mode" (Own) or "Pet Mode" (Minimalist).
	var modeSwitchTitle: String
	/// R1.7 — Minimalist-only "Panel Size…", unconditional when present; Own
	/// has no analogous size concept.
	var offersPanelSize: Bool
	/// R1.9 — "Hide pet" (Own) or "Hide panel" (Minimalist); same semantics,
	/// cosmetic title only.
	var hideItemTitle: String
}

/// Activation closures for every possible prompt item. Each closure is
/// expected to already perform any dismiss-on-activate the caller needs — the
/// builder only decides which items exist and in what order.
struct FloatingPetPromptHandlers {
	var forceIdle: () -> Void
	var rename: () -> Void
	var syncLabel: () -> Void
	var prune: () -> Void
	var modeSwitch: () -> Void
	var panelSize: () -> Void
	var hideAllOtherPets: () -> Void
	var hideThis: () -> Void
}

/// The single `[FloatingPetPromptItem]` builder for the right-click hide
/// prompt, shared by Own (`FloatingPetInteractionView`) and Minimalist
/// (`MinimalistBadgeView`). Per-shape differences are expressed only as
/// `FloatingPetPromptCapabilities` fields — never as shape identity.
enum FloatingPetPromptBuilder {
	static func items(
		capabilities: FloatingPetPromptCapabilities,
		handlers: FloatingPetPromptHandlers
	) -> [FloatingPetPromptItem] {
		var items: [FloatingPetPromptItem] = []

		if capabilities.offersForceIdle {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.forceIdleTitle, onActivate: handlers.forceIdle))
		}
		if capabilities.sessionLabel != nil || capabilities.hasActiveSession {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.renameTitle, onActivate: handlers.rename))
		}
		if capabilities.hasActiveSession {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.syncLabelTitle, onActivate: handlers.syncLabel))
			items.append(
				FloatingPetPromptItem(
					title: FloatingPetHidePrompt.pruneTitle,
					onActivate: handlers.prune))
		}
		items.append(
			FloatingPetPromptItem(title: capabilities.modeSwitchTitle, onActivate: handlers.modeSwitch))
		if capabilities.offersPanelSize {
			items.append(
				FloatingPetPromptItem(title: FloatingPetHidePrompt.panelSizeTitle, onActivate: handlers.panelSize))
		}
		items.append(
			FloatingPetPromptItem(
				title: FloatingPetHidePrompt.hideAllOtherPetsTitle, onActivate: handlers.hideAllOtherPets))
		items.append(
			FloatingPetPromptItem(title: capabilities.hideItemTitle, onActivate: handlers.hideThis))

		return items
	}
}

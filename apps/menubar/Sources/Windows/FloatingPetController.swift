import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol FloatingPetVisibilityControlling: AnyObject {
	var isFloatingPetVisible: Bool { get }
	func setFloatingPetVisible(_ visible: Bool)
}

/// Unified interface for a single floating-pet window managed by `FloatingPetWindowPool`.
/// `FloatingPetController` conforms; tests inject lightweight stubs.
@MainActor
protocol FloatingPetWindowControlling: FloatingPetVisibilityControlling {
	func apply(state: ActivityState, visualMode: VisualMode)
	/// Latest prompt-timer status for this window's render key, computed by the
	/// pool's `PromptTimerTracker` (the pool owns the tracker so the timer keeps
	/// correct time while no window exists — see `PromptTimerTracker`). The
	/// window only displays it.
	func applyPromptTimerStatus(_ status: PromptTimerStatus?)
	/// `PoolApply` (P18.04)'s equivalent of `applyPromptTimerStatus`, taking
	/// the already-rendered `PromptTimerPresentation` `DesiredWindow` carries
	/// instead of the raw `PromptTimerStatus`: `PoolDerive`'s `PoolMemory`
	/// (not this protocol's caller) owns the `PromptTimerTracker`, so by the
	/// time a `DesiredWindow` reaches `apply` only the rendered label/
	/// isRunning pair is available — reconstructing a fake raw status here
	/// would fabricate a `startedAt` that was never observed. See this
	/// ticket's Rationale (Contract note) for why this is a separate method
	/// rather than a signature change to `applyPromptTimerStatus`.
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?)
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?)
	func applyGateBadge(content: GateBadgeContent?)
	func applyPlatform(origin: String?)
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?)
	/// Assigned session number for this window (nil for a plain-origin or
	/// "combined" window — session numbering only applies to session-keyed
	/// windows). Drives the `PlatformSessionBadge` row.
	func applySessionNumber(_ number: Int?)
	func applyHasActiveSession(_ hasActiveSession: Bool)
	/// User-set rename label for this session (from `SessionLabelStore`), or
	/// `nil` to fall back to "Session N". No-op for plain-origin/"combined"
	/// windows, mirroring `applySessionNumber`.
	func applySessionLabel(_ label: String?)
	/// "<platform> · <label>" naming the resolved session this window folds,
	/// or `nil` for a genuinely solo window (P19.03). Feeds the Prune menu
	/// item and its confirmation alert only.
	func applyFoldedSessionDisplay(_ display: String?)
	/// Small, fixed, non-renamable badge naming this window's mode — the
	/// resolved session's platform display name for a folded `.origin`, or
	/// "Combined" for `.combined` — or `nil` for a genuinely solo window
	/// (P19.04). Visually and functionally distinct from the renamable
	/// session-label badge; never wired to a rename gesture.
	func applyModeIndicatorBadge(_ text: String?)
	/// Last submitted prompt for this exact session, shown as a delayed hover
	/// tooltip on the session badge. `nil`/empty clears the tooltip.
	func applySessionTooltip(_ summary: String?)
	/// Reversible P15.08 conflict-bubble presentation: `payload` shown on the
	/// longest-lived active session's panel while this window's origin is in
	/// `FloatingPetWindowPool.blockedOrigins`; `nil` hides it. Distinct from
	/// `applyAttention` — the conflict signal is pool-level, not per-session
	/// `state.json` state.
	func applyConflictBubble(_ payload: ConflictBubblePayload?)
	/// This window's current on-screen frame (location + size), regardless of
	/// visibility. Read by the pool right before a session-cap eviction (P15.07)
	/// tears this window down, so a newly-spawned session window replacing it
	/// can inherit the same slot instead of defaulting.
	var currentFrame: CGRect { get }
	/// Moves this window to `frame` (clamped to the visible frame) and persists
	/// it as this window's saved position, so a later relaunch keeps the
	/// inherited location too. Used only right after a session window spawns
	/// into a slot freed by an evicted sibling session of the same origin.
	func adoptFrame(_ frame: CGRect)
	/// Live-updates the idle-escalation thresholds (Settings > Customization's
	/// "Pet Idle Escalation Timing") for an already-open window, so a change
	/// takes effect without waiting for this window to respawn. No-op for
	/// controllers with no idle-escalation concept (e.g. Minimalist).
	func updateIdleEscalationConfig(_ config: IdleEscalationConfig)
}

extension FloatingPetWindowControlling {
	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {}
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {}
	func applySessionNumber(_ number: Int?) {}
	func applyHasActiveSession(_ hasActiveSession: Bool) {}
	func applySessionLabel(_ label: String?) {}
	func applyFoldedSessionDisplay(_ display: String?) {}
	func applyModeIndicatorBadge(_ text: String?) {}
	func applySessionTooltip(_ summary: String?) {}
	func applyConflictBubble(_ payload: ConflictBubblePayload?) {}
	var currentFrame: CGRect { .zero }
	func adoptFrame(_ frame: CGRect) {}
	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {}
}

/// Unified interface for a floating-pet panel renderer, covering both the
/// full "Own"-mode panel (`FloatingPetPanelController`) and the compact
/// "Minimalist" strip (`MinimalistPanelController`) — one renderer
/// interface, two skins. Members outside a conformer's shape get a
/// default no-op via the extension below, so neither renderer is forced
/// to implement members that don't apply to it.
@MainActor
protocol PanelManaging: AnyObject {
	func show(frame: CGRect)
	func hide()
	func apply(state: ActivityState, visualMode: VisualMode)
	/// Pool-computed prompt-timer status for display (see `PromptTimerTracker`).
	func applyPromptTimerStatus(_ status: PromptTimerStatus?)
	/// `PoolApply` (P18.04)'s equivalent, taking an already-rendered
	/// `PromptTimerPresentation` instead of the raw `PromptTimerStatus` —
	/// see `FloatingPetWindowControlling.applyPromptTimerPresentation`'s doc
	/// for why this is a separate method.
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?)
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?)
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?)
	func applyGateBadge(content: GateBadgeContent?)
	func applyPlatform(origin: String?)
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool)
	func setRPGHUDEnabled(_ enabled: Bool)
	func setHUDDemoActive(_ active: Bool)
	func setHUDPinned(_ pinned: Bool)
	func setInteraction(_ interaction: FloatingInteraction?)
	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void)
	/// Assigned session number for this window (nil clears the session badge row).
	func applySessionNumber(_ number: Int?)
	func applyHasActiveSession(_ hasActiveSession: Bool)
	/// User-set rename label for this session (from `SessionLabelStore`), or
	/// `nil` to fall back to "Session N". No-op for plain-origin/"combined"
	/// windows, mirroring `applySessionNumber`.
	func applySessionLabel(_ label: String?)
	/// "<platform> · <label>" naming the resolved session this window folds,
	/// or `nil` for a genuinely solo window (P19.03). Feeds the Prune menu
	/// item and its confirmation alert only.
	func applyFoldedSessionDisplay(_ display: String?)
	/// Small, fixed, non-renamable badge naming this window's mode — the
	/// resolved session's platform display name for a folded `.origin`, or
	/// "Combined" for `.combined` — or `nil` for a genuinely solo window
	/// (P19.04). Visually and functionally distinct from the renamable
	/// session-label badge; never wired to a rename gesture.
	func applyModeIndicatorBadge(_ text: String?)
	/// Last submitted prompt for this exact session, shown as a delayed hover
	/// tooltip on the session badge. `nil`/empty clears the tooltip.
	func applySessionTooltip(_ summary: String?)
	/// Reversible P15.08 conflict-bubble presentation; `nil` hides it.
	func applyConflictBubble(_ payload: ConflictBubblePayload?)
	/// Live-updates the idle-escalation thresholds for this panel's scene.
	func updateIdleEscalationConfig(_ config: IdleEscalationConfig)
	func applyActivity(_ state: ActivityState)
	func applyPromptSummary(_ summary: String)
	func applyBadgeScale(_ scale: Double)
}

extension PanelManaging {
	// Floating-only members: default no-ops so MinimalistPanelController
	// (which has no sprite, RPG HUD, interaction, or idle-escalation concept)
	// isn't forced to implement them.
	func apply(state: ActivityState, visualMode: VisualMode) {}
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}
	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {}
	func setRPGHUDEnabled(_ enabled: Bool) {}
	func setHUDDemoActive(_ active: Bool) {}
	func setHUDPinned(_ pinned: Bool) {}
	func setInteraction(_ interaction: FloatingInteraction?) {}
	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {}

	// Minimalist-only members: default no-ops so FloatingPetPanelController
	// (which renders a sprite, not a compact strip) isn't forced to implement them.
	func applyActivity(_ state: ActivityState) {}
	func applyPromptSummary(_ summary: String) {}
	func applyBadgeScale(_ scale: Double) {}

	// Shared members with default no-ops (kept for convenience; both
	// conformers implement these directly).
	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {}
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {}
	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {}
	func applyGateBadge(content: GateBadgeContent?) {}
	func applyPlatform(origin: String?) {}
	func applySessionNumber(_ number: Int?) {}
	func applyHasActiveSession(_ hasActiveSession: Bool) {}
	func applySessionLabel(_ label: String?) {}
	func applyFoldedSessionDisplay(_ display: String?) {}
	func applyModeIndicatorBadge(_ text: String?) {}
	func applySessionTooltip(_ summary: String?) {}
	func applyConflictBubble(_ payload: ConflictBubblePayload?) {}
}

/// Action-handler surface shared by both renderer skins: the settable
/// closures `MenubarApp`'s window factory wires for user-initiated actions
/// (right-click affordances, attention dismissal, hide-this-window). Both
/// panel controllers expose the same nine slots, so the factory writes each
/// handler exactly once against this protocol instead of once per skin.
/// Per-skin differences are wiring parameters, not separate handler sets:
/// the mode-switch target is chosen by the factory (Own offers "Minimalist
/// Mode", Minimalist offers "Pet Mode" — capability matrix R1.6), and
/// Minimalist-only affordances like the Panel Size slider stay concrete
/// properties outside this protocol (matrix R1.7).
@MainActor
protocol PanelActionHandling: PanelManaging {
	/// User dismissed or focused away from the attention bubble.
	var onAttentionDismissed: (() -> Void)? { get set }
	/// User activated the right-click "Force Idle" affordance (only offered
	/// while non-idle) — the escape hatch for a stuck animation.
	var onForceIdle: (() -> Void)? { get set }
	/// User clicked the P15.08 conflict bubble's action button.
	var onOpenSettingsRequested: (() -> Void)? { get set }
	/// User committed a trimmed/capped label via the right-click rename
	/// affordance. The panel never writes the sidecar itself.
	var onRenameRequested: ((String) -> Void)? { get set }
	/// User activated the right-click "Sync Label" affordance. The panel
	/// never resolves or writes the label itself.
	var onSyncLabelRequested: (() -> Void)? { get set }
	/// User confirmed the right-click "Prune Session" affordance (P15.07).
	/// The panel never destroys session state itself.
	var onPruneRequested: (() -> Void)? { get set }
	/// User activated the right-click "Hide All Other Pets" affordance.
	/// The panel never touches other windows itself.
	var onHideAllOtherPetsRequested: (() -> Void)? { get set }
	/// User activated the right-click mode-switch affordance ("Minimalist
	/// Mode" on an Own panel, "Pet Mode" on a Minimalist strip). The target
	/// mode is decided by the wiring, not the panel.
	var onModeSwitchRequested: (() -> Void)? { get set }
	/// User activated the right-click hide-this-window affordance ("Hide
	/// pet" on an Own panel, "Hide panel" on a Minimalist strip — same
	/// semantics, per-skin title; matrix R1.9).
	var onHideWindowRequested: (() -> Void)? { get set }
}

@MainActor
final class FloatingPetController: NSObject, FloatingPetVisibilityControlling, FloatingPetWindowControlling {
	private let panel: PanelManaging
	private let visibleFrameProvider: () -> CGRect
	private let saveState: (FloatingAppState) throws -> Void
	private var state: FloatingAppState
	private let notificationCenter: NotificationCenter

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }

	/// Called after visibility is persisted and the panel is shown or hidden.
	var onVisibilityChanged: ((Bool) -> Void)?

	init(
		panel: PanelManaging,
		visibleFrameProvider: @escaping () -> CGRect,
		saveState: @escaping (FloatingAppState) throws -> Void = AppStateStore.save,
		notificationCenter: NotificationCenter = .default,
		initialState: FloatingAppState? = nil
	) {
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.saveState = saveState
		self.notificationCenter = notificationCenter
		self.state = initialState ?? AppStateStore.load(visibleFrame: visibleFrameProvider())
		super.init()

		panel.setFrameChangeHandler { [weak self] frame in
			self?.persistFrameChange(frame)
		}
		notificationCenter.addObserver(
			self,
			selector: #selector(displayParametersDidChange(_:)),
			name: NSApplication.didChangeScreenParametersNotification,
			object: nil
		)

		if state.isFloatingPetVisible {
			panel.show(frame: state.frame)
		}
		onVisibilityChanged?(state.isFloatingPetVisible)
	}

	deinit {
		notificationCenter.removeObserver(self)
	}

	func setFloatingPetVisible(_ visible: Bool) {
		let visibleFrame = visibleFrameProvider()
		let nextState = FloatingAppState(
			isFloatingPetVisible: visible,
			frame: FloatingFramePolicy.clamp(state.frame, to: visibleFrame),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
		)
		do {
			try saveState(nextState)
		} catch {
			NSLog("FloatingPetController: failed to persist floating visibility: \(error.localizedDescription)")
			return
		}

		state = nextState

		if visible {
			panel.show(frame: nextState.frame)
		} else {
			panel.hide()
		}
		onVisibilityChanged?(visible)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		panel.apply(state: state, visualMode: visualMode)
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		panel.applyPromptTimerStatus(status)
	}

	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
		panel.applyPromptTimerPresentation(presentation)
	}

	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		panel.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		panel.applyAttention(payload: payload, sourceEvent: sourceEvent)
	}

	func applyGateBadge(content: GateBadgeContent?) {
		panel.applyGateBadge(content: content)
	}

	func applyPlatform(origin: String?) {
		panel.applyPlatform(origin: origin)
	}

	func applySessionNumber(_ number: Int?) {
		panel.applySessionNumber(number)
	}

	func applyHasActiveSession(_ hasActiveSession: Bool) {
		panel.applyHasActiveSession(hasActiveSession)
	}

	func applySessionLabel(_ label: String?) {
		panel.applySessionLabel(label)
	}

	func applyFoldedSessionDisplay(_ display: String?) {
		panel.applyFoldedSessionDisplay(display)
	}

	func applyModeIndicatorBadge(_ text: String?) {
		panel.applyModeIndicatorBadge(text)
	}

	func applySessionTooltip(_ summary: String?) {
		panel.applySessionTooltip(summary)
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		panel.applyConflictBubble(payload)
	}

	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {
		panel.updateIdleEscalationConfig(config)
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		panel.applyRPGState(
			halfHearts: halfHearts,
			levelFraction: levelFraction,
			level: level,
			activeMinutes: activeMinutes,
			hudEnabled: hudEnabled
		)
	}

	func setRPGHUDEnabled(_ enabled: Bool) {
		panel.setRPGHUDEnabled(enabled)
	}

	func setHUDDemoActive(_ active: Bool) {
		panel.setHUDDemoActive(active)
	}

	func setHUDPinned(_ pinned: Bool) {
		panel.setHUDPinned(pinned)
	}

	var currentFrame: CGRect { state.frame }

	func adoptFrame(_ frame: CGRect) {
		saveClampedFrame(frame, visibleFrame: visibleFrameProvider(), logLabel: "session-slot inheritance")
	}

	func persistFrameChange(_ frame: CGRect) {
		saveClampedFrame(frame, visibleFrame: visibleFrameProvider(), logLabel: "frame change")
	}

	func reclampForVisibleFrameChange() {
		saveClampedFrame(
			state.frame,
			visibleFrame: visibleFrameProvider(),
			logLabel: "display change"
		)
	}

	@objc private func displayParametersDidChange(_ notification: Notification) {
		reclampForVisibleFrameChange()
	}

	private func saveClampedFrame(_ frame: CGRect, visibleFrame: CGRect, logLabel: String) {
		let nextState = FloatingAppState(
			isFloatingPetVisible: state.isFloatingPetVisible,
			frame: FloatingFramePolicy.clamp(frame, to: visibleFrame),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
		)
		do {
			try saveState(nextState)
		} catch {
			NSLog("FloatingPetController: failed to persist floating \(logLabel): \(error.localizedDescription)")
			return
		}

		state = nextState
		if nextState.isFloatingPetVisible {
			panel.show(frame: nextState.frame)
		}
	}
}

@MainActor
final class MinimalistWindowController: NSObject, FloatingPetWindowControlling {
	private let origin: WindowKey
	private let panel: PanelManaging
	private let visibleFrameProvider: () -> CGRect
	private let saveState: (FloatingAppState) throws -> Void
	private let notificationCenter: NotificationCenter
	private let promptSummaryProvider: (String) -> String
	private let badgeScaleProvider: () -> Double
	private var state: FloatingAppState
	/// Most recent origin passed to applyPlatform(origin:). Defaults to the
	/// controller's own origin; tracked separately so a combined-minimalist
	/// window's prompt summary follows whichever platform last won the badge
	/// rather than always reading the controller's nominal origin.
	private var lastAppliedOrigin: String

	var isFloatingPetVisible: Bool { state.isFloatingPetVisible }
	var onVisibilityChanged: ((Bool) -> Void)?

	init(
		origin: WindowKey,
		panel: PanelManaging,
		visibleFrameProvider: @escaping () -> CGRect,
		saveState: @escaping (FloatingAppState) throws -> Void = AppStateStore.save,
		notificationCenter: NotificationCenter = .default,
		initialState: FloatingAppState? = nil,
		promptSummaryProvider: @escaping (String) -> String = { PromptAttentionReader.latestSummary(origin: $0) },
		badgeScaleProvider: @escaping () -> Double = {
			CustomizationJsonReader.read(at: CodogotchiFolders.customizationPath()).minimalistBadgeScale
		}
	) {
		self.origin = origin
		self.panel = panel
		self.visibleFrameProvider = visibleFrameProvider
		self.saveState = saveState
		self.notificationCenter = notificationCenter
		self.promptSummaryProvider = promptSummaryProvider
		self.badgeScaleProvider = badgeScaleProvider
		self.lastAppliedOrigin = origin.origin
		self.state = initialState ?? AppStateStore.load(visibleFrame: visibleFrameProvider())
		super.init()

		panel.setFrameChangeHandler { [weak self] frame in
			self?.persistFrameChange(frame)
		}
		notificationCenter.addObserver(
			self,
			selector: #selector(displayParametersDidChange(_:)),
			name: NSApplication.didChangeScreenParametersNotification,
			object: nil
		)

		if state.isFloatingPetVisible {
			panel.applyBadgeScale(badgeScaleProvider())
			panel.show(frame: state.frame)
		}
		onVisibilityChanged?(state.isFloatingPetVisible)
	}

	deinit {
		notificationCenter.removeObserver(self)
	}

	func setFloatingPetVisible(_ visible: Bool) {
		let nextState = FloatingAppState(
			isFloatingPetVisible: visible,
			frame: FloatingFramePolicy.clamp(state.frame, to: visibleFrameProvider()),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
		)
		do {
			try saveState(nextState)
		} catch {
			NSLog("MinimalistWindowController: failed to persist floating visibility: \(error.localizedDescription)")
			return
		}

		state = nextState
		if visible {
			panel.applyBadgeScale(badgeScaleProvider())
			panel.show(frame: nextState.frame)
			refreshPromptSummary()
		} else {
			panel.hide()
		}
		onVisibilityChanged?(visible)
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		panel.applyBadgeScale(badgeScaleProvider())
		panel.applyActivity(state)
		refreshPromptSummary()
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		panel.applyPromptTimerStatus(status)
	}

	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
		panel.applyPromptTimerPresentation(presentation)
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		// Minimalist mode intentionally has no sprite and no RPG HUD.
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		panel.applyAttention(payload: payload, sourceEvent: sourceEvent)
		refreshPromptSummary()
	}

	func applyGateBadge(content: GateBadgeContent?) {
		panel.applyGateBadge(content: content)
	}

	func applyPlatform(origin: String?) {
		lastAppliedOrigin = origin ?? self.origin.origin
		panel.applyPlatform(origin: lastAppliedOrigin)
	}

	func applySessionNumber(_ number: Int?) {
		panel.applySessionNumber(number)
	}

	func applyHasActiveSession(_ hasActiveSession: Bool) {
		panel.applyHasActiveSession(hasActiveSession)
	}

	func applySessionLabel(_ label: String?) {
		panel.applySessionLabel(label)
	}

	func applyFoldedSessionDisplay(_ display: String?) {
		panel.applyFoldedSessionDisplay(display)
	}

	func applyModeIndicatorBadge(_ text: String?) {
		panel.applyModeIndicatorBadge(text)
	}

	func applySessionTooltip(_ summary: String?) {
		panel.applySessionTooltip(summary)
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		panel.applyConflictBubble(payload)
	}

	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {}

	var currentFrame: CGRect { state.frame }

	func adoptFrame(_ frame: CGRect) {
		saveClampedFrame(frame, visibleFrame: visibleFrameProvider(), logLabel: "session-slot inheritance")
	}

	func persistFrameChange(_ frame: CGRect) {
		saveClampedFrame(frame, visibleFrame: visibleFrameProvider(), logLabel: "frame change")
	}

	func reclampForVisibleFrameChange() {
		saveClampedFrame(
			state.frame,
			visibleFrame: visibleFrameProvider(),
			logLabel: "display change"
		)
	}

	@objc private func displayParametersDidChange(_ notification: Notification) {
		reclampForVisibleFrameChange()
	}

	private func refreshPromptSummary() {
		panel.applyPromptSummary(promptSummaryProvider(lastAppliedOrigin))
	}

	private func saveClampedFrame(_ frame: CGRect, visibleFrame: CGRect, logLabel: String) {
		// The strip is content-tight (small), but Own mode needs a larger pet-panel
		// frame. Clamp the origin using the STRIP's actual size so the badge/bubble
		// can reach the screen edge; save with petPanelSize so Own-mode restore is
		// valid. FloatingPetController re-clamps when it spawns Own mode.
		let petPanelSize: CGSize = {
			let s = state.frame.size
			let fp = FloatingFramePolicy.self
			guard s.width >= fp.minimumSize.width, s.width <= fp.maximumSize.width,
				s.height >= fp.minimumSize.height, s.height <= fp.maximumSize.height
			else { return fp.defaultSize }
			return s
		}()
		// Clamp origin so the strip itself (frame.size) stays within the visible
		// frame with a 6pt inset — same margin used in clampedFrame(origin:size:).
		let margin: CGFloat = 6
		let safe = visibleFrame.insetBy(dx: margin, dy: margin)
		let clampedOrigin = CGPoint(
			x: max(safe.minX, min(safe.maxX - frame.size.width, frame.origin.x)),
			y: max(safe.minY, min(safe.maxY - frame.size.height, frame.origin.y))
		)
		let nextState = FloatingAppState(
			isFloatingPetVisible: state.isFloatingPetVisible,
			frame: CGRect(origin: clampedOrigin, size: petPanelSize),
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
		)
		do {
			try saveState(nextState)
		} catch {
			NSLog("MinimalistWindowController: failed to persist floating \(logLabel): \(error.localizedDescription)")
			return
		}

		state = nextState
		// Re-show at the STRIP's actual clamped position, not the pet-panel-clamped
		// one, so the badge stays where the user left it after a drag.
		if nextState.isFloatingPetVisible {
			panel.show(frame: CGRect(origin: clampedOrigin, size: frame.size))
		}
	}
}

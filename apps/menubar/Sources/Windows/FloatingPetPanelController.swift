import AppKit

@MainActor
final class FloatingPetPanelController: PanelActionHandling {
	private var codexPet: CodexPet
	private var codogotchiPet: CodogotchiPet?
	private let demoFrameInterval: TimeInterval?
	private var idleEscalationConfig: IdleEscalationConfig
	private let initialIdleAge: TimeInterval
	private let clock: () -> Date
	private let visibleFrameProvider: () -> CGRect
	private var panel: NSPanel?
	private var scene: FloatingPetScene?
	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentSicknessLevel: SicknessLevel = .none
	private var frameChangeHandler: ((CGRect) -> Void)?
	/// Called when the user activates the right-click "Hide pet" affordance.
	/// Shared handler slot (`PanelActionHandling.onHideWindowRequested`); the
	/// app wires this to hide this window via the window pool.
	var onHideWindowRequested: (() -> Void)?
	/// Called when the user activates the right-click "Force Idle" affordance
	/// (only offered while non-idle). The app wires this to rewrite this pet's
	/// `state.d/` slice back to idle — an escape hatch for a stuck animation.
	var onForceIdle: (() -> Void)?
	/// Called when the user dismisses or focuses away from the attention bubble.
	/// Intended for the caller to persist the idle state back to state.json so a
	/// relaunch does not re-show the bubble.
	var onAttentionDismissed: (() -> Void)?
	/// Called when the user clicks the P15.08 conflict bubble's action button.
	/// Wired by the caller to open Settings > Customization.
	var onOpenSettingsRequested: (() -> Void)?

	/// Owns instance lifecycle, anchoring, drag/right-click routing, and
	/// fronting for the animation badge, gate badge, attention bubble,
	/// conflict bubble, and RPG HUD family (P17.03). This controller still
	/// owns all "when is this visible" business logic (active-content
	/// flags, hover state, transient-reveal timers) — the coordinator only
	/// performs the mechanical reposition/front/hide act.
	private let chromeCoordinator: ChromeFlockCoordinator
	private var lastPanelFrame: CGRect = .zero
	private var isPanelShown = false
	private var attentionActive = false
	/// Mirrors `attentionActive` for the P15.08 conflict bubble: true while
	/// `applyConflictBubble` last received a non-nil payload, so drag/resize
	/// re-anchoring (`reanchorChrome`) keeps the conflict bubble glued to the
	/// panel the same way it does the real attention bubble.
	private var conflictActive = false
	private var gateBadgeContent: GateBadgeContent?
	/// Mirror of the scene's idle-escalation level, used for the badge label.
	private var currentEscalation: IdleEscalation = .none
	/// Platform attribution from the latest `source_event.origin`, resolved to a
	/// logo chip shown immediately left of the animation badge. `nil` when the
	/// origin is absent or non-platform, in which case no chip is drawn.
	private var currentPlatform: PlatformAttribution?
	/// Latest `source_event` from `state.json`, mirrored so a double-click on
	/// the platform chip can resolve the same Focus target the attention
	/// bubble's Focus button does, even when no bubble is currently shown.
	private var currentSourceEvent: SourceEvent?
	/// Session number assigned to this window by `FloatingPetWindowPool`, or
	/// `nil` for a plain-origin/combined window. Drives the `PlatformSessionBadge`
	/// row beneath the platform chip + animation badge.
	private var currentSessionNumber: Int?
	private var currentHasActiveSession = false
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N".
	private var currentSessionLabel: String?
	/// Last submitted prompt for this session, shown as a delayed hover
	/// tooltip on the session badge.
	private var currentSessionTooltip: String?
	/// Small, fixed, non-renamable badge naming this window's mode — the
	/// resolved session's platform display name for a folded `.origin`, or
	/// "Combined" for `.combined` — or `nil` for a genuinely solo window
	/// (P19.04). Mirrored so a later `repositionAndShowAnimationBadge()` call
	/// triggered by an unrelated push doesn't clear it.
	private var currentModeIndicatorBadge: String?
	/// Latest prompt-timer status pushed by the pool (which owns the tracker —
	/// see `PromptTimerTracker`). This panel only renders it; the heartbeat
	/// recomputes the label each second while the status reports running.
	private var promptTimerStatus: PromptTimerStatus?
	private var promptTimerHeartbeat: Timer?
	/// Latest presentation pushed via `applyPromptTimerPresentation` (P18.04's
	/// already-rendered path). Kept separate from `promptTimerStatus` (raw)
	/// so a subsequent `repositionAndShowAnimationBadge()` call triggered by
	/// an unrelated push (e.g. `applyPlatform`, `applySessionNumber`) renders
	/// this instead of clobbering it with `promptTimerStatus?.presentation()`
	/// — `promptTimerStatus` never gets updated on this path, so without this
	/// override every later same-tick reposition would silently erase the
	/// pushed presentation.
	private var promptTimerPresentationOverride: PromptTimerPresentation?
	/// Fired with the trimmed/capped label the user commits via the
	/// right-click rename affordance. Wired by the caller (`MenubarApp`) to
	/// persist to `SessionLabelStore` — this panel never writes the sidecar.
	var onRenameRequested: ((String) -> Void)?
	/// Fired when the user confirms the right-click "Prune Session" affordance
	/// (P15.07). Wired by the caller (`MenubarApp`) to destroy the session's
	/// slice, free-list number, and label — this panel never touches those
	/// stores directly, it only reports the user's confirmed intent.
	var onPruneRequested: (() -> Void)?
	/// Fired when the user activates the right-click "Sync Label" affordance.
	/// Wired by the caller (`MenubarApp`) to re-fetch the platform's current
	/// thread title and persist it — this panel never resolves or writes the
	/// label itself.
	var onSyncLabelRequested: (() -> Void)?
	/// Fired when the user activates the right-click "Hide All Other Pets"
	/// affordance. Wired by the caller (`MenubarApp`) to hide every other
	/// currently-rendered window via the pool — this panel never touches
	/// other windows itself.
	var onHideAllOtherPetsRequested: (() -> Void)?
	/// Fired when the user activates the right-click "Minimalist Mode"
	/// affordance. Shared handler slot (`PanelActionHandling.onModeSwitchRequested`);
	/// wired by the caller (`MenubarApp`) to persist the mode switch to
	/// customization.json — this panel never writes config itself.
	var onModeSwitchRequested: (() -> Void)?

	// RPG HUD — shown on hover, and transiently revealed on animation moments
	// (lose/gain a half-heart, level up) when not hovering.
	private let rpgHUDViewModel = RPGHUDViewModel()
	private var isHoveringPet = false
	/// Local event monitor installed when the pointer leaves the pet frame while
	/// the HUD is visible — keeps the HUD alive until the pointer also exits the
	/// HUD panel itself.
	private var hudHoverMonitor: Any?
	// Ghosted (0 hearts): the pet renders grayscale and a persistent tombstone is
	// shown to the right of the pet. Both are part of the RPG HUD — they clear
	// when at least a half-heart returns *or* the HUD is disabled. The active
	// decision lives in `rpgHUDViewModel.showsGhostPresentation`.
	/// Pending auto-hide for a transient (non-hover) reveal.
	private var hudAutoHideWork: DispatchWorkItem?
	/// Set by the view-model's flash callback during `update`, signalling that
	/// the current snapshot crossed an animation threshold worth revealing.
	private var hudFlashPending = false
	/// Seconds a transient reveal stays on screen before fading out.
	private static let hudTransientSeconds: TimeInterval = 4.0
	/// When true (HUD demo), the HUD is pinned visible regardless of hover.
	private var hudDemoActive = false
	/// When true (runtime `hud-pin` sentinel), the HUD stays visible regardless of
	/// hover. Unlike `hudDemoActive` this does NOT suppress live RPG updates, so a
	/// scripted demo (e.g. `tcha`) can keep feeding hearts/level while the HUD is
	/// forced on.
	private var hudPinned = false
	/// HUD forced visible (sweep demo or runtime pin) regardless of hover.
	private var hudForcedVisible: Bool { hudDemoActive || hudPinned }
	/// True while the user is actively dragging the pet. The RPG HUD (hearts,
	/// heart-regen bar, XP ring + its content) and the ghost chrome (tombstone +
	/// revival meter) are fully ordered out for the duration so they neither render
	/// nor re-anchor each drag tick — repositioning them per `mouseDragged` was the
	/// main source of drag lag. The correct presentation is restored on mouse-up.
	private var isDraggingPet = false

	init(
		codexPet: CodexPet,
		codogotchiPet: CodogotchiPet?,
		demoFrameInterval: TimeInterval? = nil,
		idleEscalationConfig: IdleEscalationConfig = .production,
		initialIdleAge: TimeInterval = 0,
		clock: @escaping () -> Date = Date.init,
		visibleFrameProvider: @escaping () -> CGRect = {
			NSScreen.screens.isEmpty
				? CGRect(x: 0, y: 0, width: 800, height: 600)
				: NSScreen.screens.map(\.visibleFrame).reduce(CGRect.null) { $0.union($1) }
		}
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.demoFrameInterval = demoFrameInterval
		self.idleEscalationConfig = idleEscalationConfig
		self.initialIdleAge = initialIdleAge
		self.clock = clock
		self.visibleFrameProvider = visibleFrameProvider
		self.chromeCoordinator = ChromeFlockCoordinator()
		self.chromeCoordinator.configureRouting(
			ChromeFlockCoordinator.ChromeRouting(
				presentHidePrompt: { [weak self] anchor in self?.presentChromeHidePrompt(anchorInScreen: anchor) },
				beginDrag: { [weak self] in self?.beginChromeDrag() },
				continueDrag: { [weak self] in self?.continueChromeDrag() },
				endDrag: { [weak self] in self?.endChromeDrag() }
			)
		)
		self.chromeCoordinator.onAttentionDismiss = { [weak self] in self?.handleBubbleDismiss() }
		self.chromeCoordinator.onConflictAction = { [weak self] in self?.onOpenSettingsRequested?() }
		self.chromeCoordinator.onConflictDismiss = { [weak self] in
			self?.conflictActive = false
			self?.chromeCoordinator.hideConflictBubble()
		}
		self.chromeCoordinator.onAnimationBadgePlatformChipDoubleClick = { [weak self] in
			AttentionFocusTarget.focus(sourceEvent: self?.currentSourceEvent)
		}
	}

	func show(frame: CGRect) {
		let panel = self.panel ?? makePanel(frame: frame)
		panel.setFrame(frame, display: true)

		if scene == nil {
			let scene = FloatingPetScene(
				size: frame.size,
				codexPet: codexPet,
				codogotchiPet: codogotchiPet,
				demoFrameInterval: demoFrameInterval,
				idleEscalationConfig: idleEscalationConfig,
				initialIdleAge: initialIdleAge,
				clock: clock
			)
			scene.onIdleEscalationChange = { [weak self] level in
				guard let self else { return }
				self.currentEscalation = level
				self.repositionAndShowAnimationBadge()
			}
			scene.update(state: currentState, visualMode: currentMode)
			scene.setSicknessLevel(currentSicknessLevel)
			self.scene = scene
			(panel.contentView as? FloatingPetInteractionView)?.presentScene(scene)
		} else {
			scene?.size = frame.size
			scene?.update(state: currentState, visualMode: currentMode)
			scene?.setSicknessLevel(currentSicknessLevel)
		}

		panel.orderFrontRegardless()
		self.panel = panel
		if let interactionView = panel.contentView as? FloatingPetInteractionView {
			interactionView.frame = NSRect(origin: .zero, size: frame.size)
			interactionView.setSpriteKitPaused(false)
			interactionView.prepareForDisplay()
		}
		scene?.resumeAnimation()

		isPanelShown = true
		lastPanelFrame = frame
		// Animation badge first: the bubble's and gate badge's leading edge are
		// anchored off the animation badge panel's own frame (the platform
		// chip's leading edge), so it must already be positioned this tick
		// before either reads `chipLeadingX`.
		repositionAndShowAnimationBadge()
		if attentionActive {
			repositionAndShowBubble()
		}
		if conflictActive {
			repositionAndShowConflictBubble()
		}
		if gateBadgeContent != nil {
			repositionAndShowGateBadge()
		}
		updateGhostPresentation()
	}

	func hide() {
		(panel?.contentView as? FloatingPetInteractionView)?.dismissHidePromptIfPresent()
		scene?.pauseAnimation()
		(panel?.contentView as? FloatingPetInteractionView)?.setSpriteKitPaused(true)
		panel?.orderOut(nil)
		isPanelShown = false
		chromeCoordinator.hideAttentionBubble()
		chromeCoordinator.hideConflictBubble()
		chromeCoordinator.hideGateBadge()
		chromeCoordinator.hideAnimationBadge()
		chromeCoordinator.hideGhostChrome()
		cancelHUDAutoHide()
		cancelHUDHoverMonitor()
		chromeCoordinator.hideHUDImmediately()
	}

	/// Swap in new pet loaders and immediately repaint the current state.
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		// Rebuild the scene with new pets when it's already visible.
		scene?.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	func applyConflictBubble(_ payload: ConflictBubblePayload?) {
		guard let payload else {
			conflictActive = false
			chromeCoordinator.hideConflictBubble()
			return
		}
		conflictActive = true
		// Clearing `conflictActive` (not just ordering out) is what makes the
		// dismissal stick: live-move repositions re-front the panel while the
		// flag is set. The pool's hourly rate limiter may legitimately
		// re-show it later via `applyConflictBubble`. See
		// `chromeCoordinator.onConflictDismiss` wiring in `init`.
		chromeCoordinator.updateConflictBubble(origin: payload.origin)
		if isPanelShown {
			repositionAndShowConflictBubble()
		}
	}

	func updateIdleEscalationConfig(_ config: IdleEscalationConfig) {
		idleEscalationConfig = config
		scene?.updateIdleEscalationConfig(config)
	}

	func applyAttention(payload: AttentionPayload?, sourceEvent: SourceEvent?) {
		currentSourceEvent = sourceEvent
		guard let payload, !payload.isExpired() else {
			attentionActive = false
			chromeCoordinator.hideAttentionBubble()
			repositionAndShowAnimationBadge()
			return
		}
		attentionActive = true
		// Refresh the chip/pill/session badge first — the bubble no longer
		// hides it (P?? unification: the badge is always visible now, the same
		// way it always was in Minimalist mode), and the bubble's `chipLeadingX`
		// anchor below needs this panel's current frame.
		repositionAndShowAnimationBadge()
		chromeCoordinator.updateAttentionBubble(payload: payload, sourceEvent: sourceEvent)
		if isPanelShown {
			repositionAndShowBubble()
		}
	}

	func applyGateBadge(content: GateBadgeContent?) {
		gateBadgeContent = content
		guard let content else {
			chromeCoordinator.hideGateBadge()
			return
		}
		chromeCoordinator.updateGateBadge(content: content, relativeTo: lastPanelFrame)
		if isPanelShown {
			repositionAndShowGateBadge()
		}
	}

	/// Screen-space x of the platform chip's leading edge: the animation
	/// badge panel's own `minX` (its `outerStack` is leading-aligned and fills
	/// the panel's full width — see the `AnimationBadgeView` alignment note),
	/// not the pet sprite's `minX`. Falls back to the pet frame's own leading
	/// edge before the animation badge panel exists (e.g. the very first tick
	/// after `show`, ordering permitting) rather than crashing/centering.
	private var chipLeadingX: CGFloat {
		chromeCoordinator.animationBadgeLeadingX ?? lastPanelFrame.minX
	}

	/// Screen-space y of the animation badge panel's own bottom edge —
	/// includes the session-label row underneath the chip+pill now that it is
	/// never hidden while the attention bubble shows (P?? unification), unlike
	/// the pet sprite's own `minY`. The attention bubble anchors below this,
	/// not below the pet, or it would land on top of the badge instead of
	/// beneath it. Falls back to the pet frame's own bottom edge before the
	/// animation badge panel exists, same reasoning as `chipLeadingX`.
	private var chromeBottomY: CGFloat {
		chromeCoordinator.animationBadgeBottomY ?? lastPanelFrame.minY
	}

	/// Routes a right-click on chrome that lives in its own floating window
	/// (the SOA gate badge, the platform-chip/activity/session animation
	/// badge) into the same hide/rename/force-idle prompt a click on the pet
	/// sprite itself presents.
	private func presentChromeHidePrompt(anchorInScreen: CGPoint) {
		(panel?.contentView as? FloatingPetInteractionView)?.presentHidePrompt(
			anchorInScreen: anchorInScreen, localPoint: .zero)
	}

	/// Routes a left-click-drag on chrome that lives in its own floating
	/// window (the SOA gate badge, the platform-chip/activity/session
	/// animation badge) into moving the pet panel, exactly as if the user had
	/// grabbed the pet body directly.
	private func beginChromeDrag() {
		(panel?.contentView as? FloatingPetInteractionView)?.beginExternalDrag()
	}

	private func continueChromeDrag() {
		(panel?.contentView as? FloatingPetInteractionView)?.continueExternalDrag()
	}

	private func endChromeDrag() {
		(panel?.contentView as? FloatingPetInteractionView)?.endExternalDrag()
	}

	func applyPlatform(origin: String?) {
		let platform = PlatformAttribution(origin: origin)
		guard platform != currentPlatform else { return }
		currentPlatform = platform
		// Origin can change without the activity state changing (e.g. claude_code
		// idle → cursor idle), so refresh the badge directly here rather than
		// relying on an `apply(state:)` tick.
		repositionAndShowAnimationBadge()
	}

	func applySessionNumber(_ number: Int?) {
		guard currentSessionNumber != number else { return }
		currentSessionNumber = number
		repositionAndShowAnimationBadge()
	}

	func applyHasActiveSession(_ hasActiveSession: Bool) {
		currentHasActiveSession = hasActiveSession
		(panel?.contentView as? FloatingPetInteractionView)?.hasActiveSessionBadge = hasActiveSession
	}

	func applySessionLabel(_ label: String?) {
		guard currentSessionLabel != label else { return }
		currentSessionLabel = label
		(panel?.contentView as? FloatingPetInteractionView)?.currentSessionLabel = label
		repositionAndShowAnimationBadge()
	}

	func applyFoldedSessionDisplay(_ display: String?) {
		(panel?.contentView as? FloatingPetInteractionView)?.foldedSessionDisplay = display
	}

	func applyModeIndicatorBadge(_ text: String?) {
		guard currentModeIndicatorBadge != text else { return }
		currentModeIndicatorBadge = text
		repositionAndShowAnimationBadge()
	}

	func applySessionTooltip(_ summary: String?) {
		guard currentSessionTooltip != summary else { return }
		currentSessionTooltip = summary
		repositionAndShowAnimationBadge()
	}

	func applyRPGState(halfHearts: Int, levelFraction: Double, level: Int, activeMinutes: Int, hudEnabled: Bool) {
		rpgHUDViewModel.onFlash = { [weak self] event in
			guard let self else { return }
			self.hudFlashPending = true
			self.chromeCoordinator.flashHUD(event)
			if event == .levelUp {
				self.scene?.playLevelUpEffect()
			}
		}
		hudFlashPending = false
		// Sickness visuals follow the HUD: under "most recent" mode only the
		// HUD-bearing pet shows them, so a background pet never looks ill with
		// no hearts on screen to explain why.
		let healthLogic = PetConfig.resolvedHealthLogicSettings()
		currentSicknessLevel =
			(hudEnabled && healthLogic.diseaseAnimationsEnabled)
			? SicknessLevel(
				halfHearts: halfHearts,
				mildTriggerHalfHearts: healthLogic.mildSicknessHalfHearts,
				severeTriggerHalfHearts: healthLogic.severeSicknessHalfHearts)
			: .none
		scene?.setSicknessLevel(currentSicknessLevel)
		rpgHUDViewModel.update(
			halfHearts: halfHearts,
			levelFraction: levelFraction,
			level: level,
			activeMinutes: activeMinutes,
			hudEnabled: hudEnabled,
			regenMinutesPerHalfHeart: healthLogic.activityRegenMinutes
		)
		updateGhostPresentation()
		guard isPanelShown else { return }
		guard rpgHUDViewModel.isHUDEnabled else {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			chromeCoordinator.hideHUDImmediately()
			return
		}
		if isHoveringPet || hudForcedVisible {
			showHUDForHover()
		} else if hudFlashPending {
			revealHUDTransiently()
		}
	}

	/// Apply a live change to the HUD-enabled setting (Settings → RPG toggle)
	/// without waiting for the next RPG state poll. Disabling hides the HUD
	/// immediately; enabling restores the normal hover-driven reveal (the HUD
	/// pops back on the next hover, or right away if the pet is hovered).
	func setRPGHUDEnabled(_ enabled: Bool) {
		rpgHUDViewModel.setHUDEnabled(enabled)
		// The tombstone + grayscale are part of the HUD: disabling recolors the pet
		// and drops the tombstone even mid-ghost; re-enabling restores them if ghosted.
		updateGhostPresentation()
		guard isPanelShown else { return }
		guard rpgHUDViewModel.isHUDEnabled else {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			chromeCoordinator.hideHUDImmediately()
			return
		}
		if isHoveringPet || hudForcedVisible {
			showHUDForHover()
		}
	}

	func setHUDDemoActive(_ active: Bool) {
		hudDemoActive = active
		refreshForcedHUDVisibility()
	}

	func setHUDPinned(_ pinned: Bool) {
		hudPinned = pinned
		refreshForcedHUDVisibility()
	}

	/// Reconcile the HUD's pinned/demo "always visible" intent with the panel.
	/// Shows the HUD when either force is active; otherwise lets a non-hovered
	/// HUD fade back to the normal hover-driven behavior.
	private func refreshForcedHUDVisibility() {
		if hudForcedVisible {
			showHUDForHover()
		} else if !isHoveringPet {
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			chromeCoordinator.fadeOutHUD()
		}
	}

	private func handleBubbleDismiss() {
		attentionActive = false
		resetPromptTimer()
		apply(state: .idle, visualMode: currentMode)
		onAttentionDismissed?()
	}

	private func repositionAndShowConflictBubble() {
		chromeCoordinator.repositionConflictBubbleOwn(
			aboveFloatingPetFrame: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
	}

	private func repositionAndShowBubble() {
		chromeCoordinator.repositionAttentionBubble(
			relativeTo: lastPanelFrame,
			leadingX: chipLeadingX,
			bottomAnchorY: chromeBottomY,
			visibleFrame: visibleFrameProvider()
		)
	}

	private func repositionAndShowGateBadge() {
		guard let content = gateBadgeContent else { return }
		chromeCoordinator.repositionGateBadgeOwn(
			content: content,
			relativeTo: lastPanelFrame,
			chipLeadingX: chipLeadingX,
			visibleFrame: visibleFrameProvider()
		)
	}

	/// Apply the 0-HP ghost presentation: grayscale the sprite and show a persistent
	/// tombstone to the right of the pet, or clear both when alive or when the
	/// HUD is disabled (the tombstone + grayscale belong to the RPG HUD).
	/// The sprite grayscale is applied even while hidden so it is correct on the
	/// next show; the tombstone panel is only ordered in while the pet is visible.
	private func updateGhostPresentation() {
		let active = rpgHUDViewModel.showsGhostPresentation
		scene?.setGhosted(active)
		guard isPanelShown, active else {
			chromeCoordinator.hideGhostChrome()
			return
		}
		chromeCoordinator.repositionGhostChrome(
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
		// Revival meter rides alongside the tombstone, gated on the same flag.
		chromeCoordinator.repositionRegenMeter(
			progress: rpgHUDViewModel.reviveProgress,
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
	}

	/// Lazily create the HUD panel and push the latest state + position into
	/// it via the coordinator. Returns whether a refresh happened, so callers
	/// can follow up with a coordinator presentation act (`ensureHUDVisible`,
	/// `fadeInHUD`) — the panel itself never leaves the coordinator.
	private func refreshHUDContent() -> Bool {
		guard rpgHUDViewModel.isHUDEnabled else { return false }
		chromeCoordinator.repositionHUD(
			hearts: rpgHUDViewModel.hearts,
			ringFraction: rpgHUDViewModel.ringFraction,
			level: rpgHUDViewModel.level,
			regenProgress: rpgHUDViewModel.heartRegenProgress,
			showsRegenBar: rpgHUDViewModel.showsHeartRegenBar,
			relativeTo: lastPanelFrame,
			spriteAnchor: currentSpriteAnchorGlobal(),
			visibleFrame: visibleFrameProvider()
		)
		return true
	}

	/// The pet's opaque silhouette in global screen coordinates, used to anchor
	/// the HUD beside the real sprite. `nil` when no sprite is loaded.
	private func currentSpriteAnchorGlobal() -> CGRect? {
		guard let local = scene?.currentSpriteOpaqueRect() else { return nil }
		return local.offsetBy(dx: lastPanelFrame.minX, dy: lastPanelFrame.minY)
	}

	/// Steady reveal while hovering: cancel any transient timer, hold visible.
	/// Skipped mid-drag — an RPG-state poll tick can land while the pointer is
	/// still over the pet (true for the whole drag), and reposition here would
	/// glue the HUD to a stale frame despite the drag's own order-out/guard.
	private func showHUDForHover() {
		guard !isDraggingPet else { return }
		guard isPanelShown, rpgHUDViewModel.isHUDEnabled else { return }
		cancelHUDAutoHide()
		cancelHUDHoverMonitor()
		if refreshHUDContent() { chromeCoordinator.ensureHUDVisible() }
	}

	/// Hover ended: fade out unless a transient reveal is mid-flight, or the
	/// pointer has moved directly onto the HUD panel — in which case arm a monitor
	/// to wait until it leaves both the HUD and the pet frame.
	private func hideHUDForHoverEnd() {
		guard !hudDemoActive else { return }
		guard hudAutoHideWork == nil else { return }
		if chromeCoordinator.isPointInsideHUD(NSEvent.mouseLocation) {
			installHUDHoverMonitor()
			return
		}
		chromeCoordinator.fadeOutHUD()
	}

	/// Brief reveal on an animation moment while not hovering: fade in, then fade
	/// out after `hudTransientSeconds` unless the pointer started hovering.
	/// Skipped mid-drag for the same reason as `showHUDForHover`.
	private func revealHUDTransiently() {
		guard !isDraggingPet else { return }
		guard isPanelShown, rpgHUDViewModel.isHUDEnabled else { return }
		if refreshHUDContent() { chromeCoordinator.fadeInHUD() }
		cancelHUDAutoHide()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.hudAutoHideWork = nil
			if !self.isHoveringPet {
				self.chromeCoordinator.fadeOutHUD()
			}
		}
		hudAutoHideWork = work
		DispatchQueue.main.asyncAfter(
			deadline: .now() + Self.hudTransientSeconds, execute: work)
	}

	private func cancelHUDAutoHide() {
		hudAutoHideWork?.cancel()
		hudAutoHideWork = nil
	}

	private func cancelHUDHoverMonitor() {
		if let monitor = hudHoverMonitor {
			NSEvent.removeMonitor(monitor)
			hudHoverMonitor = nil
		}
	}

	/// Arm a local event monitor that fades the HUD once the pointer exits both
	/// the HUD panel frame and the pet panel frame. Used when hover leaves the pet
	/// but the pointer lands directly on the HUD — the appear trigger is unaffected
	/// (the HUD still only appears on pet-hover or animation flash).
	private func installHUDHoverMonitor() {
		cancelHUDHoverMonitor()
		hudHoverMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.mouseMoved, .leftMouseDragged]
		) { [weak self] event in
			Task { @MainActor in
				guard let self else { return }
				let pt = NSEvent.mouseLocation
				let inHUD = self.chromeCoordinator.isPointInsideHUD(pt)
				let inPet = self.lastPanelFrame.contains(pt)
				guard !inHUD, !inPet else { return }
				self.cancelHUDHoverMonitor()
				if !self.isHoveringPet, !self.hudDemoActive, self.hudAutoHideWork == nil {
					self.chromeCoordinator.fadeOutHUD()
				}
			}
			return event
		}
	}

	private func repositionAndShowAnimationBadge() {
		guard isPanelShown else { return }
		chromeCoordinator.repositionAnimationBadge(
			label: animationBadgeLabel,
			platform: currentPlatform,
			inFlight: animationBadgeInFlight,
			promptTimer: promptTimerPresentationOverride ?? promptTimerStatus?.presentation(),
			sessionNumber: currentSessionNumber,
			sessionLabel: currentSessionLabel,
			sessionTooltip: currentSessionTooltip,
			modeIndicator: currentModeIndicatorBadge,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
	}

	private func syncPromptTimerHeartbeat() {
		guard promptTimerStatus?.isRunning == true else {
			promptTimerHeartbeat?.invalidate()
			promptTimerHeartbeat = nil
			return
		}
		guard promptTimerHeartbeat == nil else { return }
		promptTimerHeartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self else { return }
				self.repositionAndShowAnimationBadge()
				self.syncPromptTimerHeartbeat()
			}
		}
	}

	/// Badge copy: the escalated idle label ("Impatient"/"Frustrated") when the
	/// agent is idle and has escalated, otherwise the current state's label.
	private var animationBadgeLabel: String {
		if currentState == .idle, let escalated = currentEscalation.badgeLabel {
			return escalated
		}
		return currentState.displayLabel
	}

	/// Whether the animation badge label should run the scanning shimmer. Tracks
	/// the underlying activity state: escalated-idle stays `.idle` and so reads
	/// static, while every active working state shimmers. See `ActivityState.isInFlight`.
	private var animationBadgeInFlight: Bool {
		currentState.isInFlight
	}

	func apply(state: ActivityState, visualMode: VisualMode) {
		currentState = state
		currentMode = visualMode
		scene?.update(state: state, visualMode: visualMode)
		// Keep the right-click prompt's "Force Idle" gate in sync with the live
		// state so the escape hatch only appears while the pet is non-idle.
		(panel?.contentView as? FloatingPetInteractionView)?.isForceIdleAvailable =
			FloatingPetHidePrompt.offersForceIdle(for: state)
		// Refresh the animation badge label; no-op while the pet is hidden.
		repositionAndShowAnimationBadge()
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		promptTimerStatus = status
		promptTimerPresentationOverride = nil
		syncPromptTimerHeartbeat()
		repositionAndShowAnimationBadge()
	}

	/// `PoolApply` (P18.04)'s already-rendered equivalent of
	/// `applyPromptTimerStatus`. Stores the presentation as an override so
	/// this and every subsequent same-tick `repositionAndShowAnimationBadge()`
	/// call (from `applyPlatform`, `applySessionNumber`, etc.) renders it
	/// instead of clobbering it with a stale `promptTimerStatus?.presentation()`
	/// — this path is still unwired into the live tick (P18.05), so it
	/// deliberately does not participate in this controller's own
	/// heartbeat-driven ticking (`syncPromptTimerHeartbeat`): once wired,
	/// per-tick redraws come from `PoolDerive` recomputing a fresh
	/// `PromptTimerPresentation` every tick, not from a local `Timer`.
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
		promptTimerPresentationOverride = presentation
		repositionAndShowAnimationBadge()
	}

	private func resetPromptTimer() {
		promptTimerStatus = nil
		promptTimerPresentationOverride = nil
		promptTimerHeartbeat?.invalidate()
		promptTimerHeartbeat = nil
		chromeCoordinator.liveRepositionAnimationBadge(
			label: animationBadgeLabel,
			platform: currentPlatform,
			inFlight: animationBadgeInFlight,
			promptTimer: nil,
			sessionNumber: currentSessionNumber,
			sessionLabel: currentSessionLabel,
			sessionTooltip: currentSessionTooltip,
			modeIndicator: currentModeIndicatorBadge,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
	}

	func setInteraction(_ interaction: FloatingInteraction?) {
		scene?.setInteraction(interaction)
	}

	func decrementIdleEscalation() {
		scene?.decrementIdleEscalation()
	}

	func setFrameChangeHandler(_ handler: @escaping (CGRect) -> Void) {
		frameChangeHandler = handler
		if let view = panel?.contentView as? FloatingPetInteractionView {
			wireFrameHandlers(on: view)
		}
	}

	/// Wire both the live (per-drag-tick) and committed (mouseUp) frame sinks.
	private func wireFrameHandlers(on view: FloatingPetInteractionView) {
		view.liveFrameChangeHandler = { [weak self] frame in
			self?.reanchorChrome(to: frame)
		}
		view.frameChangeHandler = { [weak self] frame in
			self?.handleCommittedFrameChange(frame)
		}
		view.onDragStateChange = { [weak self] dragging in
			self?.setPetDragging(dragging)
		}
	}

	/// Drag begin/end notification from the interaction view. Hides the RPG HUD and
	/// ghost chrome for the duration of a drag (a pure perf win — see `isDraggingPet`)
	/// and restores the correct presentation on mouse-up.
	private func setPetDragging(_ dragging: Bool) {
		guard isDraggingPet != dragging else { return }
		isDraggingPet = dragging
		if dragging {
			// Order the HUD chrome fully out so it stops rendering and re-anchoring.
			cancelHUDAutoHide()
			cancelHUDHoverMonitor()
			chromeCoordinator.hideHUDImmediately()
			chromeCoordinator.hideGhostChrome()
		} else {
			// Restore whatever should be on screen now that the drag has ended.
			updateGhostPresentation()
			if isHoveringPet || hudForcedVisible {
				showHUDForHover()
			}
		}
	}

	/// Live re-anchor: keep `lastPanelFrame` current and glue the attention
	/// bubble to the pet on every drag/resize tick. No persistence — runs hot.
	private func reanchorChrome(to frame: CGRect) {
		lastPanelFrame = frame
		guard isPanelShown else { return }
		// Animation badge first — the bubble's and gate badge's `chipLeadingX`
		// anchor reads this panel's just-updated frame (see the ordering note
		// in `show`).
		chromeCoordinator.liveRepositionAnimationBadge(
			label: animationBadgeLabel,
			platform: currentPlatform,
			inFlight: animationBadgeInFlight,
			sessionNumber: currentSessionNumber,
			sessionLabel: currentSessionLabel,
			sessionTooltip: currentSessionTooltip,
			modeIndicator: currentModeIndicatorBadge,
			relativeTo: lastPanelFrame,
			visibleFrame: visibleFrameProvider()
		)
		if attentionActive {
			chromeCoordinator.liveRepositionAttentionBubble(
				relativeTo: lastPanelFrame,
				leadingX: chipLeadingX,
				bottomAnchorY: chromeBottomY,
				visibleFrame: visibleFrameProvider()
			)
		}
		if conflictActive {
			chromeCoordinator.liveRepositionConflictBubbleOwn(
				aboveFloatingPetFrame: lastPanelFrame,
				visibleFrame: visibleFrameProvider()
			)
		}
		if let content = gateBadgeContent {
			chromeCoordinator.liveRepositionGateBadgeOwn(
				content: content,
				relativeTo: lastPanelFrame,
				chipLeadingX: chipLeadingX,
				visibleFrame: visibleFrameProvider()
			)
		}
		// While dragging the pet, the HUD + ghost chrome are ordered out for perf
		// (see `isDraggingPet`); skip re-anchoring them entirely until mouse-up.
		guard !isDraggingPet else { return }
		// Keep the HUD glued to the pet on non-drag live moves (e.g. resize) while
		// it is visible — steady (hover), pinned (demo), or mid transient reveal.
		if rpgHUDViewModel.isHUDEnabled, isHoveringPet || hudDemoActive || hudAutoHideWork != nil {
			chromeCoordinator.liveRepositionHUD(
				hearts: rpgHUDViewModel.hearts,
				ringFraction: rpgHUDViewModel.ringFraction,
				level: rpgHUDViewModel.level,
				regenProgress: rpgHUDViewModel.heartRegenProgress,
				showsRegenBar: rpgHUDViewModel.showsHeartRegenBar,
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
		}
		// The tombstone is persistent while ghosted — keep it glued to the pet too.
		if rpgHUDViewModel.showsGhostPresentation {
			chromeCoordinator.liveRepositionTombstone(
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
			chromeCoordinator.liveRepositionRegenMeter(
				progress: rpgHUDViewModel.reviveProgress,
				relativeTo: lastPanelFrame,
				spriteAnchor: currentSpriteAnchorGlobal(),
				visibleFrame: visibleFrameProvider()
			)
		}
	}

	/// Committed frame change (mouseUp): re-anchor once more, then forward to the
	/// external persistence handler.
	private func handleCommittedFrameChange(_ frame: CGRect) {
		reanchorChrome(to: frame)
		frameChangeHandler?(frame)
	}

	private func syncSceneSizeToPanel(_ panelSize: CGSize) {
		guard let scene else { return }
		let previous = scene.size
		guard previous != panelSize else { return }
		scene.size = panelSize
	}

	private func makePanel(frame: CGRect) -> NSPanel {
		let panel = NSPanel(
			contentRect: frame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.level = .floating
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		panel.hidesOnDeactivate = false
		panel.isReleasedWhenClosed = false
		panel.ignoresMouseEvents = false
		panel.acceptsMouseMovedEvents = true
		let interactionView = makeContentView(frame: frame, panel: panel)
		interactionView.autoresizingMask = [.width, .height]
		panel.contentView = interactionView
		return panel
	}

	private func makeContentView(frame: CGRect, panel: NSPanel) -> FloatingPetInteractionView {
		let view = FloatingPetInteractionView(
			frame: CGRect(origin: .zero, size: frame.size),
			visibleFrameProvider: { [weak panel, visibleFrameProvider] in
				panel?.screen?.visibleFrame ?? visibleFrameProvider()
			},
			interactionHandler: { [weak self] interaction in
				self?.scene?.setInteraction(interaction)
			},
			sceneSizeHandler: { [weak self] size in
				self?.syncSceneSizeToPanel(size)
			}
		)
		wireFrameHandlers(on: view)
		view.hideFloatingPetHandler = { [weak self] in
			self?.onHideWindowRequested?()
		}
		view.isForceIdleAvailable = FloatingPetHidePrompt.offersForceIdle(for: currentState)
		view.forceIdleHandler = { [weak self] in
			self?.resetPromptTimer()
			self?.onForceIdle?()
		}
		view.hasActiveSessionBadge = currentHasActiveSession
		view.currentSessionLabel = currentSessionLabel
		view.renameHandler = { [weak self] newLabel in
			self?.currentSessionLabel = newLabel
			self?.onRenameRequested?(newLabel)
			self?.repositionAndShowAnimationBadge()
		}
		view.pruneHandler = { [weak self] in
			self?.onPruneRequested?()
		}
		view.syncLabelHandler = { [weak self] in
			self?.onSyncLabelRequested?()
		}
		view.hideAllOtherPetsHandler = { [weak self] in
			self?.onHideAllOtherPetsRequested?()
		}
		view.minimalistModeHandler = { [weak self] in
			self?.onModeSwitchRequested?()
		}
		view.holdDeEscalationHandler = { [weak self] in
			self?.scene?.decrementIdleEscalation()
		}
		view.onHoverChange = { [weak self] isHovering in
			guard let self else { return }
			self.isHoveringPet = isHovering
			if isHovering {
				self.showHUDForHover()
			} else {
				self.hideHUDForHoverEnd()
				self.chromeCoordinator.setHUDRingHovered(false)
			}
		}
		view.onPointerUpdate = { [weak self] in
			guard let self else { return }
			let screenPt = NSEvent.mouseLocation
			self.chromeCoordinator.updateHUDRingHover(at: screenPt)
		}
		return view
	}
}

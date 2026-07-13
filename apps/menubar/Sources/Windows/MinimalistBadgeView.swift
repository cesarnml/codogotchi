import AppKit

/// Content view for the minimalist badge panel: hosts the `AnimationBadgeView`
/// and owns the panel drag. Deliberately knows nothing about the attention
/// bubble — that lives in its own panel.
final class MinimalistBadgeView: NSView {
	/// `fileprivate` (not `private`) so `GateBadgePanel`'s Minimalist-mode
	/// entry point can left-align the ticket/gate badge to the same leading
	/// edge the chip+pill row sits at, rather than centering it on the strip.
	static let hPad: CGFloat = 10
	private static let rowSpacing: CGFloat = 4

	private let animationBadge = AnimationBadgeView(frame: .zero)
	private let sessionBadge = PlatformSessionBadge(frame: .zero)
	private let badgeStack = NSStackView()
	private let outerStack = NSStackView()
	private var currentMetrics = GateBadgeLayout.metrics(scale: 1.0)

	var clampedFrameProvider: ((CGPoint) -> CGRect)?
	/// Fires on every drag step with the live window frame so the controller can
	/// keep the bubble anchored to the badge.
	var onDragMoved: ((CGRect) -> Void)?
	/// Fires once on mouse-up with the final frame for persistence.
	var frameChangeHandler: ((CGRect) -> Void)?
	/// Fires when the user activates the right-click "Hide panel" pill.
	var onHidePanelRequested: (() -> Void)?
	/// Fires when the user double-clicks the platform chip — mirrors Own
	/// mode's `AnimationBadgePanel.onPlatformChipDoubleClick`, forwarded from
	/// the embedded `animationBadge`.
	var onPlatformChipDoubleClick: (() -> Void)? {
		didSet { animationBadge.onPlatformChipDoubleClick = onPlatformChipDoubleClick }
	}
	/// Fires when the user activates the right-click "Force Idle" pill. Only shown
	/// while the badge represents a non-idle activity (see `currentActivity`).
	var onForceIdleRequested: (() -> Void)?
	/// Fires with the trimmed/capped label the user commits via the right-click
	/// "Rename…" affordance. Not fired when the user cancels or commits an
	/// empty/whitespace-only label. Mirrors Own mode's `renameHandler`.
	var renameHandler: ((String) -> Void)?
	/// Fires when the user activates the right-click "Sync Label" affordance,
	/// offered only while a session number is assigned (mirrors Own mode's
	/// `syncLabelHandler`). This view never resolves or writes the label
	/// itself — the caller re-fetches the platform's title and persists it.
	var syncLabelHandler: (() -> Void)?
	/// Fires when the user confirms the right-click "Prune Session"
	/// affordance, offered only while a session number is assigned (same gate
	/// as Sync Label; mirrors Own mode's `pruneHandler`). Not fired when the
	/// user cancels the confirmation alert. This view never destroys session
	/// state itself — the caller routes the prune through the window pool.
	var pruneHandler: (() -> Void)?
	/// Fires when the user activates the right-click "Hide All Other Pets"
	/// affordance, offered unconditionally. This view never touches other
	/// windows itself — the caller (the window pool, via the app-level
	/// wiring) hides every other currently-rendered window.
	var hideAllOtherPetsHandler: (() -> Void)?
	/// Fires when the user activates the right-click "Pet Mode" pill — the
	/// mode-switch back to the full pet renderer. Mirrors Own mode's
	/// `minimalistModeHandler`.
	var onPetModeRequested: (() -> Void)?
	/// Fires on every tick of the "Panel Size" slider with the new
	/// scale; `isFinal` marks the tick ending the drag gesture. Wired by the
	/// controller to live-apply the scale and persist it — this view never
	/// writes config itself.
	var panelSizeHandler: ((Double, Bool) -> Void)?
	/// Current global badge scale, mirrored by the controller's
	/// `applyBadgeScale` so the size pill's slider starts at the live value.
	var currentBadgeScale: Double = 1.0
	/// Latest activity the badge is displaying, mirrored so the right-click prompt
	/// can decide whether to offer "Force Idle".
	private var currentActivity: ActivityState = .idle
	private var dragOffsetInScreen: CGPoint?

	private var hidePromptPanel: FloatingPetHidePromptPanel?
	private let hidePromptDismissal = FloatingPetPromptDismissal()

	private var sizePillPanel: MinimalistPanelSizePillPanel?
	private let sizePillDismissal = FloatingPetPromptDismissal()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		buildUI()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	deinit {
		hidePromptDismissal.uninstall()
		sizePillDismissal.uninstall()
	}

	func configureBadge(
		platform: PlatformAttribution?,
		activity: ActivityState,
		metrics: GateBadgeLayout.Metrics
	) {
		currentActivity = activity
		currentMetrics = metrics
		animationBadge.configure(
			text: activity.displayLabel,
			platform: platform,
			inFlight: activity.isInFlight,
			promptTimer: promptTimerStatus?.presentation(),
			metrics: metrics
		)
		sessionBadge.configure(
			number: currentSessionNumber, label: currentSessionLabel, tooltip: currentSessionTooltip,
			metrics: metrics)
		syncPromptTimerHeartbeat()
	}

	func applyPromptTimerStatus(_ status: PromptTimerStatus?) {
		promptTimerStatus = status
		animationBadge.configurePromptTimer(status?.presentation())
		syncPromptTimerHeartbeat()
	}

	/// `PoolApply` (P18.04)'s already-rendered equivalent of
	/// `applyPromptTimerStatus`: forwards `presentation` straight to
	/// `animationBadge.configurePromptTimer(_:)` — the same renderer call
	/// `applyPromptTimerStatus` makes after deriving a presentation from its
	/// raw `PromptTimerStatus` — without re-deriving anything, since only the
	/// rendered label/isRunning pair is available here. Deliberately does
	/// not touch `promptTimerStatus`/the heartbeat: this path is still
	/// unwired into the live tick (P18.05); once wired, ticking comes from
	/// `PoolDerive` recomputing a fresh presentation every tick rather than
	/// this view's local `Timer`.
	func applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?) {
		animationBadge.configurePromptTimer(presentation)
	}

	func resetPromptTimer() {
		promptTimerStatus = nil
		promptTimerHeartbeat?.invalidate()
		promptTimerHeartbeat = nil
		animationBadge.configurePromptTimer(nil)
	}

	/// Latest session number/label/tooltip applied via `configureSessionNumber`.
	/// Mirrored so a later `configureBadge` (metrics/activity refresh) can
	/// re-apply them without the caller having to resend them every tick.
	private var currentSessionNumber: Int?
	/// User-set rename label for this session (P15.06), or `nil` to fall back
	/// to "Session N". Also prefills the rename alert's text field.
	private var currentSessionLabel: String?
	private var currentSessionTooltip: String?
	/// Latest prompt-timer status pushed by the pool (which owns the tracker —
	/// see `PromptTimerTracker`). This view only renders it; the heartbeat
	/// recomputes the label each second while the status reports running.
	private var promptTimerStatus: PromptTimerStatus?
	private var promptTimerHeartbeat: Timer?

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
				self.animationBadge.configurePromptTimer(self.promptTimerStatus?.presentation())
				self.syncPromptTimerHeartbeat()
				self.layoutSubtreeIfNeeded()
			}
		}
	}

	/// Shows/hides and labels the session badge row. A session-keyed window
	/// (`number` non-`nil`) shows "Session N" unless renamed; a plain-origin/
	/// combined window (`number` `nil`) now also shows a badge — the pool's
	/// platform-name default, or the user's rename — via `label` (P??
	/// unification). The row hides only when both are `nil`.
	func configureSessionNumber(_ number: Int?, label: String? = nil, tooltip: String? = nil) {
		currentSessionNumber = number
		currentSessionLabel = label
		currentSessionTooltip = tooltip
		sessionBadge.configure(number: number, label: label, tooltip: tooltip, metrics: currentMetrics)
	}

	/// Width the badge content needs plus horizontal padding. When the session
	/// row is visible, the wider of the two rows drives the panel width.
	var badgePreferredWidth: CGFloat {
		var width = animationBadge.preferredSize.width
		if !sessionBadge.isHidden {
			width = max(width, sessionBadge.intrinsicContentSize.width)
		}
		return width + Self.hPad * 2
	}

	// MARK: - Drag

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		dismissHidePrompt()
		dismissSizePill()
		let point = NSEvent.mouseLocation
		dragOffsetInScreen = CGPoint(
			x: point.x - window.frame.origin.x,
			y: point.y - window.frame.origin.y
		)
	}

	override func mouseDragged(with event: NSEvent) {
		guard let window, let dragOffsetInScreen else { return }
		let point = NSEvent.mouseLocation
		let origin = CGPoint(
			x: point.x - dragOffsetInScreen.x,
			y: point.y - dragOffsetInScreen.y
		)
		let frame = clampedFrameProvider?(origin) ?? CGRect(origin: origin, size: window.frame.size)
		window.setFrame(frame, display: true)
		onDragMoved?(frame)
	}

	override func mouseUp(with event: NSEvent) {
		dragOffsetInScreen = nil
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
	}

	// MARK: - External drag (chrome living in its own floating window)

	/// `fileprivate` (not `private`) so `GateBadgePanel` — the SOA ticket/gate
	/// badge, its own floating window stacked above this strip — can route a
	/// left-click-drag on itself into moving this strip, exactly as if the
	/// user had grabbed the strip directly. Mirrors `mouseDown`/`mouseDragged`/
	/// `mouseUp` above verbatim, reading `NSEvent.mouseLocation` (screen space,
	/// window-independent) the same way those do, rather than a point handed
	/// in from the other window's own event.
	func beginExternalDrag() {
		guard let window else { return }
		dismissHidePrompt()
		dismissSizePill()
		let point = NSEvent.mouseLocation
		dragOffsetInScreen = CGPoint(
			x: point.x - window.frame.origin.x,
			y: point.y - window.frame.origin.y
		)
	}

	func continueExternalDrag() {
		guard let window, let dragOffsetInScreen else { return }
		let point = NSEvent.mouseLocation
		let origin = CGPoint(
			x: point.x - dragOffsetInScreen.x,
			y: point.y - dragOffsetInScreen.y
		)
		let frame = clampedFrameProvider?(origin) ?? CGRect(origin: origin, size: window.frame.size)
		window.setFrame(frame, display: true)
		onDragMoved?(frame)
	}

	func endExternalDrag() {
		dragOffsetInScreen = nil
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
	}

	// MARK: - Hide-panel affordance

	/// Right-click anywhere on the badge (platform chip or activity pill) surfaces
	/// the same frosted "Hide" pill Own mode uses, retitled "Hide panel" since it
	/// hides the whole minimalist strip.
	override func rightMouseDown(with event: NSEvent) {
		guard let window else { return }
		if hidePromptPanel != nil {
			dismissHidePrompt()
		}
		presentHidePrompt(anchorInScreen: window.convertPoint(toScreen: event.locationInWindow))
	}

	func dismissHidePromptIfPresent() {
		dismissHidePrompt()
		dismissSizePill()
	}

	/// `fileprivate` (not `private`) so `GateBadgePanel` can route a right-click
	/// on the SOA ticket/gate badge — a separate floating window stacked above
	/// this strip — into the same prompt a click on the strip itself presents.
	func presentHidePrompt(anchorInScreen: CGPoint) {
		guard let window else { return }
		dismissHidePrompt()
		dismissSizePill()
		let capabilities = FloatingPetPromptCapabilities(
			offersForceIdle: FloatingPetHidePrompt.offersForceIdle(for: currentActivity),
			sessionLabel: currentSessionLabel,
			hasActiveSession: currentSessionNumber != nil,
			modeSwitchTitle: FloatingPetHidePrompt.petModeTitle,
			offersPanelSize: true,
			hideItemTitle: FloatingPetHidePrompt.panelTitle
		)
		let handlers = FloatingPetPromptHandlers(
			forceIdle: { [weak self] in
				self?.dismissHidePrompt()
				self?.onForceIdleRequested?()
			},
			rename: { [weak self] in
				self?.dismissHidePrompt()
				self?.presentRenameAlert()
			},
			syncLabel: { [weak self] in
				self?.dismissHidePrompt()
				self?.syncLabelHandler?()
			},
			prune: { [weak self] in
				self?.dismissHidePrompt()
				self?.presentPruneConfirmation()
			},
			modeSwitch: { [weak self] in
				self?.dismissHidePrompt()
				self?.onPetModeRequested?()
			},
			panelSize: { [weak self] in
				self?.dismissHidePrompt()
				self?.presentPanelSizePill()
			},
			hideAllOtherPets: { [weak self] in
				self?.dismissHidePrompt()
				self?.hideAllOtherPetsHandler?()
			},
			hideThis: { [weak self] in
				self?.dismissHidePrompt()
				self?.onHidePanelRequested?()
			}
		)
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: handlers)
		let promptSize = FloatingPetHidePrompt.stackSize(titles: items.map(\.title))
		let visibleFrame = window.screen?.visibleFrame
			?? NSScreen.main?.visibleFrame
			?? CGRect(x: 0, y: 0, width: 800, height: 600)
		let screenFrame = FloatingPetHidePrompt.screenFrame(
			anchor: anchorInScreen,
			promptSize: promptSize,
			visibleFrame: visibleFrame
		)
		let panel = FloatingPetHidePromptPanel(frame: screenFrame, items: items)
		panel.orderFrontRegardless()
		hidePromptPanel = panel
		hidePromptDismissal.install(owner: self, panel: panel) { [weak self] in
			self?.dismissHidePrompt()
		}
	}

	/// Presents a modal text-entry alert for renaming this session. Trims and
	/// caps the result at `SessionLabelStore.maxLength`; an empty/whitespace
	/// result (or Cancel) is treated as "no rename" and `renameHandler` is not
	/// fired. Mirrors Own mode's `presentRenameAlert`.
	private func presentRenameAlert() {
		let alert = NSAlert()
		alert.messageText = "Rename Session"
		alert.informativeText = "Up to \(SessionLabelStore.maxLength) characters."
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")
		let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = currentSessionLabel ?? ""
		alert.accessoryView = field
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let normalized = SessionLabelStore.normalize(field.stringValue)
		guard !normalized.isEmpty else { return }
		renameHandler?(normalized)
	}

	/// Presents a destructive-action confirmation alert for pruning this
	/// session. `pruneHandler` fires only when the user confirms; Cancel is a
	/// no-op, matching the rename alert's "no commit on cancel" contract.
	/// Skipped entirely once the user has checked "Do not show this warning
	/// again." on a prior confirmation (`features.skip_prune_confirmation`) —
	/// pruning a slice is cheap to recover from (regenerated on the next
	/// activity transition, or by another prompt), so this alert only exists
	/// to catch accidental clicks, not to gate a truly destructive action.
	/// Mirrors Own mode's `presentPruneConfirmation`.
	private func presentPruneConfirmation() {
		guard !PetConfig.resolvedSkipPruneConfirmation() else {
			pruneHandler?()
			return
		}
		let alert = NSAlert()
		alert.messageText = "Prune Session"
		alert.informativeText =
			"This destroys the panel and its session data. This cannot be undone."
		alert.addButton(withTitle: "Prune")
		alert.addButton(withTitle: "Cancel")
		alert.buttons.first?.hasDestructiveAction = true
		let skipCheckbox = NSButton(
			checkboxWithTitle: "Do not show this warning again.", target: nil, action: nil)
		skipCheckbox.state = .off
		alert.accessoryView = skipCheckbox
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		if skipCheckbox.state == .on {
			try? PetConfig.write(skipPruneConfirmation: true, to: PetConfig.configURL())
		}
		pruneHandler?()
	}

	// MARK: - Panel Size pill

	/// Presents the "Panel Size" slider pill just below the strip,
	/// left-aligned with the session-label row (which shares the chip row's
	/// leading edge — `outerStack` is leading-aligned at `hPad`). The slider
	/// starts at the live global scale (`currentBadgeScale`) and streams ticks
	/// through `panelSizeHandler`; the pill stays up through the whole drag
	/// gesture — the slider lives inside the pill, so the outside-click
	/// dismissal below never sees it — and dismisses on any click away,
	/// keyboard input, or app switch, mirroring the hide prompt's dismissal
	/// contract.
	private func presentPanelSizePill() {
		guard let window else { return }
		dismissSizePill()
		let visibleFrame = window.screen?.visibleFrame
			?? NSScreen.main?.visibleFrame
			?? CGRect(x: 0, y: 0, width: 800, height: 600)
		let pillSize = MinimalistPanelSizePill.size
		// Below the strip, clamped so the pill never leaves the visible frame
		// (falling back to on-screen positions when the strip sits at an edge).
		let proposed = CGPoint(
			x: window.frame.minX + Self.hPad,
			y: window.frame.minY - MinimalistPanelSizePill.gapBelowStrip - pillSize.height
		)
		let screenFrame = CGRect(
			x: max(visibleFrame.minX, min(visibleFrame.maxX - pillSize.width, proposed.x)),
			y: max(visibleFrame.minY, min(visibleFrame.maxY - pillSize.height, proposed.y)),
			width: pillSize.width,
			height: pillSize.height
		)
		let pill = MinimalistPanelSizePillPanel(frame: screenFrame, initialScale: currentBadgeScale)
		pill.onScaleChanged = { [weak self] scale, isFinal in
			self?.currentBadgeScale = scale
			self?.panelSizeHandler?(scale, isFinal)
		}
		pill.orderFrontRegardless()
		sizePillPanel = pill
		sizePillDismissal.install(owner: self, panel: pill) { [weak self] in
			self?.dismissSizePill()
		}
	}

	private func dismissSizePill() {
		guard sizePillPanel != nil else { return }
		sizePillDismissal.uninstall()
		sizePillPanel?.orderOut(nil)
		sizePillPanel = nil
	}

	private func dismissHidePrompt() {
		hidePromptDismissal.uninstall()
		guard hidePromptPanel != nil else { return }
		hidePromptPanel?.orderOut(nil)
		hidePromptPanel = nil
	}

	// MARK: - Layout

	private func buildUI() {
		wantsLayer = true
		badgeStack.orientation = .horizontal
		badgeStack.alignment = .centerY
		badgeStack.spacing = 8
		badgeStack.addArrangedSubview(animationBadge)

		sessionBadge.isHidden = true

		outerStack.orientation = .vertical
		// `.leading` (not `.centerX`) keeps the chip+pill row pinned at `hPad` from
		// the panel's left edge regardless of the session badge row's width — see
		// the matching note on `AnimationBadgeView.outerStack`.
		outerStack.alignment = .leading
		outerStack.spacing = Self.rowSpacing
		outerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(outerStack)
		outerStack.addArrangedSubview(badgeStack)
		outerStack.addArrangedSubview(sessionBadge)
		NSLayoutConstraint.activate([
			outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
			outerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.hPad),
			outerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}
}


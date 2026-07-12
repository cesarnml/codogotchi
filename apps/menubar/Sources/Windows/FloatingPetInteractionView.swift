import AppKit
import SpriteKit

final class FloatingPetInteractionView: NSView {
	private enum ActiveInteraction {
		case drag(grabOffsetInScreen: CGPoint)
		case resize(startFrame: CGRect, startScreenPoint: CGPoint)
	}

	private static let trackingKindBounds = "bounds"
	private static let trackingKindAffordance = "affordance"

	private let skView = SKView(frame: .zero)
	private let overlayView = FloatingPetOverlayView(frame: .zero)
	private let visibleFrameProvider: () -> CGRect
	private let interactionHandler: (FloatingInteraction?) -> Void
	private let sceneSizeHandler: (CGSize) -> Void
	private var activeInteraction: ActiveInteraction?
	private var lastEmittedInteraction: FloatingInteraction?
	private var holdTimer: Timer?
	private var boundsTrackingArea: NSTrackingArea?
	private var affordanceTrackingArea: NSTrackingArea?
	private var lastTrackingBoundsSize: CGSize = .zero
	private var lastLayoutBoundsSize: CGSize = .zero
	private var isReconfiguringTracking = false
	private var resizeCursorPushed = false
	private var localMouseMonitor: Any?
	private let promptDismissal = FloatingPetPromptDismissal()
	private var pointerInsideFrame = false
	private var affordanceHoverActive = false
	private var hidePromptPanel: FloatingPetHidePromptPanel?
	var frameChangeHandler: ((CGRect) -> Void)?
	/// Fired on every in-flight drag/resize tick (not just mouseUp) so attached
	/// chrome (the attention bubble) can re-anchor live. Must stay cheap — it
	/// runs per `mouseDragged`; persistence stays on `frameChangeHandler`.
	var liveFrameChangeHandler: ((CGRect) -> Void)?
	/// Fired when a pet drag begins (`true`) and ends (`false`). Lets the panel
	/// suppress the RPG HUD + ghost chrome for the duration of the drag. Resize
	/// drags do not fire this — only translation of the pet body.
	var onDragStateChange: ((Bool) -> Void)?
	/// Fired when the user holds a stationary click on the pet body for ≥5 s.
	var holdDeEscalationHandler: (() -> Void)?
	var hideFloatingPetHandler: (() -> Void)?
	/// Fired when the user activates the right-click "Force Idle" pill. Only
	/// offered while `isForceIdleAvailable` (the pet is not idle).
	var forceIdleHandler: (() -> Void)?
	/// Whether the right-click prompt should offer "Force Idle". Kept in sync by
	/// the controller from the latest applied `ActivityState`.
	var isForceIdleAvailable = false
	/// Whether this window currently holds a session number (P15.06). Gates
	/// only the right-click "Prune Session" affordance — pruning destroys
	/// backing session state, so it stays restricted to an actual
	/// session-keyed window. Rename is gated separately, on
	/// `currentSessionLabel` (see below), now that a plain-origin/combined
	/// window shows a label (and can be renamed) too. Kept in sync by the
	/// controller from the latest applied session number.
	var hasActiveSessionBadge = false
	/// This window's current session-label badge text, if any — a
	/// session-keyed window's own "Session N" default or rename, or a
	/// plain-origin/combined window's platform-name default or rename (P??
	/// unification). `nil` only when the badge is hidden entirely. Prefills
	/// the rename alert's text field and gates whether "Rename…" is offered.
	var currentSessionLabel: String?
	/// Fired with the trimmed/capped label the user commits via the
	/// right-click "Rename" affordance. Not fired when the user cancels or
	/// commits an empty/whitespace-only label.
	var renameHandler: ((String) -> Void)?
	/// Fired when the user confirms the right-click "Prune Session" affordance
	/// (P15.07). Not fired if the user cancels the confirmation alert. Only
	/// offered while `hasActiveSessionBadge` — see that property's doc for why
	/// this gate differs from Rename's.
	var pruneHandler: (() -> Void)?
	/// Fired when the user activates the right-click "Sync Label" affordance.
	/// Only offered while `hasActiveSessionBadge` (same gate as Prune, unlike
	/// Rename) — a plain-origin/combined window has no session id to
	/// re-fetch a platform title for. This view never resolves or writes the
	/// label itself.
	var syncLabelHandler: (() -> Void)?
	/// Fired when the user activates the right-click "Hide All Other Pets"
	/// affordance, offered unconditionally. This view never touches other
	/// windows itself — the app wires this to the pool's bulk-hide call.
	var hideAllOtherPetsHandler: (() -> Void)?
	/// Fired when the user activates the right-click "Minimalist Mode"
	/// affordance. The app wires this to persist the mode switch to
	/// customization.json; the window pool re-renders on its next tick.
	var minimalistModeHandler: (() -> Void)?
	/// Fired when the pointer enters or leaves the pet frame. `true` = entered.
	var onHoverChange: ((Bool) -> Void)?
	/// Fired on every pointer event while tracking (moved, entered, exited).
	var onPointerUpdate: (() -> Void)?

	init(
		frame: CGRect,
		visibleFrameProvider: @escaping () -> CGRect,
		interactionHandler: @escaping (FloatingInteraction?) -> Void,
		sceneSizeHandler: @escaping (CGSize) -> Void
	) {
		self.visibleFrameProvider = visibleFrameProvider
		self.interactionHandler = interactionHandler
		self.sceneSizeHandler = sceneSizeHandler
		super.init(frame: frame)

		autoresizingMask = [.width, .height]
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		skView.allowsTransparency = true
		skView.ignoresSiblingOrder = true
		skView.autoresizingMask = [.width, .height]
		skView.wantsLayer = true
		skView.layer?.zPosition = 0
		addSubview(skView)
		overlayView.autoresizingMask = [.width, .height]
		overlayView.wantsLayer = true
		overlayView.layer?.zPosition = 20
		addSubview(overlayView, positioned: .above, relativeTo: skView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		nil
	}

	func presentScene(_ scene: SKScene) {
		skView.presentScene(scene)
		elevateOverlayAboveSpriteKit()
	}

	func setSpriteKitPaused(_ paused: Bool) {
		skView.isPaused = paused
	}

	/// Re-arm mouse-move tracking and sync affordance visibility after the panel
	/// is shown or its frame changes outside an in-flight drag.
	func prepareForDisplay() {
		window?.acceptsMouseMovedEvents = true
		installLocalMouseMonitorIfNeeded()
		reconfigureTrackingAreasIfNeeded(force: true)
		syncPointerState(reason: "prepareForDisplay")
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil {
			prepareForDisplay()
		} else {
			dismissHidePrompt()
			removeLocalMouseMonitor()
		}
	}

	deinit {
		removeLocalMouseMonitor()
		promptDismissal.uninstall()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		reconfigureTrackingAreasIfNeeded(force: false)
	}

	override var isFlipped: Bool { false }

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard bounds.contains(point) else { return nil }
		return self
	}

	override func layout() {
		super.layout()
		skView.frame = bounds
		overlayView.frame = bounds
		let sizeChanged = bounds.size != lastLayoutBoundsSize
		lastLayoutBoundsSize = bounds.size
		if sizeChanged {
			sceneSizeHandler(bounds.size)
			reconfigureTrackingAreasIfNeeded(force: false)
		}
		elevateOverlayAboveSpriteKit()
		// Translate drags only move origin; skip pointer/tracking churn each frame.
		if activeInteraction == nil || isResizing {
			syncPointerState(reason: "layout")
		}
	}

	override func mouseMoved(with event: NSEvent) {
		handlePointerEvent(at: convert(event.locationInWindow, from: nil), reason: "mouseMoved")
	}

	override func mouseEntered(with event: NSEvent) {
		let kind = event.trackingArea?.userInfo?["kind"] as? String
		let localPoint = convert(event.locationInWindow, from: nil)
		if kind == Self.trackingKindAffordance {
			affordanceHoverActive = true
		}
		handlePointerEvent(at: localPoint, reason: "mouseEntered(\(kind ?? "bounds"))")
	}

	override func mouseExited(with event: NSEvent) {
		guard !isReconfiguringTracking else {
			return
		}
		let kind = event.trackingArea?.userInfo?["kind"] as? String
		if kind == Self.trackingKindAffordance {
			affordanceHoverActive = false
		}
		// Do NOT pre-assign pointerInsideFrame = false here. handlePointerEvent
		// owns all reads and writes of pointerInsideFrame so the wasInBounds delta
		// check fires correctly and onHoverChange?(false) propagates to the HUD.
		handlePointerEvent(
			at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil),
			reason: "mouseExited(\(kind ?? "bounds"))"
		)
	}

	override func rightMouseDown(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		let shouldPresent = FloatingPetHidePrompt.shouldPresent(
			at: localPoint,
			in: bounds,
			hasActivePointerInteraction: activeInteraction != nil
		)
		guard shouldPresent else {
			dismissHidePrompt()
			return
		}
		presentHidePrompt(anchorInScreen: screenLocation(for: event), localPoint: localPoint)
	}

	override func mouseDown(with event: NSEvent) {
		guard let window else { return }
		let localPoint = convert(event.locationInWindow, from: nil)
		if hidePromptPanel != nil {
			dismissHidePrompt()
		}
		let startScreenPoint = NSEvent.mouseLocation
		switch FloatingInteractionPolicy.hitTest(point: localPoint, in: bounds) {
		case .dragRegion:
			let clickInScreen = screenLocation(for: event)
			let grabOffset = CGPoint(
				x: clickInScreen.x - window.frame.origin.x,
				y: clickInScreen.y - window.frame.origin.y
			)
			activeInteraction = .drag(grabOffsetInScreen: grabOffset)
			overlayView.showsResizeAffordance = false
			onDragStateChange?(true)
			emitInteraction(
				FloatingInteractionPolicy.clickInteraction(hitTarget: .dragRegion),
				reason: "mouseDown-click"
			)
			startHoldTimer()
		case .resizeAffordance:
			activeInteraction = .resize(startFrame: window.frame, startScreenPoint: startScreenPoint)
			pushResizeCursor()
			handlePointerEvent(at: localPoint, reason: "mouseDown-resize")
		}
	}

	override func mouseDragged(with event: NSEvent) {
		// Intentionally does NOT cancel the hold timer: any continuous click-hold
		// on the pet body de-escalates after 5 s, whether the user holds still
		// (jumping) or drags (running-left/right). The timer is only cancelled on
		// mouseUp. Resize never arms the timer, so dragging the affordance is a
		// no-op here.
		guard let window, let activeInteraction else { return }
		let currentPoint = NSEvent.mouseLocation
		let nextFrame: CGRect
		let hitTarget: FloatingInteractionHitTarget

		switch activeInteraction {
		case let .drag(grabOffsetInScreen):
			let stepDelta = CGSize(width: event.deltaX, height: event.deltaY)
			hitTarget = .dragRegion
			let mouseInScreen = screenLocation(for: event)
			let before = window.frame
			nextFrame = FloatingInteractionPolicy.draggedFrame(
				mouseLocationInScreen: mouseInScreen,
				grabOffsetInScreen: grabOffsetInScreen,
				windowSize: before.size,
				visibleFrame: visibleFrameProvider()
			)
			applyPanelFrame(nextFrame, isTranslate: true)
			let interaction = FloatingInteractionPolicy.interaction(
				forStepDelta: stepDelta,
				hitTarget: hitTarget,
				previous: lastEmittedInteraction
			)
			emitInteraction(interaction, reason: "mouseDragged-\(hitTarget)")
			return
		case let .resize(startFrame, startScreenPoint):
			let rawDelta = CGSize(
				width: currentPoint.x - startScreenPoint.x,
				height: currentPoint.y - startScreenPoint.y
			)
			hitTarget = .resizeAffordance
			nextFrame = FloatingInteractionPolicy.resizedFrame(
				from: startFrame,
				dragDelta: rawDelta,
				visibleFrame: visibleFrameProvider()
			)
			applyPanelFrame(nextFrame, isTranslate: false)
			let stepDelta = CGSize(width: event.deltaX, height: event.deltaY)
			let interaction = FloatingInteractionPolicy.interaction(
				forStepDelta: stepDelta,
				hitTarget: hitTarget,
				previous: lastEmittedInteraction
			)
			emitInteraction(interaction, reason: "mouseDragged-\(hitTarget)")
		}
	}

	override func mouseUp(with event: NSEvent) {
		cancelHoldTimer()
		let wasResizing = isResizing
		let wasDragging = isTranslating
		window?.displayIfNeeded()
		activeInteraction = nil
		if wasDragging { onDragStateChange?(false) }
		emitInteraction(nil, reason: "mouseUp-clear")
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
		popResizeCursorIfNeeded()
		let localPoint = convert(event.locationInWindow, from: nil)
		handlePointerEvent(at: localPoint, reason: wasResizing ? "mouseUp-resize" : "mouseUp")
	}

	override func cursorUpdate(with event: NSEvent) {
		applyAffordanceCursor(for: convert(event.locationInWindow, from: nil))
	}

	// MARK: - External drag (chrome living in its own floating window)

	/// `fileprivate` (not `private`) so `GateBadgePanel`/`AnimationBadgePanel`
	/// — the SOA badge and chip/pill/session badge, each its own floating
	/// window — can route a left-click-drag on themselves into moving this
	/// panel, exactly as if the user had grabbed the pet body directly.
	/// Deliberately skips the sprite-interaction feedback (`emitInteraction`,
	/// the hold-to-de-escalate timer, resize-affordance hiding) `mouseDown`/
	/// `mouseDragged`/`mouseUp` drive for a direct pet-body drag — those are
	/// specific to touching the sprite itself, not its surrounding chrome.
	func beginExternalDrag() {
		guard let window else { return }
		dismissHidePrompt()
		let screenPoint = NSEvent.mouseLocation
		let grabOffset = CGPoint(
			x: screenPoint.x - window.frame.origin.x,
			y: screenPoint.y - window.frame.origin.y
		)
		activeInteraction = .drag(grabOffsetInScreen: grabOffset)
		overlayView.showsResizeAffordance = false
		onDragStateChange?(true)
	}

	func continueExternalDrag() {
		guard let window, case let .drag(grabOffsetInScreen)? = activeInteraction else { return }
		let nextFrame = FloatingInteractionPolicy.draggedFrame(
			mouseLocationInScreen: NSEvent.mouseLocation,
			grabOffsetInScreen: grabOffsetInScreen,
			windowSize: window.frame.size,
			visibleFrame: visibleFrameProvider()
		)
		applyPanelFrame(nextFrame, isTranslate: true)
	}

	func endExternalDrag() {
		guard isTranslating else { return }
		window?.displayIfNeeded()
		activeInteraction = nil
		onDragStateChange?(false)
		if let frame = window?.frame {
			frameChangeHandler?(frame)
		}
	}

	private var isResizing: Bool {
		if case .resize = activeInteraction { return true }
		return false
	}

	private func startHoldTimer() {
		holdTimer?.invalidate()
		// Repeats so a sustained hold steps down one level every 5 s ("5 s for
		// each bump"). Added in `.common` mode rather than scheduled in `.default`
		// so it keeps firing while a drag puts the run loop in event-tracking mode.
		let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
			self?.holdDeEscalationHandler?()
		}
		RunLoop.main.add(timer, forMode: .common)
		holdTimer = timer
	}

	private func cancelHoldTimer() {
		holdTimer?.invalidate()
		holdTimer = nil
	}

	private var isTranslating: Bool {
		if case .drag = activeInteraction { return true }
		return false
	}

	/// Screen location for the event cursor, using the window's base coordinate
	/// system so it stays consistent with `NSWindow.frame` (bottom-left screen).
	private func screenLocation(for event: NSEvent) -> CGPoint {
		guard let window else { return NSEvent.mouseLocation }
		return window.convertPoint(toScreen: event.locationInWindow)
	}

	private func applyPanelFrame(_ frame: CGRect, isTranslate: Bool) {
		guard let window else { return }
		let before = window.frame
		guard frame != before else { return }

		if isTranslate, frame.size == before.size {
			window.setFrameOrigin(frame.origin)
		} else {
			window.setFrame(frame, display: false)
		}

		if frame.size != before.size {
			sceneSizeHandler(frame.size)
		}

		// Re-anchor attached chrome (attention bubble) live, every tick. Cheap
		// in-memory reposition only; state persistence stays on mouseUp.
		liveFrameChangeHandler?(frame)
	}

	private func elevateOverlayAboveSpriteKit() {
		addSubview(overlayView, positioned: .above, relativeTo: skView)
	}

	private func installLocalMouseMonitorIfNeeded() {
		guard localMouseMonitor == nil else { return }
		localMouseMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [
				.mouseMoved,
				.leftMouseDragged,
				.leftMouseUp,
				.leftMouseDown,
				.rightMouseDown,
			]
		) { [weak self] event in
			guard let self, let window = self.window, event.window === window else { return event }
			let localPoint = self.convert(event.locationInWindow, from: nil)
			if self.hidePromptPanel != nil {
				switch event.type {
				case .leftMouseDown, .rightMouseDown:
					self.dismissHidePrompt()
				default:
					break
				}
			}
			// `mouseDragged` on this view already moves the panel; skip duplicate overlay work.
			if self.isTranslating, event.type == .leftMouseDragged {
				return event
			}
			self.handlePointerEvent(at: localPoint, reason: "localMonitor-\(event.type.rawValue)")
			return event
		}
	}

	/// `fileprivate` (not `private`) so `GateBadgePanel`/`AnimationBadgePanel`
	/// can route a right-click on the chip/pill/session-badge/SOA-badge chrome
	/// into the same prompt the pet sprite itself presents — see
	/// `FloatingPetPanelController`'s badge-panel wiring.
	func presentHidePrompt(anchorInScreen: CGPoint, localPoint: CGPoint) {
		dismissHidePrompt()
		guard let window else { return }
		let capabilities = FloatingPetPromptCapabilities(
			offersForceIdle: isForceIdleAvailable,
			sessionLabel: currentSessionLabel,
			hasActiveSession: hasActiveSessionBadge,
			modeSwitchTitle: FloatingPetHidePrompt.minimalistModeTitle,
			offersPanelSize: false,
			hideItemTitle: FloatingPetHidePrompt.title
		)
		let handlers = FloatingPetPromptHandlers(
			forceIdle: { [weak self] in
				self?.dismissHidePrompt()
				self?.forceIdleHandler?()
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
				self?.minimalistModeHandler?()
			},
			panelSize: {},
			hideAllOtherPets: { [weak self] in
				self?.dismissHidePrompt()
				self?.hideAllOtherPetsHandler?()
			},
			hideThis: { [weak self] in
				self?.dismissHidePrompt()
				self?.hideFloatingPetHandler?()
			}
		)
		let items = FloatingPetPromptBuilder.items(capabilities: capabilities, handlers: handlers)
		let promptSize = FloatingPetHidePrompt.stackSize(titles: items.map(\.title))
		let visibleFrame = window.screen?.visibleFrame ?? visibleFrameProvider()
		let screenFrame = FloatingPetHidePrompt.screenFrame(
			anchor: anchorInScreen,
			promptSize: promptSize,
			visibleFrame: visibleFrame
		)
		let panel = FloatingPetHidePromptPanel(frame: screenFrame, items: items)
		panel.orderFrontRegardless()
		hidePromptPanel = panel
		promptDismissal.install(owner: self, panel: panel) { [weak self] in
			self?.dismissHidePrompt()
		}
	}

	/// Presents a modal text-entry alert for renaming this session. Trims and
	/// caps the result at `SessionLabelStore.maxLength`; an empty/whitespace
	/// result (or Cancel) is treated as "no rename" and `renameHandler` is not
	/// fired.
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

	func dismissHidePromptIfPresent() {
		dismissHidePrompt()
	}

	private func dismissHidePrompt() {
		promptDismissal.uninstall()
		hidePromptPanel?.orderOut(nil)
		hidePromptPanel = nil
	}

	private func removeLocalMouseMonitor() {
		guard let localMouseMonitor else { return }
		NSEvent.removeMonitor(localMouseMonitor)
		self.localMouseMonitor = nil
	}

	private func reconfigureTrackingAreasIfNeeded(force: Bool) {
		let needsRefresh = force
			|| FloatingInteractionPolicy.shouldRefreshTrackingAreas(
				previousBounds: CGRect(origin: .zero, size: lastTrackingBoundsSize),
				newBounds: bounds
			)
		guard needsRefresh else { return }

		isReconfiguringTracking = true
		defer { isReconfiguringTracking = false }

		if let boundsTrackingArea {
			removeTrackingArea(boundsTrackingArea)
		}
		if let affordanceTrackingArea {
			removeTrackingArea(affordanceTrackingArea)
		}

		let boundsArea = NSTrackingArea(
			rect: bounds,
			options: [
				.activeAlways,
				.mouseMoved,
				.mouseEnteredAndExited,
				.enabledDuringMouseDrag,
				.inVisibleRect,
			],
			owner: self,
			userInfo: ["kind": Self.trackingKindBounds]
		)
		addTrackingArea(boundsArea)
		boundsTrackingArea = boundsArea

		let affordanceRevealRect = FloatingInteractionPolicy.resizeAffordanceRevealRect(in: bounds)
		let affordanceArea = NSTrackingArea(
			rect: affordanceRevealRect,
			options: [
				.activeAlways,
				.mouseEnteredAndExited,
				.enabledDuringMouseDrag,
				.inVisibleRect,
			],
			owner: self,
			userInfo: ["kind": Self.trackingKindAffordance]
		)
		addTrackingArea(affordanceArea)
		affordanceTrackingArea = affordanceArea

		lastTrackingBoundsSize = bounds.size
	}

	private func syncPointerState(reason: String) {
		guard let window else { return }
		let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		handlePointerEvent(at: localPoint, reason: reason)
	}

	private func handlePointerEvent(at localPoint: CGPoint, reason: String) {
		if isTranslating {
			return
		}
		let inBounds = FloatingInteractionPolicy.pointerInBounds(localPoint, bounds: bounds)
		let inRevealRect = FloatingInteractionPolicy.resizeAffordanceRevealRect(in: bounds)
			.contains(localPoint)
		let wasInBounds = pointerInsideFrame
		pointerInsideFrame = inBounds
		if inBounds != wasInBounds {
			onHoverChange?(inBounds)
		}
		if inRevealRect {
			affordanceHoverActive = true
		} else if !isResizing {
			affordanceHoverActive = false
		}
		updateOverlayVisuals(
			localPoint: localPoint,
			pointerInAffordance: affordanceHoverActive || inRevealRect,
			reason: reason
		)
		onPointerUpdate?()
	}

	private func pushResizeCursor() {
		guard !resizeCursorPushed else { return }
		NSCursor.closedHand.push()
		resizeCursorPushed = true
	}

	private func popResizeCursorIfNeeded() {
		guard resizeCursorPushed else { return }
		NSCursor.pop()
		resizeCursorPushed = false
	}

	private func applyAffordanceCursor(for localPoint: CGPoint) {
		if isResizing {
			NSCursor.closedHand.set()
			return
		}
		let inAffordance = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds).contains(localPoint)
		if inAffordance {
			NSCursor.openHand.set()
		} else {
			NSCursor.arrow.set()
		}
	}

	private func updateOverlayVisuals(
		localPoint: CGPoint,
		pointerInAffordance: Bool,
		reason: String
	) {
		let shouldShowAffordance = FloatingInteractionPolicy.shouldShowResizeAffordance(
			pointerInAffordance: pointerInAffordance,
			isResizing: isResizing
		)
		let affordanceRect = FloatingInteractionPolicy.resizeAffordanceRect(in: bounds)
		let affordanceChanged = overlayView.showsResizeAffordance != shouldShowAffordance
		overlayView.showsResizeAffordance = shouldShowAffordance
		overlayView.resizeAffordanceRect = affordanceRect
		if affordanceChanged || pointerInAffordance {
			elevateOverlayAboveSpriteKit()
			overlayView.needsDisplay = true
		}

		if pointerInsideFrame || isResizing {
			applyAffordanceCursor(for: localPoint)
		} else {
			NSCursor.arrow.set()
		}

		syncPointerIdleInteraction(reason: reason)
	}

	private func emitInteraction(_ interaction: FloatingInteraction?, reason: String) {
		guard interaction != lastEmittedInteraction else { return }
		lastEmittedInteraction = interaction
		interactionHandler(interaction)
	}

	/// Clears interaction overlays when the pointer leaves the frame (no hover
	/// jumping). Skipped while `mouseDragged` owns interaction selection.
	private func syncPointerIdleInteraction(reason: String) {
		guard activeInteraction == nil, !pointerInsideFrame else { return }
		emitInteraction(nil, reason: "pointer-left-\(reason)")
	}
}


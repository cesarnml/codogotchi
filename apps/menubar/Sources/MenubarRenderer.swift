import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import QuartzCore

/// Whether the renderer paints the active state's frames at full saturation
/// (`.normal`) or with saturation collapsed to grayscale (`.desaturated`).
///
/// Desaturation is the early failure visual for the menubar: when the polling
/// driver in P2.07 can't reach a fresh `state.json`, the renderer is asked to
/// hold `.idle` in `.desaturated` mode rather than swap to a separate "error"
/// pet pose.
enum VisualMode: Equatable {
	case normal
	case desaturated
}

/// Which spritesheet produced the frames the renderer is currently animating.
/// The renderer uses this to select the correct per-frame interval without
/// having to inspect the frame count or call into either loader.
enum SpriteSource {
	/// Frame came from `MaliPet` (Codex sheet, ~125 ms/frame).
	case codex
	/// Frame came from `CodogotchiPet` (codogotchi sheet, ~167 ms/frame).
	case codogotchi
	/// Neither loader had frames for the state; renderer is showing `.idle`
	/// frames from the Codex sheet.
	case idleFallback
}

/// Composites Codex-sheet and codogotchi-sheet frames into the menu-bar
/// `NSStatusItem`, animating whichever spritesheet serves the current state.
///
/// Resolution order for any `ActivityState`:
/// 1. `MaliPet` (Codex sheet) — checked first via `MaliPet.rowMap`.
/// 2. `CodogotchiPet` (codogotchi sheet) — checked second.
/// 3. Idle fallback — `.idle` frames from the Codex sheet when both return empty.
///
/// The renderer is driven by external `update(state:visualMode:)` calls — it
/// does **not** read `state.json` directly (that's P2.07's job) and it does
/// not pick its own state. While a state is held the renderer animates its
/// frames on a continuous loop; on state transition the new loop begins from
/// frame 0 on the next tick.
///
/// All writes to `NSStatusItem.button.image` happen on the main actor. The
/// renderer accepts an injected `ImageSink` closure so tests can drive it
/// without a real `NSStatusItem` or `NSApplication` event loop.
@MainActor
final class MenubarRenderer {
	/// Closure the renderer calls with every painted frame. Production wires
	/// this to `statusItem.button.image = $0`; tests wire it to capture the
	/// emitted `NSImage` for assertion.
	typealias ImageSink = (NSImage) -> Void

	private let codexPet: MaliPet
	/// Nil when the codogotchi sheet was not installed at launch (soft degrade).
	/// The nine SoA-owned states fall back to idle rendering while nil.
	private let codogotchiPet: CodogotchiPet?
	private let sink: ImageSink
	private let ciContext: CIContext

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentFrames: [MaliPet.Frame] = []
	private var currentSource: SpriteSource = .codex
	private var frameIndex: Int = 0
	private var timer: Timer?
	/// When set, overrides the sheet-specific frame interval for every state.
	/// Demo mode passes `CODOGOTCHI_DEMO_FRAME_MS / 1000.0` here so each frame
	/// is individually inspectable regardless of which spritesheet serves it.
	private let demoFrameInterval: TimeInterval?

	init(
		codexPet: MaliPet,
		codogotchiPet: CodogotchiPet?,
		sink: @escaping ImageSink,
		demoFrameInterval: TimeInterval? = nil
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.sink = sink
		self.ciContext = CIContext(options: nil)
		self.demoFrameInterval = demoFrameInterval
		self.currentFrames = codexPet.frames(for: .idle)
		self.currentSource = .codex
	}

	deinit {
		timer?.invalidate()
	}

	/// Switch to `state` in `visualMode`. On state change the frame index
	/// resets to 0 so the new loop begins at frame 0; on a visual-mode-only
	/// change the current frame is repainted under the new mode without
	/// restarting the loop.
	func update(state: ActivityState, visualMode: VisualMode) {
		let stateChanged = state != currentState || currentFrames.isEmpty
		let modeChanged = visualMode != currentMode
		currentState = state
		currentMode = visualMode

		if stateChanged {
			resolveFrames(for: state)
			frameIndex = 0
		}

		paintCurrent()

		if stateChanged || timer == nil {
			restartTimer()
		} else if !modeChanged {
			// No state change, no mode change — keep the existing timer.
		}
	}

	// MARK: - Test seam

	/// Snapshot of the currently held state — exposed for unit tests.
	var currentStateForTesting: ActivityState { currentState }

	/// Snapshot of the currently held visual mode — exposed for unit tests.
	var currentVisualModeForTesting: VisualMode { currentMode }

	/// Frame index inside the active state's row — exposed for unit tests so
	/// the state-transition reset to 0 can be asserted.
	var currentFrameIndexForTesting: Int { frameIndex }

	/// The frame array the renderer is currently animating — exposed for unit
	/// tests so they can confirm the renderer swapped to the right row.
	var currentFramesForTesting: [NSImage] { currentFrames.map(\.image) }

	/// Advance one frame without waiting for the real `Timer`. Used by tests
	/// to drive frame-index transitions deterministically.
	func advanceFrameForTesting() {
		tick()
	}

	// MARK: - Internals

	/// Populate `currentFrames` and `currentSource` via composite resolution.
	private func resolveFrames(for state: ActivityState) {
		let codexFrames = codexPet.frames(for: state)
		if !codexFrames.isEmpty {
			currentFrames = codexFrames
			currentSource = .codex
			return
		}
		let codogotchiFrames = codogotchiPet?.frames(for: state) ?? []
		if !codogotchiFrames.isEmpty {
			currentFrames = codogotchiFrames
			currentSource = .codogotchi
			return
		}
		// Neither sheet maps this state — fall back to Codex idle.
		currentFrames = codexPet.frames(for: .idle)
		currentSource = .idleFallback
	}

	private func renderedCurrentFrame() -> NSImage? {
		guard !currentFrames.isEmpty else { return nil }
		let frame = currentFrames[frameIndex % currentFrames.count]
		switch currentMode {
		case .normal:
			return frame.image
		case .desaturated:
			// Skip the sink emission rather than silently emitting a colored
			// frame when Core Image fails. The previous painted frame (which
			// is already desaturated whenever the renderer entered
			// `.desaturated` mode in steady state) stays on the status item.
			// Emitting a colored frame here would silently violate the
			// desaturated-mode contract and defeat the early-failure-visual
			// intent of this mode.
			return desaturate(frame)
		}
	}

	private func desaturate(_ frame: MaliPet.Frame) -> NSImage? {
		// Use the CGImage from the Frame directly instead of asking
		// AppKit to vend one via NSImage.cgImage(forProposedRect:), which
		// intermittently returns nil when the NSImage's logical size differs
		// from its backing pixel dimensions — that was the root cause of the
		// menubar flicker before P2.11 plumbed the CGImage through.
		let ci = CIImage(cgImage: frame.cgImage)
		let filter = CIFilter.colorControls()
		filter.inputImage = ci
		filter.saturation = 0
		guard let output = filter.outputImage,
			let outCG = ciContext.createCGImage(output, from: output.extent)
		else {
			NSLog("MenubarRenderer: desaturate skipped — CIColorControls produced no output")
			return nil
		}
		return NSImage(cgImage: outCG, size: frame.image.size)
	}

	private func restartTimer() {
		timer?.invalidate()
		let interval: TimeInterval
		if let demo = demoFrameInterval {
			// Demo mode: uniform interval across all sheets so each frame is
			// individually inspectable. Shortcuts the sheet-specific defaults.
			interval = demo
		} else {
			switch currentSource {
			case .codogotchi:
				interval = CodogotchiPet.frameInterval
			case .codex, .idleFallback:
				// Codex sheet cycles all rows in ~1 s by dividing by the actual
				// frame count. Variable frame counts per row (8, 6, 4) each produce
				// a ~1 s animation cycle.
				interval = 1.0 / Double(max(currentFrames.count, 1))
			}
		}
		dbgLog("DBG restartTimer: source=\(currentSource) interval=\(interval)")
		let newTimer = Timer(timeInterval: interval, repeats: true) {
			[weak self] _ in
			let t = CACurrentMediaTime()
			dbgLog("DBG t=\(t) timer.block fired")
			Task { @MainActor in self?.tick() }
		}
		RunLoop.main.add(newTimer, forMode: .common)
		timer = newTimer
	}

	private func tick() {
		guard !currentFrames.isEmpty else {
			dbgLog("DBG tick: currentFrames empty, skipping")
			return
		}
		frameIndex = (frameIndex + 1) % currentFrames.count
		let t = CACurrentMediaTime()
		dbgLog("DBG t=\(t) tick: frameIndex=\(frameIndex) of \(currentFrames.count)")
		paintCurrent()
	}

	private func paintCurrent() {
		guard let frame = renderedCurrentFrame() else {
			dbgLog("DBG paintCurrent: renderedCurrentFrame returned nil (mode=\(currentMode))")
			return
		}
		let t = CACurrentMediaTime()
		dbgLog(
			"DBG t=\(t) paintCurrent: emitting frame idx=\(frameIndex) size=\(frame.size.width)x\(frame.size.height)"
		)
		sink(frame)
	}
}

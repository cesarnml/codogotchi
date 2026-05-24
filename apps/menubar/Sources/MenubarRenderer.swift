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

/// Paints Mali into the menu-bar `NSStatusItem` for the four floor states.
///
/// The renderer is driven by external `update(state:visualMode:)` calls — it
/// does **not** read `state.json` directly (that's P2.07's job) and it does
/// not pick its own state. While a state is held the renderer animates its
/// frames on a 1-second-per-cycle continuous loop; on state transition the
/// new loop begins from frame 0 on the next tick.
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

	private let pet: MaliPet
	private let sink: ImageSink
	private let ciContext: CIContext

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentFrames: [MaliPet.Frame] = []
	private var frameIndex: Int = 0
	private var timer: Timer?

	init(pet: MaliPet, sink: @escaping ImageSink) {
		self.pet = pet
		self.sink = sink
		self.ciContext = CIContext(options: nil)
		self.currentFrames = pet.frames(for: .idle)
	}

	deinit {
		timer?.invalidate()
	}

	/// Switch to `state` in `visualMode`. On state change the frame index
	/// resets to 0 so the new loop starts at the beginning of the row; on a
	/// visual-mode-only change the current frame is repainted under the new
	/// mode without restarting the loop. The 1-second animation timer is
	/// (re)scheduled with an interval of `1 / frameCount` seconds.
	func update(state: ActivityState, visualMode: VisualMode) {
		let stateChanged = state != currentState || currentFrames.isEmpty
		let modeChanged = visualMode != currentMode
		currentState = state
		currentMode = visualMode

		if stateChanged {
			let frames = pet.frames(for: state)
			// States not yet in the rowMap (codogotchi-sheet states pending P3.04)
			// fall back to idle frames so the menubar always shows something.
			currentFrames = frames.isEmpty ? pet.frames(for: .idle) : frames
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
		let frameCount = max(currentFrames.count, 1)
		let interval = 1.0 / Double(frameCount)
		dbgLog("DBG restartTimer: frameCount=\(frameCount) interval=\(interval)")
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

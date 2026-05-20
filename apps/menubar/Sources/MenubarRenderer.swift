import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

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
	private var currentFrames: [NSImage] = []
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
			currentFrames = pet.frames(for: state)
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
	var currentFramesForTesting: [NSImage] { currentFrames }

	/// Advance one frame without waiting for the real `Timer`. Used by tests
	/// to drive frame-index transitions deterministically.
	func advanceFrameForTesting() {
		tick()
	}

	// MARK: - Internals

	private func paintCurrent() {
		guard let frame = renderedCurrentFrame() else { return }
		sink(frame)
	}

	private func renderedCurrentFrame() -> NSImage? {
		guard !currentFrames.isEmpty else { return nil }
		let raw = currentFrames[frameIndex % currentFrames.count]
		switch currentMode {
		case .normal:
			return raw
		case .desaturated:
			// Skip the sink emission rather than silently emitting a colored
			// frame when Core Image fails. The previous painted frame (which
			// is already desaturated whenever the renderer entered
			// `.desaturated` mode in steady state) stays on the status item.
			// Emitting a colored frame here would silently violate the
			// desaturated-mode contract and defeat the early-failure-visual
			// intent of this mode.
			return desaturate(raw)
		}
	}

	private func desaturate(_ image: NSImage) -> NSImage? {
		guard
			let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
			NSLog("MenubarRenderer: desaturate skipped — NSImage has no backing CGImage")
			return nil
		}
		let ci = CIImage(cgImage: cg)
		let filter = CIFilter.colorControls()
		filter.inputImage = ci
		filter.saturation = 0
		guard let output = filter.outputImage,
			let outCG = ciContext.createCGImage(output, from: output.extent)
		else {
			NSLog("MenubarRenderer: desaturate skipped — CIColorControls produced no output")
			return nil
		}
		return NSImage(cgImage: outCG, size: image.size)
	}

	private func restartTimer() {
		timer?.invalidate()
		let frameCount = max(currentFrames.count, 1)
		let interval = 1.0 / Double(frameCount)
		// `[weak self]` avoids a retain cycle through the timer's closure —
		// `Timer.scheduledTimer(withTimeInterval:repeats:block:)` keeps a
		// strong reference to its block, and the block would otherwise hold
		// the renderer alive past its intended lifetime (a known AppKit
		// pitfall called out in the ticket review focus).
		timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
			[weak self] _ in
			Task { @MainActor in self?.tick() }
		}
	}

	private func tick() {
		guard !currentFrames.isEmpty else { return }
		frameIndex = (frameIndex + 1) % currentFrames.count
		paintCurrent()
	}
}

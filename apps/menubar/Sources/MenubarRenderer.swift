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

/// Composites CodogotchiPet two-sheet and Codex-sheet frames into the menu-bar
/// `NSStatusItem`, painting a single static hero frame per active state.
///
/// Resolution order for any `ActivityState`:
/// 1. `CodogotchiPet` (SoA sheet → Lite-Basic sheet) — checked first.
/// 2. `CodexPet` (Codex sheet) — fallback when CodogotchiPet returns empty.
/// 3. Idle fallback — `.idle` frames from the Codex sheet when both return empty.
///
/// The renderer is driven by external `update(state:visualMode:)` calls — it
/// does **not** read `state.json` directly (that's the polling driver's job)
/// and it does not pick its own state. It does **not** animate: the menubar
/// surface is too small for frame-to-frame motion to read at the 22pt status
/// item size, and the floating pet carries the live animation when present.
/// On state or visual-mode change the renderer paints the row's hero frame
/// (`heroFrameIndex`) once. Subsequent `update` calls with unchanged inputs
/// are no-ops, so the 1 Hz polling tick does not trigger redundant repaints.
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

	/// Frame the renderer paints for every active row (0-indexed). Both
	/// shipped spritesheets are safe at this index: the codogotchi sheet has
	/// 24 non-blank frames per row, and the codex sheet's per-row layout per
	/// https://codexpet.xyz/spec/ has a non-blank frame at index 3 on every
	/// row used today. Clamped at paint time so pathologically short rows
	/// still resolve to the last available frame.
	static let heroFrameIndex = 3

	private var codexPet: CodexPet
	/// Nil when no codogotchi sheets are available (soft degrade).
	private var codogotchiPet: CodogotchiPet?
	private let sink: ImageSink
	private let ciContext: CIContext

	private var currentState: ActivityState = .idle
	private var currentMode: VisualMode = .normal
	private var currentFrames: [CodexPet.Frame] = []
	private var frameIndex: Int = 0

	init(
		codexPet: CodexPet,
		codogotchiPet: CodogotchiPet?,
		sink: @escaping ImageSink
	) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		self.sink = sink
		self.ciContext = CIContext(options: nil)
		// currentFrames stays empty so the first `update` call always paints,
		// even when the first state is the default `.idle`.
	}

	/// Switch to `state` in `visualMode`. Repaints exactly when the resolved
	/// (state, mode) pair differs from the last painted pair — including the
	/// first call after init, when `currentFrames` is empty. The painted
	/// frame is the row's static hero (`heroFrameIndex`, clamped to the row
	/// length).
	func update(state: ActivityState, visualMode: VisualMode) {
		let stateChanged = state != currentState || currentFrames.isEmpty
		let modeChanged = visualMode != currentMode
		guard stateChanged || modeChanged else { return }

		currentState = state
		currentMode = visualMode

		if stateChanged {
			resolveFrames(for: state)
			frameIndex = min(Self.heroFrameIndex, max(currentFrames.count - 1, 0))
		}

		paintCurrent()
	}

	/// Swap in new pet loaders and immediately repaint the current state.
	func replacePets(codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		self.codexPet = codexPet
		self.codogotchiPet = codogotchiPet
		currentFrames = []  // force re-resolve on next update
		update(state: currentState, visualMode: currentMode)
	}

	// MARK: - Test seam

	/// Snapshot of the currently held state — exposed for unit tests.
	var currentStateForTesting: ActivityState { currentState }

	/// Snapshot of the currently held visual mode — exposed for unit tests.
	var currentVisualModeForTesting: VisualMode { currentMode }

	/// Frame index inside the active state's row — exposed for unit tests so
	/// the hero-frame selection can be asserted.
	var currentFrameIndexForTesting: Int { frameIndex }

	/// The frame array the renderer is currently holding — exposed for unit
	/// tests so they can confirm the renderer swapped to the right row.
	var currentFramesForTesting: [NSImage] { currentFrames.map(\.image) }

	// MARK: - Internals

	/// Populate `currentFrames` via composite resolution.
	private func resolveFrames(for state: ActivityState) {
		// CodogotchiPet covers SoA gate states and Lite-Basic hook states.
		let codogotchiFrames = codogotchiPet?.frames(for: state) ?? []
		if !codogotchiFrames.isEmpty {
			currentFrames = codogotchiFrames
			return
		}
		// Codex sheet: hook-animation fallback for unknown/artless states.
		let codexFrames = codexPet.frames(for: state)
		if !codexFrames.isEmpty {
			currentFrames = codexFrames
			return
		}
		// Final fallback: Codex idle.
		currentFrames = codexPet.frames(for: .idle)
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

	private func desaturate(_ frame: CodexPet.Frame) -> NSImage? {
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

	private func paintCurrent() {
		guard let frame = renderedCurrentFrame() else {
			return
		}
		sink(frame)
	}
}

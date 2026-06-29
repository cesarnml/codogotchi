import CoreGraphics
import Foundation

let APP_STATE_SCHEMA_VERSION = 3

struct FloatingAppState: Codable, Equatable {
	let isFloatingPetVisible: Bool
	let frame: CGRect
	let onboardingCompletedAt: String?
	let lastHookActivityAt: String?
	let hooksStatus: HooksStatusSnapshot?
	/// Version token recorded after hooks install/update. Nil means hooks were
	/// never installed via the app, or the state file predates schema v2.
	let installedHookVersion: String?

	init(
		isFloatingPetVisible: Bool,
		frame: CGRect,
		onboardingCompletedAt: String? = nil,
		lastHookActivityAt: String? = nil,
		hooksStatus: HooksStatusSnapshot? = nil,
		installedHookVersion: String? = nil
	) {
		self.isFloatingPetVisible = isFloatingPetVisible
		self.frame = frame
		self.onboardingCompletedAt = onboardingCompletedAt
		self.lastHookActivityAt = lastHookActivityAt
		self.hooksStatus = hooksStatus
		self.installedHookVersion = installedHookVersion
	}
}

enum FloatingFramePolicy {
	static let minimumSize = CGSize(width: 96, height: 96)
	static let maximumSize = CGSize(width: 256, height: 256)
	static let defaultSize = CGSize(width: 160, height: 160)
	static let safeMargin: CGFloat = 24

	static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
		let size = clampedSize(defaultSize, to: visibleFrame.size)
		let x = visibleFrame.maxX - size.width - safeMargin
		let y = visibleFrame.minY + safeMargin
		return clamp(CGRect(origin: CGPoint(x: x, y: y), size: size), to: visibleFrame)
	}

	static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
		guard visibleFrame.width > 0, visibleFrame.height > 0 else {
			return CGRect(origin: .zero, size: minimumSize)
		}

		let size = clampedSize(frame.size, to: visibleFrame.size)
		let x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
		let y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
		return CGRect(x: x, y: y, width: size.width, height: size.height)
	}

	private static func clampedSize(_ size: CGSize, to visibleSize: CGSize) -> CGSize {
		let width = min(max(size.width, minimumSize.width), min(maximumSize.width, visibleSize.width))
		let height = min(max(size.height, minimumSize.height), min(maximumSize.height, visibleSize.height))
		return CGSize(width: width, height: height)
	}

	/// Scale a source-cell image to fit inside a floating panel without SpriteKit
	/// scene/view scaling. Used for debug logging and codex calibration checks.
	static func fittedSpriteSize(imageSize: CGSize, panelSize: CGSize) -> CGSize {
		guard imageSize.width > 0, imageSize.height > 0, panelSize.width > 0, panelSize.height > 0
		else {
			return imageSize
		}
		let scale = min(panelSize.width / imageSize.width, panelSize.height / imageSize.height)
		return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
	}
}

enum AppStateStore {
	static func appStateURL() -> URL {
		if let cStr = getenv("CODOGOTCHI_HOME"), let home = String(validatingUTF8: cStr) {
			return URL(fileURLWithPath: home).appendingPathComponent("app-state.json")
		}
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codogotchi")
			.appendingPathComponent("app-state.json")
	}

	static func load(visibleFrame: CGRect) -> FloatingAppState {
		let fallback = defaultState(visibleFrame: visibleFrame)
		let url = appStateURL()
		let data: Data
		do {
			data = try Data(contentsOf: url)
		} catch {
			if FileManager.default.fileExists(atPath: url.path) {
			}
			return fallback
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let payload = try? decoder.decode(AppStatePayload.self, from: data),
			payload.schemaVersion <= APP_STATE_SCHEMA_VERSION
		else {
			return fallback
		}

		return FloatingAppState(
			isFloatingPetVisible: payload.floatingPet.visible,
			frame: FloatingFramePolicy.clamp(payload.floatingPet.frame.cgRect, to: visibleFrame),
			onboardingCompletedAt: payload.onboardingCompletedAt,
			lastHookActivityAt: payload.lastHookActivityAt,
			hooksStatus: payload.hooksStatus,
			installedHookVersion: payload.installedHookVersion
		)
	}

	static func save(_ state: FloatingAppState) throws {
		let url = appStateURL()
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

		// Preserve per-origin positions written by pool windows so a single-controller
		// save (e.g. hook-status refresh) doesn't clobber them.
		let existingPositions = loadRawPayload(url: url)?.floatingPetPositions

		let payload = AppStatePayload(
			schemaVersion: APP_STATE_SCHEMA_VERSION,
			floatingPet: FloatingPetPayload(
				visible: state.isFloatingPetVisible,
				frame: FloatingFramePayload(state.frame)
			),
			floatingPetPositions: existingPositions,
			onboardingCompletedAt: state.onboardingCompletedAt,
			lastHookActivityAt: state.lastHookActivityAt,
			hooksStatus: state.hooksStatus,
			installedHookVersion: state.installedHookVersion
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.keyEncodingStrategy = .convertToSnakeCase
		let data = try encoder.encode(payload)
		try data.write(to: url, options: .atomic)
	}

	/// Returns the saved frame for `origin`, or the default frame when none has been stored.
	static func loadFrame(for origin: String, visibleFrame: CGRect) -> CGRect {
		guard let payload = loadRawPayload(url: appStateURL()),
			payload.schemaVersion <= APP_STATE_SCHEMA_VERSION
		else {
			return FloatingFramePolicy.defaultFrame(in: visibleFrame)
		}
		if let saved = payload.floatingPetPositions?[origin] {
			return FloatingFramePolicy.clamp(saved.cgRect, to: visibleFrame)
		}
		return FloatingFramePolicy.defaultFrame(in: visibleFrame)
	}

	/// Persists `frame` for `origin` in the `floating_pet_positions` map, leaving all
	/// other fields in the file untouched.
	static func saveFrame(_ frame: CGRect, for origin: String) throws {
		let url = appStateURL()
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let existing = loadRawPayload(url: url)
		var positions = existing?.floatingPetPositions ?? [:]
		positions[origin] = FloatingFramePayload(frame)
		let payload = AppStatePayload(
			schemaVersion: APP_STATE_SCHEMA_VERSION,
			floatingPet: existing?.floatingPet
				?? FloatingPetPayload(visible: true, frame: FloatingFramePayload(FloatingFramePolicy.defaultFrame(in: .zero))),
			floatingPetPositions: positions,
			onboardingCompletedAt: existing?.onboardingCompletedAt,
			lastHookActivityAt: existing?.lastHookActivityAt,
			hooksStatus: existing?.hooksStatus,
			installedHookVersion: existing?.installedHookVersion
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.keyEncodingStrategy = .convertToSnakeCase
		let data = try encoder.encode(payload)
		try data.write(to: url, options: .atomic)
	}

	private static func loadRawPayload(url: URL) -> AppStatePayload? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return try? decoder.decode(AppStatePayload.self, from: data)
	}

	private static func defaultState(visibleFrame: CGRect) -> FloatingAppState {
		FloatingAppState(
			isFloatingPetVisible: true,
			frame: FloatingFramePolicy.defaultFrame(in: visibleFrame)
		)
	}
}

private struct AppStatePayload: Codable {
	let schemaVersion: Int
	let floatingPet: FloatingPetPayload
	/// Per-origin last-known frame, keyed by window key ("claude_code", "cursor", "combined", …).
	let floatingPetPositions: [String: FloatingFramePayload]?
	let onboardingCompletedAt: String?
	let lastHookActivityAt: String?
	let hooksStatus: HooksStatusSnapshot?
	let installedHookVersion: String?
}

private struct FloatingPetPayload: Codable {
	let visible: Bool
	let frame: FloatingFramePayload
}

private struct FloatingFramePayload: Codable {
	let x: CGFloat
	let y: CGFloat
	let width: CGFloat
	let height: CGFloat

	init(_ rect: CGRect) {
		x = rect.origin.x
		y = rect.origin.y
		width = rect.size.width
		height = rect.size.height
	}

	var cgRect: CGRect {
		CGRect(x: x, y: y, width: width, height: height)
	}
}

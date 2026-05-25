import CoreGraphics
import Foundation

let APP_STATE_SCHEMA_VERSION = 1

struct FloatingAppState: Codable, Equatable {
	let isFloatingPetVisible: Bool
	let frame: CGRect
}

enum FloatingFramePolicy {
	static let minimumSize = CGSize(width: 96, height: 96)
	static let maximumSize = CGSize(width: 512, height: 512)
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
				dbgLog("AppStateStore.load: falling back after unreadable app-state.json: \(error.localizedDescription)")
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
			frame: FloatingFramePolicy.clamp(payload.floatingPet.frame.cgRect, to: visibleFrame)
		)
	}

	static func save(_ state: FloatingAppState) throws {
		let url = appStateURL()
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

		let payload = AppStatePayload(
			schemaVersion: APP_STATE_SCHEMA_VERSION,
			floatingPet: FloatingPetPayload(
				visible: state.isFloatingPetVisible,
				frame: FloatingFramePayload(state.frame)
			)
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.keyEncodingStrategy = .convertToSnakeCase
		let data = try encoder.encode(payload)
		try data.write(to: url, options: .atomic)
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

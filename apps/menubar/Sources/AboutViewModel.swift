import Foundation

// RED stub — real implementation lands in the green step of P8.03.

struct AboutViewModel {
	let appVersionSource: () -> String
	let hookVersionSource: () -> String

	init(
		appVersionSource: @escaping () -> String = { "" },
		hookVersionSource: @escaping () -> String = { "" }
	) {
		self.appVersionSource = appVersionSource
		self.hookVersionSource = hookVersionSource
	}

	var appVersion: String { "" }
	var hookVersion: String { "" }

	static func bundledHookVersion(
		runner: HookStatusClient.Runner = HookStatusClient.defaultRunner
	) -> String {
		""
	}
}

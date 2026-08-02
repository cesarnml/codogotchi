import Foundation

/// View-model for the General tab.
///
/// Maps a `HooksStatusSnapshot` to per-platform display rows and builds the
/// diagnostics payload. Owns status refresh so the window controller can call
/// `refresh()` after any hook action and re-bind `rows`.
final class GeneralTabViewModel {
	/// A single platform row as the tab renders it.
	struct PlatformRow: Equatable {
		let name: String
		/// Origin key (`"codex"`, `"claude_code"`, …) used to look up the
		/// platform's icon via `PlatformAttribution`. Distinct from `name`
		/// (the human-readable label) so the view doesn't have to re-derive
		/// one from the other.
		let originKey: String
		let installed: Bool
		let partiallyInstalled: Bool
		let firingRecently: Bool
		let lastEventAt: String?
		let sourceOrigin: String?
		let installable: Bool
		/// The platform is present on this machine but may not have hooks yet.
		let detected: Bool
		/// The installed registration matches what the current binary would write.
		/// `false` means genuine registration drift (missing event slots or a stale
		/// command path) that re-running Update actually fixes.
		let registrationCurrent: Bool

		/// Which status pill to show and the descriptor line beneath it in the
		/// Hooks table. Purely a display-layer grouping of the fields above —
		/// no new data, just named buckets instead of ad hoc string assembly
		/// (see the old `platformLine()` this replaces).
		enum StatusPill: Equatable {
			case installed
			case updateAvailable
			case detectedNotInstalled
			case notInstalled
			case notSupported
		}

		struct StatusPresentation: Equatable {
			let pill: StatusPill
			let pillTitle: String
			let descriptor: String
		}

		var statusPresentation: StatusPresentation {
			guard installable else {
				return StatusPresentation(
					pill: .notSupported, pillTitle: "Not supported yet", descriptor: "Coming soon")
			}
			if installed && registrationCurrent {
				return StatusPresentation(
					pill: .installed, pillTitle: "Installed", descriptor: "Registration current")
			}
			// Covers both a fully-installed-but-stale registration and a partial
			// install (present, missing a newly added event slot) — both are
			// fixed the same way: re-run Update.
			if installed || partiallyInstalled {
				return StatusPresentation(
					pill: .updateAvailable, pillTitle: "Update available",
					descriptor: "Registration out of date")
			}
			if detected {
				return StatusPresentation(
					pill: .detectedNotInstalled, pillTitle: "Detected — not installed",
					descriptor: "Present on this machine, no hooks yet")
			}
			return StatusPresentation(
				pill: .notInstalled, pillTitle: "Not installed",
				descriptor: "Run Install hooks to add this tool")
		}
	}

	/// Current per-platform rows. Updated by `applySnapshot(_:)` and `refresh()`.
	private(set) var rows: [PlatformRow] = []

	/// Most recent snapshot retained for diagnostics JSON assembly.
	private(set) var lastSnapshot: HooksStatusSnapshot?

	/// Version last recorded in `app-state.json` after a successful install/update.
	/// Set by `SettingsWindowController` after a successful hook operation.
	var installedHookVersion: String?

	/// True when the bundled binary reports a different version than the one last
	/// recorded at install/update time.
	///
	/// This is NO LONGER a banner trigger: a version bump can be pure
	/// binary-internals drift (same registered command path, same event slots),
	/// in which case re-registering is a no-op and prompting the user is noise.
	/// The binary version is surfaced informationally in the About tab instead.
	/// The actionable signal is `hasStaleRegistration`, which compares the
	/// installed registration against what the current binary would write. Kept
	/// as a predicate for diagnostics and tests.
	var needsBannerUpdate: Bool {
		LockstepPolicy.needsUpdate(
			hooksInstalled: rows.contains { $0.installed },
			bundledVersion: hookVersion,
			installedVersion: installedHookVersion
		)
	}

	/// True when an installable platform HAS codogotchi hooks (fully or partially
	/// wired) whose registration no longer matches what the current binary would
	/// write — missing event slots OR a stale command path. Re-running Update
	/// re-registers them (idempotently). This subsumes the old
	/// partially-installed-only check and additionally catches command-format
	/// drift that a version-string comparison used to stand in for.
	var hasStaleRegistration: Bool {
		rows.contains {
			$0.installable && ($0.installed || $0.partiallyInstalled)
				&& !$0.registrationCurrent
		}
	}

	/// True when a coding tool is present on this machine but has no codogotchi
	/// hooks at all (not installed, not partial). This is the "you installed a
	/// new tool since last time — Update to wire it" signal.
	var hasUnhookedDetectedPlatform: Bool {
		rows.contains {
			$0.installable && $0.detected && !$0.installed && !$0.partiallyInstalled
		}
	}

	/// Whether to show the update banner at all: an installed registration that
	/// drifted from what the current binary would write, OR a newly detected tool
	/// that has no hooks yet. A pure binary-version bump with an unchanged
	/// registration deliberately shows nothing.
	var shouldShowUpdateBanner: Bool {
		hasStaleRegistration || hasUnhookedDetectedPlatform
	}

	/// Banner copy reflecting why an update is offered. Stale registration takes
	/// precedence over a newly detected tool with no hooks.
	var updateBannerMessage: String {
		if hasStaleRegistration {
			return "Hooks are out of date — click Update to re-register them."
		}
		return "A new coding tool was detected — click Update to install its hooks."
	}

	/// Current value of the "Monochrome menu bar icon" toggle.
	/// Loaded from `customization.json` on init; updated via `setMonochromeMenubarIcon`.
	private(set) var menubarIconMonochrome: Bool

	/// Current value of the "Require Prune Session confirmation" toggle. `true`
	/// (the default) shows the destructive-action alert every time; unchecked
	/// it prunes immediately. Inverted storage: persisted as
	/// `features.skip_prune_confirmation` in `config.json`, since that flag also
	/// gets set from the alert's own "Do not show this warning again." checkbox.
	private(set) var requirePruneConfirmation: Bool

	/// Current value of the "Animate platform logo while working" toggle.
	/// Loaded from `customization.json` on init; updated via
	/// `setPlatformChipAnimationEnabled`. Off by default.
	private(set) var platformChipAnimationEnabled: Bool

	private let statusClient: HookStatusClient
	private let appVersion: String
	private let hookVersion: String
	private let store: CustomizationStore
	private let configFileURL: URL

	init(
		statusClient: HookStatusClient = HookStatusClient(),
		appVersion: String = AboutViewModel.bundleShortVersion(),
		hookVersion: String = AboutViewModel.bundledHookVersion(),
		customizationFilePath: String = CodogotchiFolders.customizationPath(),
		configFileURL: URL = PetConfig.configURL(),
		store: CustomizationStore? = nil
	) {
		self.statusClient = statusClient
		self.appVersion = appVersion
		self.hookVersion = hookVersion
		self.store = store ?? CustomizationStore(filePath: customizationFilePath)
		self.configFileURL = configFileURL
		self.menubarIconMonochrome = self.store.snapshot.menubarIconMonochrome
		self.requirePruneConfirmation = !PetConfig.resolvedSkipPruneConfirmation(from: configFileURL)
		self.platformChipAnimationEnabled = self.store.snapshot.platformChipAnimationEnabled
	}

	/// Persists `menubar_icon_monochrome` through the shared `CustomizationStore`
	/// (the sole `customization.json` writer) without clobbering unmanaged keys.
	/// Returns `true` when the write succeeded; in-memory state is only updated
	/// on success so it stays in sync with what survives a relaunch.
	@discardableResult
	func setMonochromeMenubarIcon(_ value: Bool) -> Bool {
		guard let snapshot = store.merge(["menubar_icon_monochrome": value]) else { return false }
		menubarIconMonochrome = snapshot.menubarIconMonochrome
		return true
	}

	/// Persists `platform_chip_animation_enabled` through the shared
	/// `CustomizationStore`, mirroring `setMonochromeMenubarIcon`. Returns `true`
	/// when the write succeeded; in-memory state is only updated on success so it
	/// stays in sync with what survives a relaunch.
	@discardableResult
	func setPlatformChipAnimationEnabled(_ value: Bool) -> Bool {
		guard let snapshot = store.merge(["platform_chip_animation_enabled": value]) else { return false }
		platformChipAnimationEnabled = snapshot.platformChipAnimationEnabled
		return true
	}

	/// Persists `features.skip_prune_confirmation` (the inverse of `value`) to
	/// `config.json`, preserving every other field. Returns `true` on a
	/// successful write; in-memory state only updates on success so it stays in
	/// sync with what survives a relaunch.
	@discardableResult
	func setRequirePruneConfirmation(_ value: Bool) -> Bool {
		do {
			try PetConfig.write(skipPruneConfirmation: !value, to: configFileURL)
		} catch {
			NSLog("GeneralTabViewModel: prune-confirmation write failed — \(error)")
			return false
		}
		requirePruneConfirmation = value
		return true
	}

	/// Updates rows from an already-fetched snapshot. Safe to call on any queue.
	func applySnapshot(_ snapshot: HooksStatusSnapshot) {
		lastSnapshot = snapshot
		rows = [
			row("Codex", "codex", snapshot.codex),
			row("Claude Code", "claude_code", snapshot.claudeCode),
			row("Cursor", "cursor", snapshot.cursor),
			row("VS Code", "vscode", snapshot.vscode),
			row("Antigravity", "antigravity", snapshot.antigravity),
		]
	}

	/// Fetches a fresh snapshot from `statusClient` and applies it.
	/// Silently no-ops on client failure so callers are not broken by a missing CLI.
	func refresh() {
		guard let snap = try? statusClient.fetch() else { return }
		applySnapshot(snap)
	}

	/// Returns a JSON string suitable for clipboard diagnostics support.
	/// Shape matches `codogotchi hooks status --json`: all optional fields are
	/// emitted as `null` (never omitted) so support tooling sees the same schema
	/// as the CLI regardless of which platforms have fired recently.
	func diagnosticsJSON() -> String {
		let snap = lastSnapshot
		let dict: [String: Any] = [
			"codogotchi": appVersion,
			"hookBinary": hookVersion,
			"hooksStatus": snap.map { statusDict($0) } ?? ([String: Any]() as Any),
		]
		let data = (try? JSONSerialization.data(
			withJSONObject: dict,
			options: [.prettyPrinted, .sortedKeys]
		)) ?? Data()
		return String(data: data, encoding: .utf8) ?? "{}"
	}

	// MARK: - Private

	/// Builds the `hooksStatus` dict matching the `hooks status --json` contract.
	/// All optional fields are explicit `NSNull()` when absent so consumers see
	/// a stable schema rather than key-absent JSON.
	private func statusDict(_ snap: HooksStatusSnapshot) -> [String: Any] {
		return [
			"codex": platformDict(snap.codex),
			"claude_code": platformDict(snap.claudeCode),
			"cursor": platformDict(snap.cursor),
			"vscode": platformDict(snap.vscode),
			"antigravity": platformDict(snap.antigravity),
		]
	}

	private func platformDict(_ p: HooksStatusSnapshot.Platform) -> [String: Any] {
		return [
			"present_on_disk": p.presentOnDisk,
			"installable_in_phase": p.installableInPhase,
			"detected": p.detected,
			"installed": p.installed,
			"partially_installed": p.partiallyInstalled,
			"registration_current": p.registrationCurrent,
			"firing_recently": p.firingRecently,
			"last_event_at": p.lastEventAt.map { $0 as Any } ?? (NSNull() as Any),
			"source_origin": p.sourceOrigin.map { $0 as Any } ?? (NSNull() as Any),
		]
	}

	private func row(_ name: String, _ originKey: String, _ p: HooksStatusSnapshot.Platform) -> PlatformRow {
		PlatformRow(
			name: name,
			originKey: originKey,
			installed: p.installed,
			partiallyInstalled: p.partiallyInstalled,
			firingRecently: p.firingRecently,
			lastEventAt: p.lastEventAt,
			sourceOrigin: p.sourceOrigin,
			installable: p.installableInPhase,
			detected: p.detected,
			registrationCurrent: p.registrationCurrent
		)
	}
}

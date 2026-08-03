import AppKit
import XCTest

@testable import Codogotchi

/// The precedence question: when the in-app "Animate platform logo while
/// working" toggle and the system Reduce Motion setting disagree, who wins?
///
/// Answer encoded here: Reduce Motion wins by default, because it is a
/// system-wide accessibility declaration and the safe direction to fail is
/// "less motion". But it must never win *silently* — a dead toggle with no
/// explanation is its own bug — so the conflict raises a notice, and an explicit
/// per-app override lets a user who has been told what is happening ask for the
/// animation anyway.
final class ReduceMotionPrecedenceTests: XCTestCase {

	// MARK: - Precedence

	func testReduceMotionBeatsTheToggleByDefault() {
		let settings = MotionSettings(chipAnimationEnabled: true, ignoresReduceMotion: false)
		XCTAssertFalse(
			settings.allowsChipAnimation(systemPrefersReducedMotion: true),
			"an accessibility setting the user set system-wide outranks an app default")
		XCTAssertTrue(settings.allowsChipAnimation(systemPrefersReducedMotion: false))
	}

	func testExplicitOverrideBeatsReduceMotion() {
		// Only reachable from the notice, so the user has already been told what
		// Reduce Motion was doing before they got the chance to override it.
		let settings = MotionSettings(chipAnimationEnabled: true, ignoresReduceMotion: true)
		XCTAssertTrue(settings.allowsChipAnimation(systemPrefersReducedMotion: true))
	}

	func testOverrideCannotResurrectAnAnimationTheUserTurnedOff() {
		// The override is scoped to the Reduce Motion question only. It must never
		// act as a second, hidden enable switch.
		let settings = MotionSettings(chipAnimationEnabled: false, ignoresReduceMotion: true)
		XCTAssertFalse(settings.allowsChipAnimation(systemPrefersReducedMotion: true))
		XCTAssertFalse(settings.allowsChipAnimation(systemPrefersReducedMotion: false))
	}

	// MARK: - When to speak up

	func testNoticeOnlyAppearsWhenTheUserActuallyAskedForMotion() {
		// A Reduce Motion user who never enabled the animation is not in conflict
		// with anything. Nagging them about a feature they did not ask for is the
		// failure mode this guards.
		let off = MotionSettings(chipAnimationEnabled: false, ignoresReduceMotion: false)
		XCTAssertFalse(off.isSuppressedByReduceMotion(systemPrefersReducedMotion: true))
	}

	func testNoticeAppearsOnlyWhileTheConflictIsLive() {
		let wanted = MotionSettings(chipAnimationEnabled: true, ignoresReduceMotion: false)
		XCTAssertTrue(wanted.isSuppressedByReduceMotion(systemPrefersReducedMotion: true))
		XCTAssertFalse(
			wanted.isSuppressedByReduceMotion(systemPrefersReducedMotion: false),
			"no Reduce Motion, no conflict, no notice")

		let overridden = MotionSettings(chipAnimationEnabled: true, ignoresReduceMotion: true)
		XCTAssertFalse(
			overridden.isSuppressedByReduceMotion(systemPrefersReducedMotion: true),
			"once overridden it is resolved, not still suppressed")
	}

	// MARK: - What the Settings row shows

	private func makeViewModel(reducedMotion: Bool) throws -> (GeneralTabViewModel, URL) {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("reduce-motion-\(UUID().uuidString).json")
		let vm = GeneralTabViewModel(store: CustomizationStore(filePath: tmp.path))
		vm.systemPrefersReducedMotion = { reducedMotion }
		return (vm, tmp)
	}

	func testNoNoticeWithoutReduceMotion() throws {
		let (vm, tmp) = try makeViewModel(reducedMotion: false)
		defer { try? FileManager.default.removeItem(at: tmp) }
		vm.setPlatformChipAnimationEnabled(true)
		XCTAssertEqual(vm.reduceMotionNotice, .none)
	}

	func testNoNoticeWhenTheToggleIsOff() throws {
		let (vm, tmp) = try makeViewModel(reducedMotion: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		XCTAssertEqual(vm.reduceMotionNotice, .none, "never nag about a feature the user did not enable")
	}

	func testSuppressedNoticeExplainsTheDeadToggle() throws {
		let (vm, tmp) = try makeViewModel(reducedMotion: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		vm.setPlatformChipAnimationEnabled(true)
		XCTAssertEqual(
			vm.reduceMotionNotice, .suppressed,
			"turning on a toggle that then does nothing must be explained, not left silent")
	}

	func testOverrideFlipsTheNoticeToConfirmationAndBack() throws {
		let (vm, tmp) = try makeViewModel(reducedMotion: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		vm.setPlatformChipAnimationEnabled(true)

		vm.setPlatformChipAnimationIgnoresReduceMotion(true)
		XCTAssertEqual(vm.reduceMotionNotice, .overridden)

		vm.setPlatformChipAnimationIgnoresReduceMotion(false)
		XCTAssertEqual(vm.reduceMotionNotice, .suppressed, "the override must be reversible from the same spot")
	}

	func testOverrideSurvivesRelaunch() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("reduce-motion-persist-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: tmp) }
		let vm = GeneralTabViewModel(store: CustomizationStore(filePath: tmp.path))
		vm.setPlatformChipAnimationEnabled(true)
		vm.setPlatformChipAnimationIgnoresReduceMotion(true)

		XCTAssertTrue(
			CustomizationJsonReader.read(at: tmp.path).platformChipAnimationIgnoresReduceMotion,
			"a decision this deliberate must not be forgotten on quit")
	}

	func testOverrideDefaultsOffForAnExistingInstall() {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("absent-\(UUID().uuidString).json")
		XCTAssertFalse(
			CustomizationJsonReader.read(at: missing.path).platformChipAnimationIgnoresReduceMotion,
			"nothing may infer an accessibility override; only an explicit choice sets it")
	}

	// MARK: - Ambient motion (the shimmer)

	func testAmbientMotionIsSuppressedByReduceMotionWithoutAnyToggle() {
		// The pill shimmer has no switch of its own — it is on for everyone. It must
		// still answer to Reduce Motion, and the chip's taste toggle must not gate
		// it: someone who never wanted a spinning logo still gets a shimmering pill.
		let chipOff = MotionSettings(chipAnimationEnabled: false, ignoresReduceMotion: false)
		XCTAssertTrue(
			chipOff.allowsAmbientMotion(systemPrefersReducedMotion: false),
			"the shimmer is not governed by the chip toggle")
		XCTAssertFalse(
			chipOff.allowsAmbientMotion(systemPrefersReducedMotion: true),
			"Reduce Motion still suppresses it")
	}

	func testTheOneOverrideCoversAmbientMotionToo() {
		// One override to rule them all: granting it from the chip's notice has to
		// release the shimmer as well, or the switch is lying about its scope.
		let overridden = MotionSettings(chipAnimationEnabled: false, ignoresReduceMotion: true)
		XCTAssertTrue(overridden.allowsAmbientMotion(systemPrefersReducedMotion: true))
	}

	func testNoticeStaysQuietWhenOnlyAmbientMotionIsSuppressed() {
		// A Reduce Motion user who never enabled the chip animation has not been
		// denied anything they asked for. Telling them their shimmer is off would be
		// nagging about a feature they never knew had a name.
		let chipOff = MotionSettings(chipAnimationEnabled: false, ignoresReduceMotion: false)
		XCTAssertFalse(chipOff.isSuppressedByReduceMotion(systemPrefersReducedMotion: true))
	}

	func testSicknessAnimationsAreOptInByDefault() {
		// The sickness aura is a repeatForever scale pulse plus a particle miasma,
		// running for as long as the pet is unwell. Nobody should meet it without
		// having asked for it.
		XCTAssertFalse(PetConfig.HealthLogicSettings.defaults.diseaseAnimationsEnabled)
	}

	// MARK: - End to end through the chip

	func testChipHonoursReduceMotionAndTheOverride() {
		let saved = MotionPolicy.overrideForTesting
		defer { MotionPolicy.overrideForTesting = saved }
		MotionPolicy.overrideForTesting = { true }

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
			styleMask: [.borderless], backing: .buffered, defer: false)
		let chip = PlatformChipView(frame: .zero)
		chip.translatesAutoresizingMaskIntoConstraints = false
		window.contentView?.addSubview(chip)
		NSLayoutConstraint.activate([
			chip.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
			chip.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
		])
		window.contentView?.layoutSubtreeIfNeeded()
		let metrics = GateBadgeLayout.metrics(
			for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160))
		func keys() -> [String] {
			chip.subviews.compactMap { $0 as? NSImageView }.first?.layer?.animationKeys() ?? []
		}

		chip.configure(
			platform: .cursor, metrics: metrics, inFlight: true,
			motionSettings: .init(chipAnimationEnabled: true, ignoresReduceMotion: false))
		XCTAssertTrue(keys().isEmpty, "Reduce Motion wins by default")

		chip.configure(
			platform: .cursor, metrics: metrics, inFlight: true,
			motionSettings: .init(chipAnimationEnabled: true, ignoresReduceMotion: true))
		XCTAssertEqual(keys().count, 1, "the explicit override must actually reach the chip")
	}
}

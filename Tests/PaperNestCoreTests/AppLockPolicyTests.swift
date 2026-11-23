import Foundation
import Testing
@testable import PaperNestCore

/// When PaperNest asks for Face ID or the passcode, and when it must not.
@Suite struct AppLockPolicyTests {
    private let start = ContinuousClock.now
    private func at(_ seconds: Double) -> ContinuousClock.Instant { start.advanced(by: .seconds(seconds)) }

    @Test(arguments: [
        (AppLockPolicy.Grace.immediately, 0.0, true),
        (.immediately, 0.4, true),
        (.oneMinute, 59.9, false),
        (.oneMinute, 60, true),
        (.fiveMinutes, 299, false),
        (.fiveMinutes, 301, true),
        (.fifteenMinutes, 899, false),
        (.fifteenMinutes, 900, true),
    ])
    func graceDecidesWhetherComingBackAsks(grace: AppLockPolicy.Grace, away: Double, asks: Bool) {
        #expect(AppLockPolicy(isEnabled: true, grace: grace).locksOnReturn(after: away) == asks)
    }

    @Test func aTimeThatCannotBeTrustedAsks() {
        let policy = AppLockPolicy(isEnabled: true, grace: .fifteenMinutes)
        for away in [nil, -1, .nan, .infinity, -.infinity] as [Double?] {
            #expect(policy.locksOnReturn(after: away), "\(String(describing: away))")
        }
    }

    @Test func offNeverAsks() {
        let off = AppLockPolicy(isEnabled: false, grace: .immediately)
        #expect(!off.locksOnReturn(after: 10_000))
        var state = AppLockState(policy: off)
        #expect(!state.isLocked && !state.asksOnActive)
        state.becameInactive(policy: off)
        state.enteredBackground(at: at(0), policy: off)
        state.becameActive(at: at(10_000), policy: off)
        #expect(!state.hidesLibrary)
    }

    @Test func aLaunchIsLockedAndAsksOnce() {
        let on = AppLockPolicy(isEnabled: true)
        var state = AppLockState(policy: on)
        #expect(state.isLocked && state.asksOnActive && state.hidesLibrary)
        state.attemptStarted()
        #expect(state.isLocked && !state.asksOnActive)
        state.unlocked()
        #expect(!state.isLocked && !state.hidesLibrary)
    }

    /// The Face ID sheet makes the app inactive and then active again; that
    /// round trip must not lock what was just unlocked.
    @Test func inactiveAloneNeverLocksAgain() {
        let on = AppLockPolicy(isEnabled: true, grace: .immediately)
        var state = AppLockState(policy: on)
        state.attemptStarted()
        state.becameInactive(policy: on)
        state.unlocked()
        state.becameActive(at: at(30), policy: on)
        #expect(!state.isLocked && !state.isCovered && !state.asksOnActive)
    }

    @Test func inactiveCoversWithoutLocking() {
        let on = AppLockPolicy(isEnabled: true, grace: .oneMinute)
        var state = AppLockState(policy: on)
        state.unlocked()
        state.becameInactive(policy: on)
        #expect(state.isCovered && !state.isLocked && state.hidesLibrary)
        state.becameActive(at: at(5), policy: on)
        #expect(!state.hidesLibrary)
    }

    @Test func backgroundWithinGraceComesBackOpen() {
        let on = AppLockPolicy(isEnabled: true, grace: .fiveMinutes)
        var state = AppLockState(policy: on)
        state.unlocked()
        state.becameInactive(policy: on)
        state.enteredBackground(at: at(0), policy: on)
        #expect(state.isCovered && !state.isLocked)
        state.becameActive(at: at(120), policy: on)
        #expect(!state.hidesLibrary)
    }

    @Test func backgroundPastGraceLocksAndAsks() {
        let on = AppLockPolicy(isEnabled: true, grace: .oneMinute)
        var state = AppLockState(policy: on)
        state.unlocked()
        state.enteredBackground(at: at(0), policy: on)
        state.becameActive(at: at(61), policy: on)
        #expect(state.isLocked && state.asksOnActive && !state.isCovered)
    }

    /// Going to the background twice before coming back counts from the
    /// first time.
    @Test func theClockStartsAtTheFirstBackground() {
        let on = AppLockPolicy(isEnabled: true, grace: .oneMinute)
        var state = AppLockState(policy: on)
        state.unlocked()
        state.enteredBackground(at: at(0), policy: on)
        state.enteredBackground(at: at(50), policy: on)
        state.becameActive(at: at(70), policy: on)
        #expect(state.isLocked)
    }

    /// A cancelled or failed attempt leaves it locked and waits for a tap:
    /// coming back to the front does not ask again by itself.
    @Test func aFailedAttemptDoesNotAskAgainOnItsOwn() {
        let on = AppLockPolicy(isEnabled: true, grace: .fiveMinutes)
        var state = AppLockState(policy: on)
        state.attemptStarted()
        state.becameInactive(policy: on)
        state.becameActive(at: at(3), policy: on)
        #expect(state.isLocked && !state.asksOnActive)
    }

    @Test func turningItOnDoesNotLockWhatIsOpen() {
        var state = AppLockState(policy: AppLockPolicy(isEnabled: false))
        let on = AppLockPolicy(isEnabled: true, grace: .immediately)
        state.policyChanged(to: on)
        #expect(!state.hidesLibrary)
        state.enteredBackground(at: at(0), policy: on)
        state.becameActive(at: at(1), policy: on)
        #expect(state.isLocked)
    }

    @Test func turningItOffOpensEverything() {
        let on = AppLockPolicy(isEnabled: true)
        var state = AppLockState(policy: on)
        state.enteredBackground(at: at(0), policy: on)
        let off = AppLockPolicy(isEnabled: false)
        state.policyChanged(to: off)
        #expect(!state.hidesLibrary && !state.asksOnActive)
        state.becameActive(at: at(10_000), policy: off)
        #expect(!state.hidesLibrary)
    }

    @Test func aDeviceThatCannotAskOpens() {
        var state = AppLockState(policy: AppLockPolicy(isEnabled: true))
        state.cannotAuthenticate()
        #expect(!state.isLocked && !state.asksOnActive)
    }
}

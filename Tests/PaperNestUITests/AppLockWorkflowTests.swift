import Foundation
import PaperNestCore
import SwiftUI
import Testing
@testable import PaperNestUI

/// The app lock as the app drives it: the stored setting, the app's phases,
/// and the device's owner check, here a stand-in that answers as told.
@MainActor @Suite struct AppLockWorkflowTests {
    final class Device: AppLockAuthenticating, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [AppLockOutcome]
        private var _reasons: [String] = []
        let canAsk: Bool

        init(_ outcomes: [AppLockOutcome] = [.success], canAsk: Bool = true) {
            self.outcomes = outcomes
            self.canAsk = canAsk
        }

        var reasons: [String] { lock.withLock { _reasons } }

        func availability() -> AppLockAvailability { canAsk ? .available(.faceID) : .cannotAsk }

        func authenticate(reason: String) async -> AppLockOutcome {
            lock.withLock {
                _reasons.append(reason)
                return outcomes.count > 1 ? outcomes.removeFirst() : (outcomes.first ?? .failed)
            }
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var instant = ContinuousClock.now
        var now: ContinuousClock.Instant { lock.withLock { instant } }
        func advance(_ seconds: Double) { lock.withLock { instant = instant.advanced(by: .seconds(seconds)) } }
    }

    private func defaults(enabled: Bool? = nil, grace: AppLockPolicy.Grace? = nil) -> UserDefaults {
        let suite = UserDefaults(suiteName: "AppLockWorkflowTests-\(UUID().uuidString)")!
        if let enabled { suite.set(enabled, forKey: AppLock.enabledKey) }
        if let grace { suite.set(grace.rawValue, forKey: AppLock.graceKey) }
        return suite
    }

    private func make(_ defaults: UserDefaults, _ device: Device, _ clock: Clock = Clock()) -> AppLock {
        AppLock(defaults: defaults, authenticator: device, now: { clock.now })
    }

    /// Lets a prompt started by a phase change run to its end.
    private func settle(_ lock: AppLock) async {
        for _ in 0..<50 {
            await Task.yield()
            if !lock.isAuthenticating { try? await Task.sleep(for: .milliseconds(5)) }
        }
    }

    @Test func offByDefaultAndNothingIsHidden() {
        let lock = make(defaults(), Device())
        #expect(!lock.policy.isEnabled && !lock.hidesLibrary)
    }

    @Test func onIsLockedFromTheFirstFrame() {
        let lock = make(defaults(enabled: true), Device())
        #expect(lock.isLocked && lock.hidesLibrary)
    }

    @Test func comingToTheFrontAsksOnceAndOpens() async {
        let device = Device([.success])
        let lock = make(defaults(enabled: true), device)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(!lock.isLocked && !lock.hidesLibrary)
        #expect(device.reasons == [L10n.appLockReasonUnlock])
    }

    /// A cancelled prompt leaves it locked; the Face ID sheet's own
    /// inactive-and-back does not start another, and Unlock does.
    @Test func aCancelledPromptWaitsForUnlock() async {
        let device = Device([.cancelled, .success])
        let lock = make(defaults(enabled: true), device)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(lock.isLocked && lock.lastAttemptFailed)
        lock.scenePhaseChanged(.inactive)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(device.reasons.count == 1, "asked again on its own")
        await lock.unlock()
        #expect(!lock.isLocked && !lock.lastAttemptFailed)
        #expect(device.reasons.count == 2)
    }

    /// Cancelled at launch, then left and come back to: asked again without
    /// a tap, and this time opened.
    @Test func comingBackAfterACancelAsksAgain() async {
        let device = Device([.cancelled, .success])
        let lock = make(defaults(enabled: true), device)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(lock.isLocked)
        lock.scenePhaseChanged(.inactive)
        lock.scenePhaseChanged(.background)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(!lock.isLocked)
        #expect(device.reasons.count == 2)
    }

    @Test func turningItOnAsksFirstAndAFailureChangesNothing() async {
        let store = defaults()
        let device = Device([.failed, .success])
        let lock = make(store, device)
        #expect(await lock.setEnabled(true) == false)
        #expect(!lock.policy.isEnabled && store.object(forKey: AppLock.enabledKey) == nil)
        #expect(await lock.setEnabled(true))
        #expect(lock.policy.isEnabled && store.bool(forKey: AppLock.enabledKey))
        // Turning it on does not lock what is open.
        #expect(!lock.hidesLibrary)
        #expect(device.reasons == [L10n.appLockReasonTurnOn, L10n.appLockReasonTurnOn])
    }

    @Test func turningItOffAsksFirst() async {
        let store = defaults(enabled: true)
        let device = Device([.success])
        let lock = make(store, device)
        await lock.unlock()
        #expect(await lock.setEnabled(false))
        #expect(!lock.policy.isEnabled && !store.bool(forKey: AppLock.enabledKey))
        #expect(device.reasons.last == L10n.appLockReasonTurnOff)
    }

    /// A device with no passcode cannot ask: the lock opens, cannot be turned
    /// on, and nobody is asked anything.
    @Test func aDeviceThatCannotAskNeverShutsTheLibrary() async {
        let device = Device(canAsk: false)
        let lock = make(defaults(enabled: true), device)
        #expect(!lock.isLocked)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(!lock.isLocked)
        let other = make(defaults(), device)
        #expect(await other.setEnabled(true) == false)
        #expect(device.reasons.isEmpty)
    }

    @Test func theTimeAwayDecides() async {
        let clock = Clock()
        let device = Device([.success])
        let lock = make(defaults(enabled: true, grace: .oneMinute), device, clock)
        await lock.unlock()
        lock.scenePhaseChanged(.inactive)
        #expect(lock.hidesLibrary && !lock.isLocked, "covered while not in front")
        lock.scenePhaseChanged(.background)
        clock.advance(30)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        #expect(!lock.hidesLibrary)
        lock.scenePhaseChanged(.background)
        clock.advance(61)
        lock.scenePhaseChanged(.active)
        await settle(lock)
        // Asked on its own, and the stand-in said yes.
        #expect(!lock.isLocked)
        #expect(device.reasons.count == 2)
    }

    @Test func graceIsKeptForTheNextLaunch() {
        let store = defaults(enabled: true)
        let lock = make(store, Device())
        lock.setGrace(.fifteenMinutes)
        #expect(make(store, Device()).policy == AppLockPolicy(isEnabled: true, grace: .fifteenMinutes))
    }
}

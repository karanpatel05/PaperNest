import Foundation
import LocalAuthentication
import Observation
import PaperNestCore
import SwiftUI

/// Which way the device proves it is its owner, for naming it on screen.
public enum AppLockBiometry: Sendable, Equatable {
    case faceID, touchID, opticID
    /// The device passcode only.
    case passcode
}

public enum AppLockAvailability: Sendable, Equatable {
    case available(AppLockBiometry)
    /// The device has no passcode, so nothing can be asked.
    case cannotAsk

    var biometry: AppLockBiometry? {
        if case .available(let biometry) = self { return biometry }
        return nil
    }
}

public enum AppLockOutcome: Sendable, Equatable {
    case success, cancelled, failed
}

/// The device's own owner check. PaperNest keeps no passcode of its own.
public protocol AppLockAuthenticating: Sendable {
    func availability() -> AppLockAvailability
    func authenticate(reason: String) async -> AppLockOutcome
}

/// Face ID, Touch ID or Optic ID, falling back to the device passcode
/// (`.deviceOwnerAuthentication`), so a face that is not recognised never
/// shuts anyone out of their own library.
struct DeviceOwnerAuthenticator: AppLockAuthenticating {
    func availability() -> AppLockAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .cannotAsk }
        // Read after `canEvaluatePolicy`, which is what sets it.
        switch context.biometryType {
        case .faceID: return .available(.faceID)
        case .touchID: return .available(.touchID)
        case .opticID: return .available(.opticID)
        default: return .available(.passcode)
        }
    }

    func authenticate(reason: String) async -> AppLockOutcome {
        // A new context each time, so one success is never reused for the next.
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

#if DEBUG
/// UI-test seam, DEBUG builds only. `-PaperNestDebugAppLock <script>` stands
/// in for the device's prompt (`LAContext`) and nothing else. The script is
/// the answers in order, comma-separated, the last one repeating:
/// `succeed`, `fail`, `cancel` — so `succeed,fail,succeed` turns the lock on,
/// refuses the next prompt, then opens. `cannotask` is a device with no
/// passcode. It reports Face ID.
final class ScriptedAppLockAuthenticator: AppLockAuthenticating, @unchecked Sendable {
    private let answers: [AppLockOutcome]
    private let cannotAsk: Bool
    private let lock = NSLock()
    private var attempts = 0

    init(script: String) {
        cannotAsk = script == "cannotask"
        answers = script.split(separator: ",").map {
            switch $0.trimmingCharacters(in: .whitespaces) {
            case "succeed": .success
            case "cancel": .cancelled
            default: .failed
            }
        }
    }

    func availability() -> AppLockAvailability { cannotAsk ? .cannotAsk : .available(.faceID) }

    func authenticate(reason: String) async -> AppLockOutcome {
        try? await Task.sleep(for: .milliseconds(300))
        let attempt = lock.withLock { attempts += 1; return attempts }
        guard !answers.isEmpty else { return .failed }
        return answers[min(attempt, answers.count) - 1]
    }
}
#endif

/// The app lock for this device: whether it is on, how long PaperNest may
/// stay in the background, and what to show right now. A device setting in
/// `UserDefaults`, not library data: it is not synced and travels with no
/// backup of the library.
@MainActor @Observable public final class AppLock {
    static let enabledKey = "PaperNestAppLockEnabled"
    static let graceKey = "PaperNestAppLockGrace"

    public private(set) var policy: AppLockPolicy
    private(set) var state: AppLockState
    private(set) var availability: AppLockAvailability
    private(set) var isAuthenticating = false
    /// The last attempt to unlock was cancelled or failed.
    private(set) var lastAttemptFailed = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any AppLockAuthenticating
    @ObservationIgnored private let now: @Sendable () -> ContinuousClock.Instant

    /// Reads the setting at once, so the very first frame is already hidden.
    public convenience init() {
        self.init(defaults: .standard, authenticator: Self.deviceAuthenticator())
    }

    init(defaults: UserDefaults, authenticator: any AppLockAuthenticating,
         now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.defaults = defaults
        self.authenticator = authenticator
        self.now = now
        let policy = Self.storedPolicy(in: defaults)
        self.policy = policy
        let availability = authenticator.availability()
        self.availability = availability
        var state = AppLockState(policy: policy)
        if availability == .cannotAsk { state.cannotAuthenticate() }
        self.state = state
    }

    /// Nothing of the library is to be seen: the lock screen, or the cover
    /// while PaperNest is not in front.
    public var hidesLibrary: Bool { state.hidesLibrary }
    public var isLocked: Bool { state.isLocked }

    /// Called with the app's phase (all its windows together).
    public func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .inactive:
            state.becameInactive(policy: policy)
        case .background:
            state.enteredBackground(at: now(), policy: policy)
        case .active:
            availability = authenticator.availability()
            state.becameActive(at: now(), policy: policy)
            if state.isLocked, availability == .cannotAsk { state.cannotAuthenticate() }
            if state.isLocked, state.asksOnActive { Task { await unlock() } }
        @unknown default:
            break
        }
    }

    /// Asks the device to prove its owner. Locked until it does.
    public func unlock() async {
        guard state.isLocked, !isAuthenticating else { return }
        availability = authenticator.availability()
        if availability == .cannotAsk {
            state.cannotAuthenticate()
            return
        }
        isAuthenticating = true
        state.attemptStarted()
        let outcome = await authenticator.authenticate(reason: L10n.appLockReasonUnlock)
        isAuthenticating = false
        lastAttemptFailed = outcome != .success
        if outcome == .success { state.unlocked() }
    }

    /// Turning the lock on or off asks first, so it can never be switched on
    /// by a device that cannot open it again, nor off by someone who could
    /// not open it. Returns whether it changed.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != policy.isEnabled, !isAuthenticating else { return false }
        availability = authenticator.availability()
        guard availability != .cannotAsk else { return false }
        isAuthenticating = true
        let outcome = await authenticator.authenticate(
            reason: enabled ? L10n.appLockReasonTurnOn : L10n.appLockReasonTurnOff)
        isAuthenticating = false
        guard outcome == .success else { return false }
        var next = policy
        next.isEnabled = enabled
        apply(next)
        return true
    }

    public func setGrace(_ grace: AppLockPolicy.Grace) {
        guard grace != policy.grace else { return }
        var next = policy
        next.grace = grace
        apply(next)
    }

    private func apply(_ next: AppLockPolicy) {
        policy = next
        defaults.set(next.isEnabled, forKey: Self.enabledKey)
        defaults.set(next.grace.rawValue, forKey: Self.graceKey)
        state.policyChanged(to: next)
    }

    static func storedPolicy(in defaults: UserDefaults) -> AppLockPolicy {
        #if DEBUG
        if defaults.bool(forKey: "PaperNestDebugAppLockReset") {
            defaults.removeObject(forKey: enabledKey)
            defaults.removeObject(forKey: graceKey)
        }
        // UI tests that do not ask for the lock never meet it, even if an
        // earlier test left it on in this simulator.
        if defaults.string(forKey: "PaperNestLibraryPath") != nil,
           defaults.string(forKey: "PaperNestDebugAppLock") == nil {
            return AppLockPolicy()
        }
        #endif
        let grace = AppLockPolicy.Grace(rawValue: defaults.integer(forKey: graceKey)) ?? .immediately
        return AppLockPolicy(isEnabled: defaults.bool(forKey: enabledKey), grace: grace)
    }

    static func deviceAuthenticator() -> any AppLockAuthenticating {
        #if DEBUG
        if let script = UserDefaults.standard.string(forKey: "PaperNestDebugAppLock") {
            return ScriptedAppLockAuthenticator(script: script)
        }
        #endif
        return DeviceOwnerAuthenticator()
    }
}

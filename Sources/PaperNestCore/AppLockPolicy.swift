import Foundation

/// When PaperNest asks for Face ID, Touch ID or the device passcode before
/// showing anything. The lock hides the library on screen; it does not
/// encrypt anything, and the app keeps no passcode of its own.
public struct AppLockPolicy: Hashable, Sendable {
    /// How long PaperNest may stay in the background before it asks again.
    public enum Grace: Int, CaseIterable, Hashable, Sendable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900

        public var seconds: Double { Double(rawValue) }
    }

    public var isEnabled: Bool
    public var grace: Grace

    public init(isEnabled: Bool = false, grace: Grace = .immediately) {
        self.isEnabled = isEnabled
        self.grace = grace
    }

    /// Whether coming back after `elapsed` seconds in the background asks
    /// again. A time that cannot be trusted (none, negative, not a number)
    /// asks: the lock fails closed.
    public func locksOnReturn(after elapsed: Double?) -> Bool {
        guard isEnabled else { return false }
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return true }
        return elapsed >= grace.seconds
    }
}

/// What the lock shows from moment to moment, driven by the app's phase.
///
/// Only going to the **background** starts the clock for asking again.
/// Becoming inactive does not: the Face ID sheet itself makes the app
/// inactive, so a lock keyed on that would close again the moment it opened.
/// Inactive does put up the cover, which keeps the documents out of the app
/// switcher's picture.
public struct AppLockState: Hashable, Sendable {
    /// Asking for Face ID or the passcode; nothing of the library shows.
    public private(set) var isLocked: Bool
    /// The library is hidden while PaperNest is not in front, locked or not.
    public private(set) var isCovered: Bool = false
    /// Whether to ask on its own the next time PaperNest is in front. Off
    /// after an attempt, so a cancelled or failed one waits for a tap on
    /// Unlock instead of asking again and again; on again once PaperNest has
    /// really been away (in the background) and comes back still locked.
    public private(set) var asksOnActive: Bool
    private var backgroundedAt: ContinuousClock.Instant?

    /// A fresh launch: locked whenever the lock is on.
    public init(policy: AppLockPolicy) {
        isLocked = policy.isEnabled
        asksOnActive = policy.isEnabled
    }

    /// Visible to the person: the lock screen or the plain cover.
    public var hidesLibrary: Bool { isLocked || isCovered }

    public mutating func becameInactive(policy: AppLockPolicy) {
        if policy.isEnabled { isCovered = true }
    }

    public mutating func enteredBackground(at now: ContinuousClock.Instant, policy: AppLockPolicy) {
        guard policy.isEnabled else { return }
        isCovered = true
        if backgroundedAt == nil { backgroundedAt = now }
    }

    public mutating func becameActive(at now: ContinuousClock.Instant, policy: AppLockPolicy) {
        if let since = backgroundedAt {
            backgroundedAt = nil
            let away = since.duration(to: now)
            let seconds = Double(away.components.seconds) + Double(away.components.attoseconds) / 1e18
            if !isLocked, policy.locksOnReturn(after: seconds) {
                isLocked = true
                asksOnActive = true
            } else if isLocked {
                // Left while still locked and come back: ask, as on any
                // return. Only the prompt's own inactive-and-back is quiet.
                asksOnActive = true
            }
        }
        if !policy.isEnabled { isLocked = false; asksOnActive = false }
        isCovered = false
    }

    /// An attempt to unlock has started; whatever it ends in, PaperNest does
    /// not ask again on its own.
    public mutating func attemptStarted() { asksOnActive = false }

    public mutating func unlocked() {
        isLocked = false
        asksOnActive = false
    }

    /// Turning the lock on (after proving it can be opened) does not lock
    /// what is already on screen; turning it off opens it.
    public mutating func policyChanged(to policy: AppLockPolicy) {
        if !policy.isEnabled {
            isLocked = false
            isCovered = false
            asksOnActive = false
            backgroundedAt = nil
        }
    }

    /// The device can no longer ask (its passcode was removed). The lock
    /// cannot be satisfied, and whoever removed the passcode knew it, so the
    /// library opens rather than staying shut for good.
    public mutating func cannotAuthenticate() {
        isLocked = false
        asksOnActive = false
    }
}

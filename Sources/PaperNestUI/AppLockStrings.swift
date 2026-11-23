import Foundation

/// The app lock's words. Their keys are the block marked "App lock" in the
/// en/fr/es `Localizable.strings`; `LocalizationTests` reads this file too.
extension L10n {
    static var appLockSection: String { tr("applock.section") }
    static var appLockRequireFaceID: String { tr("applock.require.faceid") }
    static var appLockRequireTouchID: String { tr("applock.require.touchid") }
    static var appLockRequireOpticID: String { tr("applock.require.opticid") }
    static var appLockRequirePasscode: String { tr("applock.require.passcode") }
    static var appLockFooter: String { tr("applock.footer") }
    static var appLockUnavailable: String { tr("applock.unavailable") }
    static var appLockUnchanged: String { tr("applock.unchanged") }
    static var appLockGraceHeader: String { tr("applock.grace.header") }
    static var appLockGraceImmediately: String { tr("applock.grace.immediately") }
    static var appLockGraceOneMinute: String { tr("applock.grace.oneminute") }
    static var appLockGraceFiveMinutes: String { tr("applock.grace.fiveminutes") }
    static var appLockGraceFifteenMinutes: String { tr("applock.grace.fifteenminutes") }
    static var appLockLocked: String { tr("applock.locked") }
    static var appLockUnlock: String { tr("applock.unlock") }
    static var appLockStillLocked: String { tr("applock.stilllocked") }
    static var appLockReasonUnlock: String { tr("applock.reason.unlock") }
    static var appLockReasonTurnOn: String { tr("applock.reason.on") }
    static var appLockReasonTurnOff: String { tr("applock.reason.off") }
}

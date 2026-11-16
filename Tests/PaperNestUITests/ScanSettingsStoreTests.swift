import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// The scanner's defaults as they are kept between launches. Each test has
/// preferences of its own, so nothing here reads or writes the app's.
@Suite struct ScanSettingsStoreTests {
    private func scratch() throws -> (defaults: UserDefaults, name: String) {
        let name = "papernest.scan-settings-tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aScannerNeverOpenedBeforeHasTheStandardDefaults() throws {
        let (defaults, name) = try scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ScanSettingsStore.load(from: defaults) == .standard)
    }

    @Test func whatIsSavedIsWhatTheNextLaunchReads() throws {
        let (defaults, name) = try scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        let chosen = ScanSettings(mode: .card, preset: .grayscale, startsAutomatic: true)
        ScanSettingsStore.save(chosen, to: defaults)
        #expect(ScanSettingsStore.load(from: defaults) == chosen)
        // A second set of preferences on the same name is what a relaunch sees.
        #expect(ScanSettingsStore.load(from: try #require(UserDefaults(suiteName: name))) == chosen)
        ScanSettingsStore.save(.standard, to: defaults)
        #expect(ScanSettingsStore.load(from: defaults) == .standard)
    }

    /// UI tests pin the defaults with launch arguments, which arrive as text.
    @Test func textFromALaunchArgumentIsReadLikeAStoredValue() throws {
        let (defaults, name) = try scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("whiteboard", forKey: "scanner.defaultMode")
        defaults.set("highContrast", forKey: "scanner.defaultPreset")
        defaults.set("YES", forKey: "scanner.autoOnEntry")
        #expect(ScanSettingsStore.load(from: defaults) == ScanSettings(mode: .whiteboard, preset: .highContrast, startsAutomatic: true))
        defaults.set("NO", forKey: "scanner.autoOnEntry")
        #expect(!ScanSettingsStore.load(from: defaults).startsAutomatic)
    }

    @Test func aStoredValueFromAnotherVersionDoesNotStopTheScannerOpening() throws {
        let (defaults, name) = try scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("book", forKey: "scanner.defaultMode")
        defaults.set(7, forKey: "scanner.defaultPreset")
        #expect(ScanSettingsStore.load(from: defaults) == .standard)
    }
}

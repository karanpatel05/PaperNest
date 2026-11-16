import Foundation
import PaperNestCore

/// Where the scanner's defaults are kept: three preferences, nothing in the
/// library. A value that is missing or unknown falls back by itself
/// (`ScanSettings.init(storedMode:…)`).
enum ScanSettingsStore {
    static let modeKey = "scanner.defaultMode"
    static let presetKey = "scanner.defaultPreset"
    static let automaticKey = "scanner.autoOnEntry"

    static func load(from defaults: UserDefaults = .standard) -> ScanSettings {
        ScanSettings(storedMode: defaults.string(forKey: modeKey), storedPreset: defaults.string(forKey: presetKey),
                     // `bool` reads "YES" from a launch argument as well as a stored true.
                     storedStartsAutomatic: defaults.object(forKey: automaticKey) == nil ? nil : defaults.bool(forKey: automaticKey))
    }

    static func save(_ settings: ScanSettings, to defaults: UserDefaults = .standard) {
        let stored = settings.stored
        defaults.set(stored.mode, forKey: modeKey)
        defaults.set(stored.preset, forKey: presetKey)
        defaults.set(stored.startsAutomatic, forKey: automaticKey)
    }
}

#if os(iOS)
import SwiftUI

/// The scanner's defaults: the mode it opens in, the filter a new capture
/// starts with, and whether the automatic shutter is on when it opens.
/// Nothing here changes a page already scanned.
struct ScannerSettingsSheet: View {
    @Binding var settings: ScanSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.scannerSettingsDefaultMode) {
                    ForEach(ScanCaptureMode.allCases, id: \.self) { mode in
                        option(mode.title, isOn: settings.mode == mode, id: "mode.\(mode.rawValue)") { settings.mode = mode }
                    }
                }
                Section {
                    ForEach(ScanPreset.allCases, id: \.self) { preset in
                        option(preset.title, isOn: settings.preset == preset, id: "preset.\(preset.rawValue)") { settings.preset = preset }
                    }
                } header: {
                    Text(L10n.scannerSettingsDefaultFilter)
                } footer: {
                    Text(L10n.scannerSettingsNote)
                }
                Section {
                    Toggle(L10n.scannerSettingsAutoOnEntry, isOn: $settings.startsAutomatic)
                        .accessibilityIdentifier("scanner.settings.auto")
                }
            }
            .navigationTitle(L10n.scannerSettings)
            .navigationBarTitleDisplayMode(.inline)
            // Done is here and not in the top bar: on a short screen under
            // iOS 27.1 the bar and everything in it goes once the list
            // scrolls, and the last setting is only reached by scrolling.
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(L10n.done).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent).tint(ScannerChrome.purple)
                .accessibilityIdentifier("scanner.settings.done")
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(ScannerChrome.panel)
            }
        }
        .tint(Theme.accent)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
    }

    /// One row per choice, the chosen one ticked. Rows, not a pop-up menu: a
    /// menu cuts French and Spanish names short.
    private func option(_ title: String, isOn: Bool, id: String, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scanner.settings.\(id)")
        .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
#endif

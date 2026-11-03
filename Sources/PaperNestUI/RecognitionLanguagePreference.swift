import Foundation
import PaperNestRender

/// Which languages the reader has asked text recognition to read in.
///
/// Stored as one comma-separated string so `@AppStorage` can observe it —
/// `UserDefaults` holds arrays perfectly well, but SwiftUI will not watch one,
/// and a settings screen that does not update as it is used is worse than a
/// slightly awkward encoding.
///
/// Empty means "no choice", which leaves recognition on its defaults. That is
/// deliberately not the same as "none": there is no way to ask for no
/// recognition here, and an empty stored value must never be read as one.
enum RecognitionLanguagePreference {
    static let key = "recognitionLanguages"

    /// The codes in a stored value, in the order they were chosen.
    ///
    /// Blank entries and stray spaces are dropped rather than passed on: they
    /// reach Vision as languages it cannot read, and the choice would then be
    /// reported back to the reader as impossible when nothing was wrong with
    /// it. Duplicates are left for `resolve` to remove, which is where every
    /// other list is cleaned.
    static func codes(from stored: String) -> [String] {
        stored.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func stored(from codes: [String]) -> String {
        codes.joined(separator: ",")
    }

    /// The reader's choice as it stands now, for code outside a view.
    static var codes: [String] {
        codes(from: UserDefaults.standard.string(forKey: key) ?? "")
    }

    /// What recognition should actually read in, asked of this device.
    static func choice() -> TextRecognizer.LanguageChoice {
        TextRecognizer.resolve(override: codes, available: TextRecognizer.availableLanguages())
    }

    /// A language's name in the reader's own language, falling back to the
    /// code itself — an unnamed row is worse than a technical one.
    static func name(of code: String) -> String {
        Locale.current.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forLanguageCode: code)
            ?? code
    }
}

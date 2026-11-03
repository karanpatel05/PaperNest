import Foundation
import Testing
@testable import PaperNestUI

/// The stored form of the reader's recognition-language choice.
///
/// Worth its own tests because the value is a hand-rolled string: a stray
/// space or an empty entry reaches Vision as a language it cannot read, and
/// the screen would then tell the reader their choice was impossible when
/// nothing was wrong with it.
@Suite struct RecognitionLanguagePreferenceTests {
    @Test func aChoiceSurvivesBeingStoredAndReadBack() {
        let codes = ["de-DE", "en-US"]

        let read = RecognitionLanguagePreference.codes(
            from: RecognitionLanguagePreference.stored(from: codes))

        #expect(read == codes)
    }

    @Test func noChoiceIsAnEmptyList() {
        #expect(RecognitionLanguagePreference.codes(from: "").isEmpty)
        #expect(RecognitionLanguagePreference.stored(from: []).isEmpty)
    }

    /// Spaces and empty entries are the two things a hand-edited or
    /// half-written value actually contains.
    @Test func straySpacesAndEmptyEntriesAreDropped() {
        #expect(RecognitionLanguagePreference.codes(from: " de-DE , ,en-US,") == ["de-DE", "en-US"])
    }

    /// The order chosen is the order Vision is given, so it has to survive.
    @Test func theOrderChosenSurvives() {
        #expect(RecognitionLanguagePreference.codes(from: "it-IT,en-US,de-DE")
                == ["it-IT", "en-US", "de-DE"])
    }

    /// An unknown code is shown as itself rather than as a blank row.
    @Test func everyCodeGetsSomethingToShow() {
        #expect(!RecognitionLanguagePreference.name(of: "en-US").isEmpty)
        #expect(RecognitionLanguagePreference.name(of: "zz-ZZ").isEmpty == false)
    }
}

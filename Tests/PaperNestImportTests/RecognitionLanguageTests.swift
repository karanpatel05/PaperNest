import Foundation
import Testing
@testable import PaperNestRender

/// F4: choosing which languages recognition reads in.
///
/// Until this existed, recognition always asked Vision for English, French
/// and Spanish, whatever the document was and whatever the reader wanted.
/// Someone scanning German could not say so, and Vision weights the list it
/// is given, so the wrong list is not merely unhelpful — it makes the reading
/// worse.
///
/// The resolution is pure and `available` is passed in, so these tests do not
/// depend on which languages this particular machine's Vision can read.
@Suite struct RecognitionLanguageTests {
    private let available = ["en-US", "fr-FR", "es-ES", "de-DE", "it-IT"]
    private let fallback = ["en-US", "fr-FR", "es-ES"]

    @Test func withNoChoiceTheDefaultsAreUsed() {
        let choice = TextRecognizer.resolve(override: [], fallback: fallback, available: available)

        #expect(choice.using == fallback)
        #expect(choice.unavailable.isEmpty)
    }

    /// A choice replaces the defaults rather than adding to them: someone who
    /// says "German" does not want English guesses mixed in, and every extra
    /// language costs accuracy on the others.
    @Test func aChoiceReplacesTheDefaults() {
        let choice = TextRecognizer.resolve(override: ["de-DE"], fallback: fallback, available: available)

        #expect(choice.using == ["de-DE"])
        #expect(choice.unavailable.isEmpty)
    }

    /// Vision weights the order it is given, so the order asked for is kept.
    @Test func theOrderAskedForIsKept() {
        let choice = TextRecognizer.resolve(override: ["it-IT", "en-US"], fallback: fallback, available: available)

        #expect(choice.using == ["it-IT", "en-US"])
    }

    /// The supported set differs by OS version, so a choice made on one
    /// machine may be half impossible on another. What can be read is used,
    /// and what cannot is **reported** rather than dropped in silence.
    @Test func whatThisDeviceCannotReadIsReportedNotDropped() {
        let choice = TextRecognizer.resolve(override: ["de-DE", "ja-JP"], fallback: fallback, available: available)

        #expect(choice.using == ["de-DE"])
        #expect(choice.unavailable == ["ja-JP"])
    }

    /// A choice this device cannot honour at all must not leave recognition
    /// with an empty list, which reads nothing: it falls back, and still says
    /// the choice could not be used.
    @Test func aChoiceThatIsEntirelyImpossibleFallsBackAndSaysSo() {
        let choice = TextRecognizer.resolve(override: ["ja-JP", "ko-KR"], fallback: fallback, available: available)

        #expect(choice.using == fallback)
        #expect(choice.unavailable == ["ja-JP", "ko-KR"])
    }

    /// The same language twice would weight it twice for no reason.
    @Test func aLanguageAskedForTwiceIsUsedOnce() {
        let choice = TextRecognizer.resolve(override: ["de-DE", "de-DE", "en-US"],
                                            fallback: fallback, available: available)

        #expect(choice.using == ["de-DE", "en-US"])
    }

    /// Even the defaults are checked against the device, for the same reason.
    @Test func defaultsAreCheckedAgainstTheDeviceToo() {
        let choice = TextRecognizer.resolve(override: [], fallback: fallback, available: ["en-US"])

        #expect(choice.using == ["en-US"])
    }

    /// Nothing readable at all is an empty list, not a guess. Recognising
    /// with a language the reader did not ask for produces confident
    /// nonsense, and `recognize` already refuses an empty list outright.
    @Test func aDeviceThatCanReadNoneOfThemGetsNothingRatherThanAGuess() {
        let choice = TextRecognizer.resolve(override: [], fallback: fallback, available: ["ja-JP"])

        #expect(choice.using.isEmpty)
    }
}

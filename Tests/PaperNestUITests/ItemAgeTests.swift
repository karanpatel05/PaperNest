import Foundation
import Testing
@testable import PaperNestUI

/// How long ago a document changed, as its tile says it. In French the
/// abbreviated style wrote every past age with a minus sign ("-5 s",
/// "-3 j"); each language must read as words.
@Suite struct ItemAgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [("en_US", "ago"), ("fr_FR", "il y a"), ("es_ES", "hace")])
    func agesReadAsWordsWithNoSign(locale: String, word: String) {
        for seconds: Double in [5, 200, 7_200, 259_200, 3_456_000] {
            let age = ItemCell.age(of: now.addingTimeInterval(-seconds), relativeTo: now, locale: Locale(identifier: locale))
            #expect(age.contains(word), "\(locale), \(seconds) s ago: “\(age)”")
            #expect(!age.hasPrefix("-") && !age.hasPrefix("+") && !age.hasPrefix("\u{2212}"), "\(locale): “\(age)”")
        }
    }
}

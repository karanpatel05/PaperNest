import Foundation
import Testing
@testable import PaperNestUI

@Suite struct LocalizationTests {
    static let languages = ["en", "fr", "es"]

    static func bundle(_ language: String) throws -> Bundle {
        let path = try #require(ResourceBundle.ui.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    static func table(_ language: String) throws -> [String: String] {
        let bundle = try bundle(language)
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    /// Keys referenced via `tr("…")` / `plural("…")` from Localization.swift
    /// and from any `<Feature>Strings.swift` beside it, a feature's own
    /// `extension L10n` (the app lock's, `AppLockStrings.swift`, is the first).
    static func referencedKeys() throws -> (strings: Set<String>, plurals: Set<String>) {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PaperNestUI")
        let sources = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == "Localization.swift" || $0.lastPathComponent.hasSuffix("Strings.swift") }
        #expect(sources.contains { $0.lastPathComponent == "Localization.swift" })
        let text = try sources.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        func keys(_ pattern: String) throws -> Set<String> {
            let regex = try NSRegularExpression(pattern: pattern)
            return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            })
        }
        return (try keys(#"\btr\("([a-zA-Z0-9_.]+)""#), try keys(#"\bplural\("([a-zA-Z0-9_.]+)""#))
    }

    /// Format specifiers in order of argument position.
    static func specifiers(_ value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(lld|ld|d|@)"#)
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        return matches.enumerated().map { offset, match in
            let position = Range(match.range(at: 1), in: value).map { String(value[$0]) } ?? String(offset + 1)
            let type = String(value[Range(match.range(at: 2), in: value)!])
            return "\(position):\(type)"
        }.sorted()
    }

    @Test func everyReferencedKeyExistsInEveryLanguage() throws {
        let referenced = try Self.referencedKeys()
        #expect(referenced.strings.count > 100)
        for language in Self.languages {
            let table = try Self.table(language)
            let missing = referenced.strings.subtracting(table.keys)
            #expect(missing.isEmpty, "\(language) is missing \(missing.sorted())")
        }
    }

    @Test func allLanguagesHaveTheSameKeysAndFormatArguments() throws {
        let english = try Self.table("en")
        for language in ["fr", "es"] {
            let table = try Self.table(language)
            #expect(Set(table.keys) == Set(english.keys), "\(language) key set differs")
            for (key, value) in table {
                let source = try #require(english[key])
                #expect(Self.specifiers(value) == Self.specifiers(source), "\(language) \(key): \(value)")
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) \(key) is empty")
            }
        }
    }

    @Test func noTableKeyIsUnused() throws {
        let referenced = try Self.referencedKeys()
        let unused = Set(try Self.table("en").keys).subtracting(referenced.strings)
        #expect(unused.isEmpty, "unused keys: \(unused.sorted())")
    }

    @Test(arguments: [
        ("en", 1, "1 page"), ("en", 2, "2 pages"), ("en", 0, "0 pages"),
        // French treats 0 and 1 as singular.
        ("fr", 0, "0 page"), ("fr", 1, "1 page"), ("fr", 2, "2 pages"),
        ("es", 1, "1 página"), ("es", 5, "5 páginas"),
    ])
    func pageCountPluralizesPerLanguage(language: String, count: Int, expected: String) throws {
        let format = try Self.bundle(language).localizedString(forKey: "item.pageCount", value: nil, table: nil)
        #expect(String(format: format, locale: Locale(identifier: language), count) == expected)
    }

    @Test func frenchUsesFrenchTypography() throws {
        let fr = try Self.table("fr")
        // « » quotes with no-break spaces, and a narrow no-break space before ?
        #expect(fr["error.import.title"] == "Impossible d’importer «\u{00A0}%@\u{00A0}»")
        #expect(fr["deletePermanently.title"]?.hasSuffix("\u{202F}?") == true)
        for (key, value) in fr {
            #expect(!value.contains(" ?") && !value.contains(" :") && !value.contains("« "), "\(key): \(value)")
        }
    }
}

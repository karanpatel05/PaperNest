import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender
// In the package the writing comes from the test-support module; in the
// iOS app's canvas test target the file is compiled in alongside this one.
#if canImport(PaperNestTestSupport)
import PaperNestTestSupport
#endif

/// Handwriting read by on-device Vision. The writing is synthetic: printed
/// single-stroke letters with a wobble (`SyntheticHandwriting`), not anyone's
/// real hand, and no Apple Pencil was involved. What passes here says that
/// this kind of writing is read, and that nothing is made up when it is not.
@Suite struct HandwritingRecognitionTests {
    /// `text` as pen strokes, the way the editor stores them: source points,
    /// a top-left origin, a width that varies a little along each stroke.
    static func ink(_ text: String, size: CGFloat = 18, width: Double = 2.2, tool: InkStroke.Tool = .pen,
                    origin: CGPoint = CGPoint(x: 60, y: 140), seed: UInt64 = 1) throws -> [InkStroke] {
        try SyntheticHandwriting.strokes(text, origin: origin, size: size, seed: seed).map { path in
            InkStroke(tool: tool, color: RGBAColor(red: 0.1, green: 0.15, blue: 0.55), width: width,
                      points: path.enumerated().map { index, point in
                          InkPoint(x: point.x, y: point.y, widthScale: 0.85 + Double(index * 7 % 10) * 0.03,
                                   time: Double(index) * 0.012)
                      })
        }
    }

    static func read(_ strokes: [InkStroke], languages: [String] = TextRecognizer.preferredLanguages)
        async throws -> [HandwritingRecognizer.Line] {
        try await HandwritingRecognizer(languages: languages).recognize(strokes)
    }

    static func texts(_ lines: [HandwritingRecognizer.Line]) -> [String] { lines.map { $0.text } }

    /// Letters, spaces and case aside: what was written.
    static func letters(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter }
    }

    @Test func aWrittenWordIsRead() async throws {
        let lines = try await Self.read(try Self.ink("hello"))
        #expect(lines.count == 1)
        #expect(Self.letters(lines.first?.text ?? "") == "hello", "read \(Self.texts(lines))")
    }

    @Test func twoLinesAreReadTopFirst() async throws {
        let lines = try await Self.read(try Self.ink("send notes\nplan lunch"))
        #expect(lines.map { Self.letters($0.text) } == ["sendnotes", "planlunch"], "read \(Self.texts(lines))")
        if lines.count == 2 { #expect(lines[0].bounds.maxY <= lines[1].bounds.minY + 1, "the first line is above") }
    }

    /// The box a line comes back with lies over the strokes it was read from,
    /// in source space: the one flip in `picture` and the one in
    /// `TextRecognizer` cancel out.
    @Test func aLinesBoxCoversItsStrokes() async throws {
        let strokes = try Self.ink("hello", origin: CGPoint(x: 210, y: 430))
        let ink = try #require(HandwritingRecognizer.bounds(of: strokes))
        let line = try #require(try await Self.read(strokes).first)
        #expect(line.bounds.intersects(ink))
        #expect(abs(line.bounds.midX - ink.midX) < ink.width * 0.25, "\(line.bounds) against \(ink)")
        #expect(abs(line.bounds.midY - ink.midY) < ink.height * 0.5, "\(line.bounds) against \(ink)")
    }

    @Test func smallAndLargeWritingAreBothRead() async throws {
        for size in [9.0, 40.0] {
            let lines = try await Self.read(try Self.ink("notes", size: size, width: size / 8))
            #expect(Self.letters(lines.first?.text ?? "") == "notes", "at \(size) points read \(Self.texts(lines))")
        }
    }

    @Test func noStrokesReadNothing() async throws {
        #expect(try await Self.read([]).isEmpty)
        #expect(HandwritingRecognizer.picture(of: []) == nil)
    }

    /// A highlighter stroke is colour over the page, not writing: a word
    /// written with one is not read, and does not disturb pen writing beside it.
    @Test func highlighterInkIsNotRead() async throws {
        #expect(try await Self.read(try Self.ink("hello", width: 14, tool: .highlighter)).isEmpty)
        let both = try Self.ink("hello") + Self.ink("plan", width: 14, tool: .highlighter, origin: CGPoint(x: 60, y: 260))
        let lines = try await Self.read(both)
        #expect(lines.map { Self.letters($0.text) } == ["hello"], "read \(Self.texts(lines))")
    }

    /// Scribbles are not words. Whatever Vision makes of a tangle, it must not
    /// come back as confident text.
    @Test func aScribbleIsNotReadAsAWord() async throws {
        var wobble = SyntheticHandwriting.Wobble(seed: 7)
        let tangle = (0..<6).map { _ in
            InkStroke(tool: .pen, color: .black, width: 2.5, points: (0..<40).map { i in
                InkPoint(x: 200 + Double(i) * 3 + wobble.next(30), y: 300 + wobble.next(40))
            })
        }
        let lines = try await Self.read(tangle)
        #expect(lines.allSatisfy { Self.letters($0.text).count < 4 }, "read \(Self.texts(lines))")
    }

    /// The picture Vision is shown: black writing on white, the writing's
    /// colour and the page beneath left out.
    @Test func thePictureIsBlackOnWhite() throws {
        let strokes = try Self.ink("hi")
        let picture = try #require(HandwritingRecognizer.picture(of: strokes))
        let ink = try #require(HandwritingRecognizer.bounds(of: strokes))
        #expect(picture.covers.contains(ink))
        #expect(picture.image.width == Int((picture.covers.width * HandwritingRecognizer.pixelsPerPoint).rounded(.up)))
        let gray = try #require(picture.image.dataProvider?.data as Data?)
        let values = Set(gray)
        #expect(values.contains(255) && values.contains(where: { $0 < 40 }), "white paper and dark ink")
    }

    /// Accented writing in French and Spanish. Vision reads handwriting less
    /// well than print, and accents least of all, so this records what it
    /// does: the letters must be read, and an accent dropped is said, not
    /// hidden.
    @Test func accentedWritingInFrenchAndSpanish() async throws {
        for (language, word) in [("fr-FR", "café"), ("es-ES", "año")] {
            let lines = try await Self.read(try Self.ink(word), languages: [language])
            let read = lines.first?.text ?? ""
            let bare = { (s: String) in s.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter(\.isLetter) }
            #expect(bare(read) == bare(word), "\(language): read \(Self.texts(lines))")
            print("HANDWRITING-ACCENTS \(language) wrote \(word) read \(read)")
        }
    }
}

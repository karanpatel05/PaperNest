import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestRender

/// Row 20's word-level half. Markup worked on whole recognised lines, so
/// highlighting one word highlighted the sentence around it.
///
/// Vision really does give per-word boxes — checked before this was built,
/// because the alternative (splitting the line box by character count) drifts
/// on any proportional font and would put highlights over the wrong ink.
@Suite struct WordBoxTests {
    private func recognise(_ line: String) async throws -> RecognizedLine {
        let data = SyntheticDocuments.textImage(lines: [line], width: 1200, height: 400)
        let image = try #require(PixelProbe.decode(data))
        let lines = try await TextRecognizer(languages: ["en-US"]).recognizeOnADedicatedThread(image)
        return try #require(lines.first)
    }

    @Test func aLineReportsItsWordsInReadingOrder() async throws {
        let line = try await recognise("Invoice total 1234 EUR")

        #expect(line.words.count >= 3, "got \(line.words.map(\.text))")
        let xs = line.words.map(\.box.x)
        #expect(xs == xs.sorted(), "words are not left to right: \(line.words.map(\.text))")
        // Each word's text is actually part of the line it came from.
        for word in line.words {
            #expect(line.text.contains(word.text), "\(word.text) is not in \(line.text)")
        }
    }

    @Test func everyWordBoxSitsInsideItsLine() async throws {
        let line = try await recognise("Invoice total 1234 EUR")

        for word in line.words {
            #expect(word.box.x >= line.box.x - 0.01, "\(word.text) starts left of its line")
            #expect(word.box.x + word.box.width <= line.box.x + line.box.width + 0.01,
                    "\(word.text) runs past its line")
            #expect(word.box.width > 0 && word.box.height > 0)
        }
    }

    @Test func wordsDoNotOverlapEachOther() async throws {
        let line = try await recognise("Invoice total 1234 EUR")
        let ordered = line.words.sorted { $0.box.x < $1.box.x }

        for (left, right) in zip(ordered, ordered.dropFirst()) {
            #expect(left.box.x + left.box.width <= right.box.x + 0.01,
                    "\(left.text) overlaps \(right.text)")
        }
    }

    /// Results recognised before this field existed are still stored. They must
    /// decode as "no words", which a caller treats as "fall back to the line" —
    /// not as a failure, and not by silently recomputing anything.
    @Test func recognitionStoredBeforeWordsExistedStillDecodes() throws {
        let old = Data("""
        {"text":"Invoice total","box":{"x":0.1,"y":0.2,"width":0.5,"height":0.05},"confidence":0.9}
        """.utf8)

        let line = try JSONDecoder().decode(RecognizedLine.self, from: old)

        #expect(line.text == "Invoice total")
        #expect(line.words.isEmpty, "a missing words field must not invent any")
        #expect(line.confidence == 0.9)
    }

    @Test func wordsSurviveBeingEncodedAndDecoded() async throws {
        let line = try await recognise("Invoice total 1234 EUR")

        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(RecognizedLine.self, from: data)

        #expect(back.words.map(\.text) == line.words.map(\.text))
        #expect(back.words.first?.box == line.words.first?.box)
    }
}

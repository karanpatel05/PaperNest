import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestRender

/// A text stamp drawn: its border or tint, its words centred on one line in
/// every language, its date line smaller, and a plain text box unchanged.
@Suite struct StampRenderTests {
    /// RGBA, read once.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        /// (red, green, blue, alpha) at a pixel, top-left origin.
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }
    }

    private let green = StampPreset.approved.color

    private func stamp(_ text: String, style: StampStyle = .outlined, fontSize: Double = 20, date: String? = nil) -> TextBox {
        var box = StampDesign(text: text, style: style, color: green).textBox(dateLine: date, fontSize: fontSize)
        box.frame = CGRect(origin: CGPoint(x: 50, y: 70), size: PageRenderer.stampSize(for: box))
        return box
    }

    @Test func anOutlinedStampHasItsBorderInsideItsFrameAndClearCorners() throws {
        let box = stamp("APPROVED")
        let pixels = Pixels(try PageRenderer.stampPicture(box, scale: 4))
        let line = Int((box.stampLineWidth * 4).rounded(.down))
        // The middle of the left edge, inside the line: the stamp's green, opaque.
        let (r, g, b, a) = pixels.at(max(0, line / 2), pixels.height / 2)
        #expect(a > 240 && g > r + 60 && g > b + 30, "no green border on the left edge: \((r, g, b, a))")
        // The very corner is outside the rounded rectangle.
        #expect(pixels.at(0, 0).3 == 0, "a square corner was drawn")
        // Between the border and the words, nothing.
        #expect(pixels.at(line + 3, pixels.height / 2).3 == 0)
    }

    @Test func aFilledStampTintsBehindItsWordsAndHasNoBorder() throws {
        let box = stamp("DRAFT", style: .filled)
        let pixels = Pixels(try PageRenderer.stampPicture(box, scale: 4))
        // Inside the round end, clear of the words: a light tint of the colour.
        let alpha = pixels.at(Int(box.stampCornerRadius * 4), 6).3
        #expect(abs(Double(alpha) / 255 - PageRenderer.stampTint) < 0.03, "tint alpha \(alpha)")
    }

    /// The same words as an ordinary text box: no border, no tint.
    @Test func anOrdinaryBoxDrawsNoBorder() throws {
        var box = stamp("APPROVED")
        box.stamp = nil
        let pixels = Pixels(try PageRenderer.stampPicture(box, scale: 4))
        for y in stride(from: 0, to: pixels.height, by: 4) {
            #expect(pixels.at(1, y).3 == 0, "something drawn at the left edge, row \(y)")
        }
    }

    /// Measured from the words themselves: each preset word in each language
    /// on one line, centred in the frame, inside the padding.
    @Test func everyWordFitsOnOneLineCentredInItsFrame() {
        let words = ["APPROVED", "APPROUVÉ", "APROBADO", "PAID", "PAYÉ", "PAGADO", "RECEIVED", "REÇU", "RECIBIDO",
                     "REVIEWED", "VÉRIFIÉ", "REVISADO", "REJECTED", "REFUSÉ", "RECHAZADO", "DRAFT", "BROUILLON",
                     "BORRADOR", "CONFIDENTIAL", "CONFIDENTIEL", "CONFIDENCIAL", "Checked by Ana"]
        for word in words {
            for style in StampStyle.allCases {
                let box = stamp(word, style: style)
                let rects = PageRenderer.textSelectionRects(box)
                #expect(rects.count == word.filter { !$0.isWhitespace }.count, "\(word): a letter is missing")
                let mids = rects.map(\.midY)
                #expect((mids.max() ?? 0) - (mids.min() ?? 0) < box.fontSize * 0.5, "\(word) wrapped onto two lines")
                let bounds = rects.reduce(CGRect.null) { $0.union($1) }
                let content = box.stampContentRect.offsetBy(dx: box.frame.minX, dy: box.frame.minY)
                #expect(content.insetBy(dx: -1, dy: -1).contains(bounds), "\(word) is outside the padding")
                #expect(abs(bounds.midX - box.frame.midX) < 2, "\(word) is not centred across")
                #expect(abs(bounds.midY - box.frame.midY) < box.fontSize * 0.25, "\(word) is not centred down")
            }
        }
    }

    @Test func theDateLineIsSmallerAndUnderTheWords() throws {
        let box = stamp("APPROVED", date: "17 nov. 2026")
        let rects = PageRenderer.textSelectionRects(box)
        let firstLineCount = "APPROVED".count
        try #require(rects.count == firstLineCount + "17nov.2026".count)
        let word = rects.prefix(firstLineCount), date = rects.dropFirst(firstLineCount)
        let wordHeight = word.map(\.height).max() ?? 0, dateHeight = date.map(\.height).max() ?? 0
        #expect(dateHeight < wordHeight * 0.75, "the date is not smaller: \(dateHeight) vs \(wordHeight)")
        #expect((date.map(\.minY).min() ?? 0) > (word.map(\.maxY).max() ?? 0), "the date is not under the words")
        let bounds = rects.reduce(CGRect.null) { $0.union($1) }
        #expect(box.frame.contains(bounds))
    }

    /// A stamp made larger is the same stamp: everything follows the type size.
    @Test func aLargerStampIsTheSameShapeScaled() {
        let small = PageRenderer.stampSize(for: stamp("PAID", fontSize: 20))
        let large = PageRenderer.stampSize(for: stamp("PAID", fontSize: 40))
        #expect(abs(large.width / small.width - 2) < 0.15 && abs(large.height / small.height - 2) < 0.15)
    }
}

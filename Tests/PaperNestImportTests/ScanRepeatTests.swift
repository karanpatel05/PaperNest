import CoreGraphics
import CoreText
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender

/// Whether a captured page repeats another, on drawn pages: a page and a
/// second photograph of it (shifted, scaled and turned a little, lit
/// differently, softer, grainier), and the hardest wrong answer — another
/// page of different print set exactly the same way. No camera was used.
@Suite struct ScanRepeatTests {
    static let vocabulary = ["the", "report", "shows", "steady", "growth", "in", "every", "region", "we", "serve",
                             "costs", "held", "flat", "while", "orders", "rose", "by", "a", "third", "over",
                             "spring", "and", "summer", "our", "teams", "expect", "more", "of", "same", "next",
                             "year", "with", "new", "stores", "opening", "north", "south", "east", "west", "soon"]

    /// Lines of words picked by a generator seeded with `seed`: each seed's
    /// print is its own, and the same every run.
    static func lines(seed: UInt64, count: Int) -> [String] {
        var state = seed &* 0x9E3779B97F4A7C15 | 1
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        return (0..<count).map { _ in (0..<(8 + next(5))).map { _ in vocabulary[next(vocabulary.count)] }.joined(separator: " ") }
    }

    /// A page of `seed`'s print, 1200 × 1560, drawn as a photograph would
    /// sit: shifted by `shift` (shares of the width), scaled and turned
    /// `degrees` about its middle; then blurred and grained.
    static func page(seed: UInt64, letters: CGFloat = 0.018, gap: CGFloat = 1.6, shift: CGPoint = .zero, scale: CGFloat = 1,
                     degrees: CGFloat = 0, paper: CGFloat = 0.96, ink: CGFloat = 0.1, blur: Double = 0, grain: Int = 0,
                     print: Bool = true, lineCount: Int = 200) -> CGImage {
        let width = 1200, height = 1560
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: paper, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: CGFloat(width) / 2 + shift.x * CGFloat(width), y: CGFloat(height) / 2 - shift.y * CGFloat(width))
        context.rotate(by: degrees * .pi / 180)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
        if print {
            let size = CGFloat(width) * letters
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: ink, alpha: 1)] as CFDictionary
            var y = CGFloat(height) - size * 4
            for text in lines(seed: seed, count: lineCount) {
                guard y > size * 3 else { break }
                context.textPosition = CGPoint(x: CGFloat(width) * 0.07, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)), context)
                y -= size * gap
            }
        }
        var image = context.makeImage()!
        if blur > 0 { image = ScanQualityAnalyzerTests.blurred(image, sigma: blur) }
        if grain > 0 { image = ScanQualityAnalyzerTests.grained(image, by: grain) }
        return image
    }

    static func print(_ image: CGImage) throws -> ScanFingerprint {
        try #require(ScanQualityAnalyzer.examine(page: image, corners: ScannerCorners.whole, photoSize: nil)).fingerprint
    }

    /// A second photograph: 1% across, 0.8% down, 1% larger, 0.4° turned,
    /// dimmer paper, greyer ink, softer and grainier.
    static func retaken(_ seed: UInt64) -> CGImage {
        page(seed: seed, shift: CGPoint(x: 0.01, y: 0.008), scale: 1.01, degrees: 0.4, paper: 0.88, ink: 0.18, blur: 1.5, grain: 3)
    }

    /// A second photograph is the same page: mild (1% across, 0.8% down, 1%
    /// larger, 0.4° turned, dimmer, softer, grainier), measured 0.91 either
    /// way; and harsh (3% across, 2% down, 3% larger, 1.2° turned, dim, soft
    /// and grainy), measured 0.67 at the least — nearer the line, since a
    /// turn and a scale move the page's corners further than a tile slides.
    @Test func aSecondPhotographOfAPageIsTheSamePage() throws {
        let original = try Self.print(Self.page(seed: 1))
        let harsh = Self.page(seed: 1, shift: CGPoint(x: 0.03, y: 0.02), scale: 1.03, degrees: 1.2, paper: 0.8, ink: 0.25,
                              blur: 3, grain: 5)
        for (retake, margin) in [(Self.retaken(1), 0.2), (harsh, 0.03)] {
            let other = try Self.print(retake)
            #expect(ScanLikeness.isSamePage(original, other))
            #expect(try #require(ScanLikeness.likeness(original, other)) > ScanLikeness.sameAtLeast + margin)
            #expect(try #require(ScanLikeness.likeness(other, original)) > ScanLikeness.sameAtLeast + margin)
        }
    }

    /// A page printed only part of the way down — a short letter — against
    /// different print set the same way, photographed or not: never the same
    /// page. Measured with 18 and 24 lines: 0.18 at the most either way; with
    /// the median instead of the lower quartile, 0.41. A missed repeat on a
    /// page this short is the price: at 14 lines it is not judged at all.
    @Test(arguments: [14, 18, 24])
    func aShortPageOfDifferentPrintIsNotTheSamePage(lines: Int) throws {
        let original = try Self.print(Self.page(seed: 1, lineCount: lines))
        for seed in UInt64(2)...UInt64(13) {
            for image in [Self.page(seed: seed, lineCount: lines),
                          Self.page(seed: seed, shift: CGPoint(x: 0.01, y: 0.008), scale: 1.01, degrees: 0.4, paper: 0.88,
                                    ink: 0.18, blur: 1.5, grain: 3, lineCount: lines)] {
                let other = try Self.print(image)
                #expect(!ScanLikeness.isSamePage(original, other))
                for likeness in [ScanLikeness.likeness(original, other), ScanLikeness.likeness(other, original)].compactMap({ $0 }) {
                    #expect(likeness < 0.3, "\(lines) lines, seed \(seed): \(likeness)")
                }
            }
        }
        // Its own second photograph is found once enough of the page is printed;
        // at 14 lines (about a third of the page) too few tiles count to judge.
        let retake = try Self.print(Self.page(seed: 1, shift: CGPoint(x: 0.01, y: 0.008), scale: 1.01, degrees: 0.4,
                                              paper: 0.88, ink: 0.18, blur: 1.5, grain: 3, lineCount: lines))
        #expect(ScanLikeness.isSamePage(original, retake) == (lines >= 18), "\(lines) lines: its own second photograph")
    }

    /// Printed in only a few tiles, a page is not judged at all: with four
    /// tiles counted, different print read 0.50.
    @Test func aPageWithOnlyAFewLinesIsNotJudged() throws {
        let original = try Self.print(Self.page(seed: 1, lineCount: 8))
        #expect(ScanLikeness.likeness(original, try Self.print(Self.page(seed: 2, lineCount: 8))) == nil)
        #expect(!ScanLikeness.isSamePage(original, try Self.print(Self.retaken(1))))
    }

    /// Different print set exactly the same way — same type, same lines,
    /// same margins — is another page, even photographed differently.
    /// Measured: 0.16 at the most.
    @Test(arguments: UInt64(2)...UInt64(7))
    func anotherPageSetTheSameWayIsNotTheSamePage(seed: UInt64) throws {
        let original = try Self.print(Self.page(seed: 1))
        for other in [try Self.print(Self.page(seed: seed)), try Self.print(Self.retaken(seed))] {
            #expect(!ScanLikeness.isSamePage(original, other))
            #expect(try #require(ScanLikeness.likeness(original, other)) < 0.3, "seed \(seed)")
            #expect(try #require(ScanLikeness.likeness(other, original)) < 0.3, "seed \(seed)")
        }
    }

    /// The same words in other type or with other spacing are not the same
    /// page photographed again.
    @Test func theSameWordsSetOtherwiseAreNotTheSamePage() throws {
        let original = try Self.print(Self.page(seed: 1))
        for other in [try Self.print(Self.page(seed: 1, letters: 0.025)), try Self.print(Self.page(seed: 1, gap: 2.0))] {
            #expect(!ScanLikeness.isSamePage(original, other))
            #expect(try #require(ScanLikeness.likeness(original, other)) < 0.4)
        }
    }

    /// Nothing on a blank page says it repeats anything.
    @Test func aBlankPageIsNobodysRepeat() throws {
        let blank = try Self.print(Self.page(seed: 1, grain: 3, print: false))
        #expect(ScanLikeness.likeness(blank, blank) == nil)
        #expect(!ScanLikeness.isSamePage(blank, blank))
        #expect(!ScanLikeness.isSamePage(blank, try Self.print(Self.page(seed: 1))))
    }

    /// The same print cropped to another shape is not the same capture.
    @Test func aPageOfAnotherShapeIsNotTheSamePage() throws {
        let whole = Self.page(seed: 1)
        let cropped = try #require(whole.cropping(to: CGRect(x: 0, y: 0, width: 1200, height: 1100)))
        #expect(ScanLikeness.likeness(try Self.print(whole), try Self.print(cropped)) == 0)
    }
}

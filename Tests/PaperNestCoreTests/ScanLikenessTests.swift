import Foundation
import Testing
@testable import PaperNestCore

/// The likeness of two fingerprints, on pictures built pixel by pixel: rows
/// of dark runs for words, the same on every page in where the rows are.
@Suite struct ScanLikenessTests {
    /// A fingerprint-sized picture: a row of "words" every 6 pixels, each
    /// word a dark run 4 to 12 pixels long, as `seed` picks them; the whole
    /// page slid by `dx`, `dy`.
    private func picture(seed: UInt64, dx: Int = 0, dy: Int = 0, blank: Bool = false) -> GrayPicture {
        let width = ScanFingerprint.width, height = ScanFingerprint.height
        var pixels = [UInt8](repeating: 245, count: width * height)
        var state = seed &* 0x9E3779B97F4A7C15 | 1
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        guard !blank else { return GrayPicture(width: width, height: height, pixels: pixels) }
        for row in stride(from: 14, to: height - 14, by: 6) {
            var x = 12
            while x < width - 12 {
                let length = 4 + next(9)
                for line in 0..<2 {
                    for column in x..<min(width - 12, x + length) {
                        let px = column + dx, py = row + line + dy
                        if (0..<width).contains(px), (0..<height).contains(py) { pixels[py * width + px] = 40 }
                    }
                }
                x += length + 2 + next(2)
            }
        }
        return GrayPicture(width: width, height: height, pixels: pixels)
    }

    private func print(_ picture: GrayPicture, aspect: Double = 0.77) -> ScanFingerprint {
        ScanFingerprint(picture, aspect: aspect)
    }

    @Test func aPageIsItsOwnRepeatEvenSlidAFewPixels() throws {
        let page = print(picture(seed: 1))
        #expect(try #require(ScanLikeness.likeness(page, page)) > 0.99)
        #expect(ScanLikeness.isSamePage(page, print(picture(seed: 1, dx: 3, dy: 2))))
    }

    @Test func otherWordsOnTheSameRowsAreAnotherPage() throws {
        let page = print(picture(seed: 1))
        for seed in UInt64(2)...UInt64(5) {
            let other = print(picture(seed: seed))
            #expect(!ScanLikeness.isSamePage(page, other))
            #expect(try #require(ScanLikeness.likeness(page, other)) < 0.4, "seed \(seed)")
        }
    }

    /// Slid further than the search reaches, a page is not found again: a
    /// missed repeat, which costs only a look.
    @Test func aSlideBeyondTheReachIsNotFound() {
        #expect(!ScanLikeness.isSamePage(print(picture(seed: 1)), print(picture(seed: 1, dx: 12))))
    }

    @Test func blankPagesAndOtherShapesAreNeverRepeats() {
        let blank = print(picture(seed: 1, blank: true))
        #expect(ScanLikeness.likeness(blank, blank) == nil)
        #expect(!ScanLikeness.isSamePage(blank, blank))
        let page = picture(seed: 1)
        #expect(ScanLikeness.likeness(print(page, aspect: 0.77), print(page, aspect: 1.0)) == 0)
        #expect(ScanLikeness.isSamePage(print(page, aspect: 0.77), print(page, aspect: 0.8)), "within the tolerance")
    }
}

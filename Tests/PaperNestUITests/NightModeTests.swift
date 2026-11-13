import CoreGraphics
import Foundation
import SwiftUI
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Night mode: how a page's colours are shown light-on-dark, and that showing
/// them so changes nothing about the page.
@MainActor @Suite struct NightModeTests {
    typealias RGB = NightPalette.RGB

    /// WCAG relative luminance and contrast: what "readable" is measured in.
    private func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (relativeLuminance(a), relativeLuminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// How different two colours look (CIE76 ΔE in L*a*b*): lightness and
    /// colour together. Luminance contrast alone cannot see a highlight —
    /// yellow on white is barely darker than the paper, by day too.
    private func difference(_ a: RGB, _ b: RGB) -> Double {
        func lab(_ color: RGB) -> (Double, Double, Double) {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let (r, g, b) = (linear(color.red), linear(color.green), linear(color.blue))
            func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
            let x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
            let y = f(0.2126 * r + 0.7152 * g + 0.0722 * b)
            let z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
            return (116 * y - 16, 500 * (x - y), 200 * (y - z))
        }
        let (first, second) = (lab(a), lab(b))
        return sqrt(pow(first.0 - second.0, 2) + pow(first.1 - second.1, 2) + pow(first.2 - second.2, 2))
    }

    private let white = RGB(red: 1, green: 1, blue: 1)
    private let black = RGB(red: 0, green: 0, blue: 0)
    private var nightPaper: RGB { NightPalette.night(white) }

    /// A highlighter stroke as the renderer leaves it on white paper:
    /// multiplied in at the highlighter's opacity.
    private func highlighted(_ color: RGBAColor) -> RGB {
        let opacity = InkStroke.highlighterOpacity
        return RGB(red: 1 - opacity * (1 - color.red), green: 1 - opacity * (1 - color.green),
                   blue: 1 - opacity * (1 - color.blue))
    }

    // MARK: - Colours

    @Test func paperTurnsDarkAndBlackTextTurnsLight() {
        #expect(NightPalette.night(white) == black)
        #expect(NightPalette.night(black) == white)
        // Greys swap ends and keep their order, so anti-aliased text stays smooth.
        let greys = stride(from: 0.0, through: 1.0, by: 0.125).map { NightPalette.night(RGB(red: $0, green: $0, blue: $0)) }
        for (grey, input) in zip(greys, stride(from: 0.0, through: 1.0, by: 0.125)) {
            #expect(abs(grey.red - (1 - input)) < 0.001)
            #expect(grey.red == grey.green && grey.green == grey.blue)
        }
    }

    /// The failure a plain "invert, then turn the hue back" has: a highlight
    /// is paper-pale, so it inverts to paper-dark and disappears. Every
    /// highlighter colour the app offers has to stay a visible band of its own
    /// colour, with the words on it still easy to read.
    @Test(arguments: [
        RGBAColor(red: 1, green: 0.82, blue: 0),      // the default highlighter, and text highlight
        RGBAColor(red: 1, green: 1, blue: 0),
        RGBAColor(red: 0.2, green: 0.9, blue: 0.3),
        RGBAColor(red: 1, green: 0.4, blue: 0.7),
        RGBAColor(red: 0.3, green: 0.7, blue: 1),
        RGBAColor(red: 1, green: 0.55, blue: 0.1),
    ])
    func aHighlightIsStillAVisibleBandOfItsOwnColour(_ color: RGBAColor) {
        let day = highlighted(color)
        let band = NightPalette.night(day)
        // As easy to tell from the page at night as it is by day, and plainly so.
        let (byDay, byNight) = (difference(day, white), difference(band, nightPaper))
        #expect(byNight >= 15 && byNight >= byDay * 0.8,
                "the highlight is hard to tell from the night page: \(band), ΔE \(byNight) against \(byDay) by day")
        // The words under a highlight are untouched by it (it multiplies), so
        // at night they are white on the band.
        #expect(contrast(NightPalette.night(black), band) >= 4.5, "words on the highlight are hard to read")
        // Still the colour it was: the strongest and weakest channels are the same ones.
        let before = [color.red, color.green, color.blue]
        let after = [band.red, band.green, band.blue]
        #expect(after.firstIndex(of: after.max()!) == before.firstIndex(of: before.max()!)
                || after.max()! - after[before.firstIndex(of: before.max()!)!] < 0.02)
        #expect(after[before.firstIndex(of: before.min()!)!] - after.min()! < 0.02)
    }

    /// Ink that could be read on white paper can be read on the night page,
    /// and red is still red.
    @Test(arguments: [
        RGBAColor(red: 0, green: 0, blue: 0),
        RGBAColor(red: 0.1, green: 0.3, blue: 0.9),   // the default shape colour
        RGBAColor(red: 0.1, green: 0.35, blue: 0.8),  // underline and strikethrough
        RGBAColor(red: 0, green: 0, blue: 1),
        RGBAColor(red: 0.85, green: 0.1, blue: 0.1),
        RGBAColor(red: 1, green: 0, blue: 0),
        RGBAColor(red: 0, green: 0.5, blue: 0.2),
        RGBAColor(red: 0.5, green: 0.1, blue: 0.7),
        RGBAColor(red: 0.35, green: 0.2, blue: 0.1),
    ])
    func inkThatWasReadableStaysReadableAndKeepsItsColour(_ color: RGBAColor) {
        let day = RGB(red: color.red, green: color.green, blue: color.blue)
        let night = NightPalette.night(day)
        #expect(contrast(day, white) >= 3, "not a fair test: this ink is hard to read by day")
        #expect(contrast(night, nightPaper) >= 4.5, "\(day) is hard to read at night as \(night)")
        let before = [day.red, day.green, day.blue]
        let after = [night.red, night.green, night.blue]
        if before.max()! - before.min()! > 0.1 {
            // The channel that led still leads, or shares the lead.
            #expect(after.max()! - after[before.firstIndex(of: before.max()!)!] < 0.02, "\(day) changed hue: \(night)")
        }
    }

    @Test func everyColourComesOutARealColourAndNoBrighterInkIsLost() {
        for red in stride(from: 0.0, through: 1.0, by: 0.125) {
            for green in stride(from: 0.0, through: 1.0, by: 0.125) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let day = RGB(red: red, green: green, blue: blue)
                    let night = NightPalette.night(day)
                    for value in [night.red, night.green, night.blue] {
                        #expect(value >= 0 && value <= 1, "\(day) -> \(night)")
                    }
                    // Anything clearly visible on white paper is clearly visible on the night page.
                    if contrast(day, white) >= 4.5 {
                        #expect(contrast(night, nightPaper) >= 3, "\(day) -> \(night)")
                    }
                }
            }
        }
    }

    // MARK: - A page's picture

    private func bitmap(_ pixels: [[RGB]]) -> CGImage {
        let (width, height) = (pixels[0].count, pixels.count)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        for (y, row) in pixels.enumerated() {
            for (x, pixel) in row.enumerated() {
                let offset = (y * width + x) * 4
                data[offset] = UInt8((pixel.red * 255).rounded())
                data[offset + 1] = UInt8((pixel.green * 255).rounded())
                data[offset + 2] = UInt8((pixel.blue * 255).rounded())
                data[offset + 3] = 255
            }
        }
        return context.makeImage()!
    }

    @Test func aPagePictureIsShownWithEveryPixelInItsNightColour() throws {
        let band = highlighted(RGBAColor(red: 1, green: 0.82, blue: 0))
        let red = RGB(red: 0.85, green: 0.1, blue: 0.1)
        let source = bitmap([[white, black, band], [red, white, black]])

        let night = try #require(NightPalette.image(source))

        #expect(night.width == 3 && night.height == 2)
        func expectPixel(_ x: Double, _ y: Double, _ expected: RGB, _ comment: Comment) {
            let pixel = PixelProbe.pixel(night, x: x, y: y)
            let want = [expected.red, expected.green, expected.blue].map { Int(($0 * 255).rounded()) }
            #expect(abs(Int(pixel.r) - want[0]) <= 1 && abs(Int(pixel.g) - want[1]) <= 1
                    && abs(Int(pixel.b) - want[2]) <= 1, comment)
        }
        expectPixel(1.0 / 6, 0.25, black, "paper")
        expectPixel(0.5, 0.25, white, "text")
        expectPixel(5.0 / 6, 0.25, NightPalette.night(band), "highlight")
        expectPixel(1.0 / 6, 0.75, NightPalette.night(red), "red ink")
        expectPixel(5.0 / 6, 0.75, white, "text on the second row")
    }

    /// Night mode is how a page is shown, never what it is.
    @Test func thePictureItWasMadeFromIsLeftAsItWas() throws {
        let source = bitmap([[white, black], [black, white]])
        _ = try #require(NightPalette.image(source))
        #expect(PixelProbe.pixel(source, x: 0.25, y: 0.25).isWhite)
        #expect(PixelProbe.pixel(source, x: 0.75, y: 0.25).isDark)
    }

    /// The same picture asked for twice is worked out once: turning back to
    /// a page at night must not show it blank while it is recoloured.
    @Test func aPictureAlreadyShownAtNightIsNotWorkedOutAgain() throws {
        let source = bitmap([[white, black], [black, white]])
        let first = try #require(NightPalette.image(source))
        let second = try #require(NightPalette.image(source))
        #expect(first === second)
    }

    /// End to end through the real renderer: a page of text with a highlight
    /// across it and a pen stroke under it.
    @Test func aRenderedPageHasDarkPaperLightInkAndAHighlightThatShows() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestNight-\(UUID().uuidString)", isDirectory: true)
        let environment = try AppEnvironment(libraryURL: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await environment.importer
            .importItem(.data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement"))
        let page = try #require(try await environment.store.pages(of: item.id).first)
        try await environment.store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 20,
                                    points: [InkPoint(x: 300, y: 600), InkPoint(x: 500, y: 600)])),
            modifiedAt: Date()))
        try await environment.store.saveObject(PageObject(
            pageID: page.id, zKey: "n",
            payload: .ink(InkStroke(tool: .highlighter, color: RGBAColor(red: 1, green: 0.82, blue: 0), width: 40,
                                    points: [InkPoint(x: 150, y: 400), InkPoint(x: 450, y: 400)])),
            modifiedAt: Date()))
        let saved = try #require(try await environment.store.pages(of: item.id).first)
        let day = try await environment.renderer.renderThumbnail(saved, maxPixelSize: 792)

        let night = try #require(NightPalette.image(day))

        #expect(PixelProbe.pixel(day, x: 300.0 / 612, y: 700.0 / 792).isWhite)
        let paper = PixelProbe.pixel(night, x: 300.0 / 612, y: 700.0 / 792)
        #expect(paper.r < 10 && paper.g < 10 && paper.b < 10, "the night page's paper is not dark")
        let ink = PixelProbe.pixel(night, x: 400.0 / 612, y: 600.0 / 792)
        #expect(ink.r > 240 && ink.g > 240 && ink.b > 240, "black ink is not light on the night page")
        let highlight = PixelProbe.pixel(night, x: 300.0 / 612, y: 400.0 / 792)
        #expect(Int(highlight.r) > Int(paper.r) + 50, "the highlight has vanished into the night page")
        #expect(Int(highlight.r) > Int(highlight.b) + 50, "the highlight is no longer yellow")
        // And the day picture, which is what is cached, stored and exported from, is as it was.
        #expect(PixelProbe.pixel(day, x: 300.0 / 612, y: 700.0 / 792).isWhite)
    }

    // MARK: - The switch

    private func defaults() -> UserDefaults {
        let name = "PaperNestNightModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// One test's night mode must not become the next test's starting state,
    /// the same rule the tool settings follow.
    @Test func aThrowawayLibraryStartsWithNightModeOff() {
        let defaults = defaults()
        defaults.set(true, forKey: NightMode.storageKey)
        defaults.set("/tmp/some-test-library", forKey: "PaperNestLibraryPath")

        NightMode.resetForThrowawayLibrary(defaults)

        #expect(!defaults.bool(forKey: NightMode.storageKey))
    }

    @Test func aRealLibraryKeepsNightModeAsItWasLeft() {
        let defaults = defaults()
        defaults.set(true, forKey: NightMode.storageKey)

        NightMode.resetForThrowawayLibrary(defaults)

        #expect(defaults.bool(forKey: NightMode.storageKey))
    }

    // MARK: - What is drawn over the page

    private func rendered(_ color: Color, filtered times: Int) throws -> PixelProbe.RGB {
        var view = AnyView(Rectangle().fill(color).frame(width: 8, height: 8))
        for _ in 0..<times { view = AnyView(view.nightFilter(true)) }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return PixelProbe.pixel(try #require(renderer.cgImage), x: 0.5, y: 0.5)
    }

    /// Everything drawn live over the page — a stroke in progress, text being
    /// typed, a selection — goes through this filter instead of the palette.
    @Test func theFilterOverThePageTurnsBlackInkLightAndWhiteDark() throws {
        let ink = try rendered(.black, filtered: 1)
        #expect(ink.r > 250 && ink.g > 250 && ink.b > 250)
        let paper = try rendered(.white, filtered: 1)
        #expect(paper.r < 5 && paper.g < 5 && paper.b < 5)
    }

    /// Find's hits are drawn over the page, so they go through the filter
    /// and not the palette — and by day they are a pale yellow, which the
    /// filter would turn nearly black. At night they are filled differently.
    @Test(arguments: [false, true])
    func aFindHitIsStillLitAtNightWithTheWordsOnItReadable(_ isCurrent: Bool) throws {
        func seen(_ ink: Color) throws -> RGB {
            let view = ZStack {
                Color.white
                ink
                FindHighlightsOverlay.fill(isCurrent: isCurrent, isNight: true).blendMode(.multiply)
            }
            .frame(width: 8, height: 8)
            .nightFilter(true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let pixel = PixelProbe.pixel(try #require(renderer.cgImage), x: 0.5, y: 0.5)
            return RGB(red: Double(pixel.r) / 255, green: Double(pixel.g) / 255, blue: Double(pixel.b) / 255)
        }
        let band = try seen(.clear)
        let words = try seen(.black)
        #expect(difference(band, nightPaper) >= 30, "a find hit cannot be told from the night page: \(band)")
        #expect(band.red > band.blue + 0.25, "a find hit is no longer amber: \(band)")
        #expect(contrast(words, band) >= 4.5, "the found words are hard to read on their highlight: \(words) on \(band)")
    }

    /// The page's own picture sits under that same filter, so it is put
    /// through it once beforehand: twice is back where it started. This is
    /// what lets the picture keep the palette's colours exactly.
    @Test(arguments: [
        (0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.5, 0.5, 0.5),
        (0.35, 0.33, 0.0),   // the default highlight, as the palette shows it at night
        (0.9, 0.5, 0.5), (0.45, 0.5, 0.85), (0.2, 0.6, 0.3),
    ])
    func theFilterAppliedTwiceGivesTheColourBack(_ red: Double, _ green: Double, _ blue: Double) throws {
        let twice = try rendered(Color(.sRGB, red: red, green: green, blue: blue), filtered: 2)
        #expect(abs(Double(twice.r) / 255 - red) < 0.03 && abs(Double(twice.g) / 255 - green) < 0.03
                && abs(Double(twice.b) / 255 - blue) < 0.03, "came back as \(twice)")
    }
}

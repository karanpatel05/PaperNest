import CoreGraphics
import CoreImage
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender

/// The scanner's presets and Cleanup, on pages made here pixel by pixel.
///
/// A fixture is paper under some lighting with dark "text" bars across it.
/// Every position below is measured from the top-left, in the fixture's own
/// pixels, so a result that came out flipped fails rather than passes.
@Suite struct ScanImageProcessorTests {
    // MARK: Fixtures

    struct RGB: Equatable, CustomStringConvertible {
        var r: Double, g: Double, b: Double
        static func gray(_ level: Double) -> RGB { RGB(r: level, g: level, b: level) }
        var brightness: Double { (r + g + b) / 3 }
        /// How far the channels are from one another: 0 is a neutral gray.
        var tint: Double { max(r, g, b) - min(r, g, b) }
        var description: String { String(format: "rgb(%.0f, %.0f, %.0f)", r, g, b) }
    }

    /// An 8-bit sRGB picture, row 0 at the top.
    struct Bitmap {
        let width: Int, height: Int
        var bytes: [UInt8]

        init(width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> RGB) {
            self.width = width; self.height = height
            bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let colour = pixel(x, y), i = (y * width + x) * 4
                    bytes[i] = UInt8(max(0, min(255, colour.r.rounded())))
                    bytes[i + 1] = UInt8(max(0, min(255, colour.g.rounded())))
                    bytes[i + 2] = UInt8(max(0, min(255, colour.b.rounded())))
                }
            }
        }

        init(_ image: CGImage) {
            width = image.width; height = image.height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        var image: CGImage {
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }

        /// Mean colour of a rectangle given as x, y, width, height.
        func mean(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> RGB {
            var r = 0.0, g = 0.0, b = 0.0
            for row in y..<(y + h) {
                for column in x..<(x + w) {
                    let i = (row * width + column) * 4
                    r += Double(bytes[i]); g += Double(bytes[i + 1]); b += Double(bytes[i + 2])
                }
            }
            let count = Double(w * h)
            return RGB(r: r / count, g: g / count, b: b / count)
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }
    }

    static let ink = RGB(r: 40, g: 40, b: 46)

    /// 400 by 560. Text bars three pixels tall every sixteen rows between
    /// x 40 and 360, leaving both side margins as bare paper.
    static func isText(_ x: Int, _ y: Int, scale: Int = 1) -> Bool {
        let px = x / scale, py = y / scale
        return px >= 40 && px < 360 && py >= 48 && py < 520 && (py - 48) % 16 < 3
    }

    /// Paper under a shadow over its top-left quarter. The shadow is 0.6 of
    /// full light and fades out over sixty pixels, as a hand's or a phone's does.
    static func shadowedPage(paper: RGB = RGB(r: 232, g: 228, b: 218), scale: Int = 1) -> Bitmap {
        Bitmap(width: 400 * scale, height: 560 * scale) { x, y in
            let px = Double(x) / Double(scale), py = Double(y) / Double(scale)
            func fade(_ distance: Double) -> Double {
                let t = max(0, min(1, distance / 60))
                return t * t * (3 - 2 * t)
            }
            // 1 well inside the quarter, 0 well outside it.
            let depth = (1 - fade(px - 170)) * (1 - fade(py - 250))
            let light = 1 - 0.4 * depth
            let base = isText(x, y, scale: scale) ? ink : paper
            return RGB(r: base.r * light, g: base.g * light, b: base.b * light)
        }
    }

    static func evenPage(paper: RGB, ink: RGB = ScanImageProcessorTests.ink) -> Bitmap {
        Bitmap(width: 400, height: 560) { x, y in isText(x, y) ? ink : paper }
    }

    /// Paper with four flat patches down its middle: red, blue, light gray, dark gray.
    static func patchPage() -> Bitmap {
        Bitmap(width: 400, height: 560) { x, y in
            guard x >= 120, x < 280 else { return .gray(235) }
            switch y {
            case 40..<140: return RGB(r: 200, g: 40, b: 40)
            case 170..<270: return RGB(r: 40, g: 60, b: 200)
            case 300..<400: return .gray(170)
            case 430..<530: return .gray(90)
            default: return .gray(235)
            }
        }
    }

    // Where to look on a 400 by 560 page.
    static func shadowPaper(_ page: Bitmap) -> RGB { page.mean(8, 90, 24, 80) }
    static func litPaper(_ page: Bitmap) -> RGB { page.mean(368, 400, 24, 80) }
    /// The bar at y 112...114, under the shadow.
    static func shadowInk(_ page: Bitmap) -> RGB { page.mean(60, 113, 80, 1) }
    /// The bar at y 432...434, in full light.
    static func litInk(_ page: Bitmap) -> RGB { page.mean(240, 433, 100, 1) }

    private func processed(_ page: Bitmap, _ appearance: ScanAppearance) throws -> Bitmap {
        Bitmap(try #require(ScanImageProcessor.apply(appearance, to: page.image)))
    }

    // MARK: Nothing asked, nothing done

    @Test func theOriginalLookLeavesEveryPixelAlone() throws {
        let page = Self.shadowedPage()
        #expect(try processed(page, .original).bytes == page.bytes)
    }

    // MARK: Remove shadows

    @Test func theFixtureReallyHasAShadow() {
        let page = Self.shadowedPage()
        #expect(Self.litPaper(page).r - Self.shadowPaper(page).r > 85)
    }

    @Test func removingShadowsLiftsShadowedPaperToTheLitPaper() throws {
        let page = Self.shadowedPage()
        let result = try processed(page, ScanAppearance(cleanup: ScanCleanup(removeShadows: 1)))
        let lit = Self.litPaper(result), shadow = Self.shadowPaper(result)
        #expect(abs(lit.brightness - shadow.brightness) < 12, "lit \(lit), shadow \(shadow)")
        // Lighting is evened out, not turned up: paper that was well lit keeps its tone.
        #expect(abs(lit.brightness - Self.litPaper(page).brightness) < 10, "lit paper became \(lit)")
        #expect(Self.shadowInk(result).brightness < 90, "ink under the shadow: \(Self.shadowInk(result))")
        #expect(Self.litInk(result).brightness < 90, "ink in the light: \(Self.litInk(result))")
    }

    @Test func halfTheAmountRemovesAboutHalfTheShadow() throws {
        let page = Self.shadowedPage()
        let before = Self.litPaper(page).brightness - Self.shadowPaper(page).brightness
        let result = try processed(page, ScanAppearance(cleanup: ScanCleanup(removeShadows: 0.5)))
        let after = Self.litPaper(result).brightness - Self.shadowPaper(result).brightness
        #expect(after > before * 0.3 && after < before * 0.7, "shadow went from \(before) to \(after)")
    }

    /// The shadowed page with a blue heading bar across its top, part of it
    /// under the shadow, and an orange picture in the light. Both are far
    /// wider than a stroke of text, so nothing closes over them.
    static let bar = RGB(r: 30, g: 64, b: 140), picture = RGB(r: 190, g: 90, b: 50)
    static func pageWithFilledBlocks() -> Bitmap {
        let page = shadowedPage()
        return Bitmap(width: 400, height: 560) { x, y in
            let i = (y * 400 + x) * 4
            let under = RGB(r: Double(page.bytes[i]), g: Double(page.bytes[i + 1]), b: Double(page.bytes[i + 2]))
            // How much light reaches this point, read back from the paper beside the text.
            let light = isText(x, y) ? nil : under.r / 232
            if x >= 40, x < 360, y >= 4, y < 40, let light { return RGB(r: bar.r * light, g: bar.g * light, b: bar.b * light) }
            if x >= 220, x < 340, y >= 300, y < 420 { return picture }
            return under
        }
    }

    /// A filled block is not a shadow. Lighting is read from the paper and
    /// carried across anything that is not paper, so a heading bar or a
    /// picture keeps its colour, and the part of it that was in shadow is
    /// lit like the rest.
    @Test func removingShadowsLeavesFilledBlocksTheirColour() throws {
        let page = Self.pageWithFilledBlocks()
        let result = try processed(page, ScanAppearance(cleanup: ScanCleanup(removeShadows: 1)))
        let picture = result.mean(250, 330, 60, 60), litBar = result.mean(260, 14, 80, 16), shadowBar = result.mean(60, 14, 80, 16)
        #expect(abs(picture.r - 190) < 12 && abs(picture.g - 90) < 12 && abs(picture.b - 50) < 12, "the picture became \(picture)")
        #expect(abs(litBar.r - 30) < 12 && abs(litBar.g - 64) < 12 && abs(litBar.b - 140) < 12, "the bar became \(litBar)")
        #expect(abs(shadowBar.brightness - litBar.brightness) < 15, "bar in shadow \(shadowBar), in light \(litBar)")
        // The paper around them is still evened out.
        #expect(abs(Self.litPaper(result).brightness - Self.shadowPaper(result).brightness) < 12)
    }

    @Test func blackAndWhiteKeepsAFilledBlockBlack() throws {
        let result = try processed(Self.pageWithFilledBlocks(), ScanAppearance(preset: .blackAndWhite))
        #expect(result.mean(260, 14, 80, 16).brightness < 40, "the bar in the light became \(result.mean(260, 14, 80, 16))")
        #expect(result.mean(60, 14, 80, 16).brightness < 40, "the bar in shadow became \(result.mean(60, 14, 80, 16))")
        #expect(Self.shadowPaper(result).brightness > 245 && Self.litPaper(result).brightness > 245)
    }

    // MARK: Whiten background

    @Test func whiteningTurnsTintedPaperWhiteAndKeepsInkDark() throws {
        let page = Self.evenPage(paper: RGB(r: 220, g: 210, b: 185))
        let result = try processed(page, ScanAppearance(cleanup: ScanCleanup(whitenBackground: 1)))
        let paper = Self.litPaper(result)
        #expect(paper.r > 247 && paper.g > 247 && paper.b > 247, "paper became \(paper)")
        #expect(paper.tint < 6, "paper kept a cast: \(paper)")
        #expect(Self.litInk(result).brightness < 80, "ink became \(Self.litInk(result))")
    }

    @Test func halfTheAmountWhitensPartWay() throws {
        let page = Self.evenPage(paper: RGB(r: 220, g: 210, b: 185))
        let before = Self.litPaper(page).brightness
        let half = Self.litPaper(try processed(page, ScanAppearance(cleanup: ScanCleanup(whitenBackground: 0.5)))).brightness
        let full = Self.litPaper(try processed(page, ScanAppearance(cleanup: ScanCleanup(whitenBackground: 1)))).brightness
        #expect(half > before + 8 && half < full - 8, "before \(before), half \(half), full \(full)")
    }

    // MARK: Sharpen text

    /// A soft edge between ink above and paper below, on a page the size of
    /// a real capture's preview. The steepest step between two rows is what
    /// sharpening has to raise; flat ink and flat paper must not move.
    @Test func sharpeningSteepensEdgesAndLeavesFlatAreasAlone() throws {
        let page = Bitmap(width: 1200, height: 1600) { _, y in
            let t = max(0, min(1, (Double(y) - 797) / 6))
            return .gray(40 + 190 * t * t * (3 - 2 * t))
        }
        func steepest(_ bitmap: Bitmap) -> Double {
            (780..<820).map { bitmap.mean(500, $0 + 1, 200, 1).brightness - bitmap.mean(500, $0, 200, 1).brightness }.max()!
        }
        let result = try processed(page, ScanAppearance(cleanup: ScanCleanup(sharpenText: 1)))
        #expect(steepest(result) > steepest(page) * 1.15, "steepest step \(steepest(page)) became \(steepest(result))")
        #expect(abs(result.mean(500, 300, 200, 100).brightness - 40) < 3)
        #expect(abs(result.mean(500, 1200, 200, 100).brightness - 230) < 3)
    }

    // MARK: Presets

    @Test func grayscaleTakesTheColourAndKeepsTheTones() throws {
        let result = try processed(Self.patchPage(), ScanAppearance(preset: .grayscale))
        let red = result.mean(150, 60, 100, 60), blue = result.mean(150, 190, 100, 60)
        let dark = result.mean(150, 450, 100, 60)
        #expect(red.tint < 3 && blue.tint < 3, "red \(red), blue \(blue)")
        #expect(red.brightness > 40 && red.brightness < 200, "a colour became \(red), not a gray")
        #expect(blue.brightness > 40 && blue.brightness < 200, "a colour became \(blue), not a gray")
        #expect(abs(dark.brightness - 90) < 12, "a gray moved: \(dark)")
    }

    /// The reason for judging ink against the paper around it: one threshold
    /// for the whole page would turn the shadowed quarter black.
    @Test func blackAndWhiteIsInkOnWhiteEvenUnderAShadow() throws {
        let result = try processed(Self.shadowedPage(), ScanAppearance(preset: .blackAndWhite))
        for (name, paper) in [("shadowed", Self.shadowPaper(result)), ("lit", Self.litPaper(result))] {
            #expect(paper.brightness > 245 && paper.tint < 3, "\(name) paper became \(paper)")
        }
        for (name, ink) in [("shadowed", Self.shadowInk(result)), ("lit", Self.litInk(result))] {
            #expect(ink.brightness < 40 && ink.tint < 3, "\(name) ink became \(ink)")
        }
    }

    @Test func highContrastWidensLightFromDarkAndKeepsColour() throws {
        let page = Self.patchPage()
        let result = try processed(page, ScanAppearance(preset: .highContrast))
        let gap = result.mean(150, 320, 100, 60).brightness - result.mean(150, 450, 100, 60).brightness
        #expect(gap > 80 * 1.25, "light and dark gray were 80 apart and are now \(gap)")
        let red = result.mean(150, 60, 100, 60)
        #expect(red.r - max(red.g, red.b) > 100, "red became \(red)")
    }

    /// Auto is the system's own correction, so what it does to a dull page is
    /// not pinned here; only that Enhanced goes further than Auto does.
    @Test func enhancedSeparatesInkFromPaperMoreThanAuto() throws {
        let page = Self.evenPage(paper: RGB(r: 170, g: 165, b: 150), ink: RGB(r: 90, g: 90, b: 96))
        func gap(_ preset: ScanPreset) throws -> Double {
            let result = try processed(page, ScanAppearance(preset: preset))
            return Self.litPaper(result).brightness - Self.litInk(result).brightness
        }
        let auto = try gap(.auto), enhanced = try gap(.enhanced)
        #expect(enhanced > auto + 5, "auto \(auto), enhanced \(enhanced)")
    }

    /// Thumbnails are drawn several at a time on Swift concurrency's threads.
    /// If Auto ever reaches Vision's face detector again, each call parks its
    /// thread waiting for Vision and Vision has none left to finish on: this
    /// test would then never return, and nothing running on those threads
    /// could report it. So a plain thread watches, and stops the run with the
    /// reason rather than leaving it hanging.
    @Test func manyPagesCanBeGivenTheAutoLookAtOnce() async throws {
        let page = Self.evenPage(paper: RGB(r: 170, g: 165, b: 150), ink: RGB(r: 90, g: 90, b: 96)).image
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            if finished.wait(timeout: .now() + 180) == .timedOut {
                fatalError("48 Auto pages at once did not finish in three minutes: automatic adjustment is waiting on Vision")
            }
        }
        let drawn = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<48 {
                group.addTask { ScanImageProcessor.apply(ScanAppearance(preset: .auto), to: page) != nil }
            }
            var count = 0
            for await succeeded in group where succeeded { count += 1 }
            return count
        }
        finished.signal()
        #expect(drawn == 48)
    }

    // MARK: Together, and at any size

    @Test func aPresetAndCleanupBothApply() throws {
        let page = Self.evenPage(paper: RGB(r: 220, g: 210, b: 185))
        let result = try processed(page, ScanAppearance(preset: .grayscale, cleanup: ScanCleanup(whitenBackground: 1)))
        let paper = Self.litPaper(result)
        #expect(paper.brightness > 245 && paper.tint < 3, "paper became \(paper)")
        #expect(Self.litInk(result).brightness < 80)
    }

    /// Every look, with and without Cleanup, on a picture that does not start
    /// at the origin, which is what a perspective-corrected capture is.
    @Test(arguments: ScanPreset.allCases, [ScanCleanup.none, .recommended, ScanCleanup(removeShadows: 1, whitenBackground: 1, sharpenText: 1)])
    func everyLookKeepsThePageSizeAndCoversIt(preset: ScanPreset, cleanup: ScanCleanup) throws {
        let source = CIImage(cgImage: Self.shadowedPage().image).transformed(by: CGAffineTransform(translationX: 37, y: -12))
        let output = ScanImageProcessor.apply(ScanAppearance(preset: preset, cleanup: cleanup), to: source)
        #expect(output.extent == source.extent)
        let rendered = Bitmap(try #require(CIContext().createCGImage(output, from: source.extent)))
        #expect(rendered.width == 400 && rendered.height == 560)
        for (x, y) in [(0, 0), (399, 0), (0, 559), (399, 559), (200, 280)] {
            #expect(rendered.alpha(x, y) == 255, "\(preset) left (\(x), \(y)) see-through")
        }
    }

    /// The preview is drawn from a small copy and the saved page from the full
    /// capture. Amounts are sized to the page, so both must show the same thing.
    @Test func aSmallPreviewShowsWhatTheFullPageWillLookLike() throws {
        let appearance = ScanAppearance(preset: .original, cleanup: ScanCleanup(removeShadows: 0.8, whitenBackground: 0.6))
        let small = try processed(Self.shadowedPage(), appearance)
        let large = try processed(Self.shadowedPage(scale: 3), appearance)
        for (name, x, y, w, h) in [("shadowed paper", 8, 90, 24, 80), ("lit paper", 368, 400, 24, 80),
                                   ("paper at the shadow's edge", 8, 250, 24, 60)] {
            let preview = small.mean(x, y, w, h), full = large.mean(x * 3, y * 3, w * 3, h * 3)
            #expect(abs(preview.brightness - full.brightness) < 5, "\(name): preview \(preview), full page \(full)")
        }
    }
}

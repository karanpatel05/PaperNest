import CoreGraphics
import Testing
@testable import PaperNestUI

/// The PaperNest watermark's logo, on the Mac (`scripts/test.sh`) and on iOS
/// (the `PaperNest-CanvasTests` target, which runs this file in the app on
/// the Simulator, where the asset catalogue is compiled and may be thinned).
@Suite struct WatermarkLogoTests {
    /// The large PaperNest watermark draws the mark about 85 points across, so
    /// a page printed at 300 dpi needs about 354 pixels of it (85 × 300 / 72).
    /// The logo is the mark at its own size in the approved art, not the
    /// icon rendition (144 pixels at most, 96 in the Mac build), which printed
    /// soft.
    @Test func theWatermarkLogoIsSharpEnoughToPrint() throws {
        let logo = try #require(BrandMark.watermarkLogo)
        #expect(logo.mask.width >= 354 && logo.mask.height >= 354,
                "the watermark logo is \(logo.mask.width) × \(logo.mask.height) pixels")
        #expect(logo.mask.width == logo.mask.height, "the mark is square")
    }

    /// The mask keeps the mark's shape: clear in the corner, solid in the ring.
    @Test func theLogoMaskIsTheMark() throws {
        let mask = try #require(BrandMark.watermarkLogo).mask
        let width = mask.width, height = mask.height
        var gray = [UInt8](repeating: 0, count: width * height)
        let ctx = try #require(CGContext(data: &gray, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        #expect(gray[0] < 20, "the corner outside the ring is not clear")
        // Halfway down, at the ring's left edge: the ring is solid there.
        let row = height / 2
        let ring = (0..<(width / 6)).map { Int(gray[row * width + $0]) }.max() ?? 0
        #expect(ring > 230, "no solid ring on the left: \(ring)")
    }
}

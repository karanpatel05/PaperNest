import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender

/// Book mode on drawn spreads: the real rectangle detector finding the
/// whole spread (or, when it finds only one page, that page not being cut
/// in half), and the fold found on the straightened spread. One at a time:
/// the detector parks the thread it is called on.
@Suite(.serialized) struct ScanBookTests {
    typealias Scenes = ScanEdgeDetectorTests

    // MARK: Drawing

    /// A photo `width` × `height` of a spread lying on a dark table: its
    /// `outline` (crop order), the fold at `gutter` across it drawn as
    /// `fold`, and the top and bottom edges curling toward the fold by `curl`
    /// (a share of the photo's height).
    enum Fold { case none, shadow, line }

    static func photo(width: Int, height: Int, outline: [CGPoint], gutter: Double = 0.5, fold: Fold = .shadow,
                      curl: Double = 0) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * CGFloat(width), y: (1 - point.y) * CGFloat(height)) }
        func along(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        func dip(_ t: Double) -> Double { curl * (1 - abs(t - gutter) / max(gutter, 1 - gutter)) }
        var path: [CGPoint] = []
        for i in 0...40 {
            let t = Double(i) / 40
            var point = along(outline[0], outline[1], t); point.y += dip(t); path.append(pixel(point))
        }
        for i in 0...40 {
            let t = Double(i) / 40
            var point = along(outline[2], outline[3], t); point.y -= dip(1 - t); path.append(pixel(point))
        }
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.beginPath(); context.addLines(between: path); context.closePath(); context.fillPath()
        var topShare = along(outline[0], outline[1], gutter), bottomShare = along(outline[3], outline[2], gutter)
        topShare.y += curl; bottomShare.y -= curl
        let top = pixel(topShare), bottom = pixel(bottomShare)
        let spreadWidth = pixel(outline[1]).x - pixel(outline[0]).x
        switch fold {
        case .shadow:
            // A soft band 6% of the spread wide, down to 0.6 at the fold.
            for i in -30...30 {
                let offset = CGFloat(i) / 30 * spreadWidth * 0.03
                context.setStrokeColor(CGColor(gray: 0.93 - 0.33 * (1 - abs(Double(i)) / 30), alpha: 1))
                context.setLineWidth(spreadWidth * 0.001 + 1)
                context.move(to: CGPoint(x: top.x + offset, y: top.y))
                context.addLine(to: CGPoint(x: bottom.x + offset, y: bottom.y))
                context.strokePath()
            }
        case .line:
            context.setStrokeColor(CGColor(gray: 0.35, alpha: 1)); context.setLineWidth(CGFloat(width) * 0.006)
            context.move(to: top); context.addLine(to: bottom); context.strokePath()
        case .none:
            break
        }
        return context.makeImage()!
    }

    /// A straightened spread, 1600 × 1000: two pages of print with inner
    /// margins, the fold at `gutter` as a shadow darkening paper and ink
    /// alike (`shadowDepth`, 0 for none, over 4% of the width) or a dark
    /// line, and optionally a dark picture on the right page near the fold.
    static func straight(gutter: Double = 0.5, shadowDepth: Double = 0.35, line: Bool = false, picture: Bool = false) -> CGImage {
        let width = 1600, height = 1000
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.92, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.1, alpha: 1)] as CFDictionary
        let fold = gutter * Double(width)
        for (left, right) in [(70.0, fold - 60), (fold + 60, Double(width) - 70)] {
            var y = Double(height) - 80
            var n = 0
            while y > 80 {
                let words = String(repeating: "the report shows growth in every region ", count: 4)
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, words as CFString, attributes))
                context.saveGState()
                context.clip(to: CGRect(x: left, y: 0, width: right - left - Double(n % 3) * 40, height: Double(height)))
                context.textPosition = CGPoint(x: left, y: y)
                CTLineDraw(line, context)
                context.restoreGState()
                y -= 26; n += 1
            }
        }
        if picture {
            // A dark photograph on the right page, close to the fold, a quarter of the height.
            context.setFillColor(gray: 0.12, alpha: 1)
            context.fill(CGRect(x: Double(width) * 0.54, y: Double(height) * 0.45, width: Double(width) * 0.08, height: Double(height) * 0.25))
        }
        var image = context.makeImage()!
        if shadowDepth > 0 {
            let picture = DocumentComparer.gray(image)!
            var pixels = picture.pixels
            for x in 0..<width {
                let falloff = max(0, 1 - abs(Double(x) - fold) / (0.02 * Double(width)))
                let light = 1 - shadowDepth * falloff
                for y in 0..<height { pixels[y * width + x] = UInt8(Double(pixels[y * width + x]) * light) }
            }
            image = ScanQualityAnalyzerTests.grey(pixels, width: width, height: height)
        }
        if line {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(gray: 0.3, alpha: 1)
            ctx.fill(CGRect(x: fold - 4, y: 0, width: 8, height: Double(height)))
            image = ctx.makeImage()!
        }
        return image
    }

    // MARK: The fold

    @Test func aFoldShadowOffTheMiddleIsFound() {
        #expect(abs(ScanGutter.find(in: Self.straight(gutter: 0.45)) - 0.45) < 0.01)
        #expect(abs(ScanGutter.find(in: Self.straight(gutter: 0.55)) - 0.55) < 0.01)
    }

    @Test func aDarkFoldLineIsFound() {
        #expect(abs(ScanGutter.find(in: Self.straight(gutter: 0.52, shadowDepth: 0, line: true)) - 0.52) < 0.01)
    }

    /// No fold to see: halfway.
    @Test func withoutAFoldTheSpreadIsSplitHalfway() {
        #expect(ScanGutter.find(in: Self.straight(shadowDepth: 0)) == 0.5)
    }

    /// A dark picture near the fold covers part of the height, not all of
    /// it: it does not pull the split, with a fold or without.
    @Test func aDarkPictureNearTheMiddleDoesNotPullTheSplit() {
        #expect(ScanGutter.find(in: Self.straight(shadowDepth: 0, picture: true)) == 0.5)
        #expect(abs(ScanGutter.find(in: Self.straight(gutter: 0.47, picture: true)) - 0.47) < 0.01)
    }

    // MARK: The spread, found by the real detector

    private func spreadFound(_ photo: CGImage, outline: [CGPoint]) throws -> ScanQuad {
        let detection = try #require(ScanCaptureMode.book.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: photo), "nothing found")
        #expect(Scenes.worstMiss(found, outline) < 0.03, "found \(found.corners)")
        #expect(ScanSpread.isSpread(found.corners, photoSize: CGSize(width: photo.width, height: photo.height)))
        return found
    }

    static let landscape = Scenes.corners((0.10, 0.18), (0.90, 0.16), (0.92, 0.84), (0.08, 0.86))
    static let portrait = Scenes.corners((0.08, 0.30), (0.92, 0.29), (0.93, 0.71), (0.07, 0.72))

    /// Fold shadow, dark fold line, or none; flat or curling toward the
    /// fold: the whole spread, in a landscape photo and a portrait one.
    @Test(arguments: [Fold.none, .shadow, .line])
    func theWholeSpreadIsFound(fold: Fold) throws {
        for curl in [0.0, 0.02] {
            _ = try spreadFound(Self.photo(width: 1600, height: 1200, outline: Self.landscape, fold: fold, curl: curl),
                                outline: Self.landscape)
            _ = try spreadFound(Self.photo(width: 1200, height: 1600, outline: Self.portrait, fold: fold, curl: curl),
                                outline: Self.portrait)
        }
    }

    /// One upright page in Book mode is found and kept as one page.
    @Test func anUprightPageInBookModeIsNotASpread() throws {
        let page = Scenes.corners((0.2, 0.1), (0.8, 0.1), (0.8, 0.9), (0.2, 0.9))
        let photo = Scenes.scene(width: 1200, height: 1600, ground: 0.2, [(page, 0.93)])
        let detection = try #require(ScanCaptureMode.book.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: photo))
        #expect(Scenes.worstMiss(found, page) < 0.03)
        #expect(!ScanSpread.isSpread(found.corners, photoSize: CGSize(width: 1200, height: 1600)))
    }

    /// Pages curling strongly in a portrait photo: the detector found only
    /// one page (measured). It is kept whole — never cut in half.
    @Test func whenOnlyOnePageIsFoundItIsNotCutInHalf() throws {
        let photo = Self.photo(width: 1200, height: 1600, outline: Self.portrait, fold: .line, curl: 0.04)
        let detection = try #require(ScanCaptureMode.book.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: photo))
        // If this fails, the detector now finds the whole spread here and the case needs a stronger curl.
        #expect(Scenes.worstMiss(found, Self.portrait) > 0.1, "the whole spread was found: \(found.corners)")
        #expect(!ScanSpread.isSpread(found.corners, photoSize: CGSize(width: 1200, height: 1600)), "found \(found.corners)")
    }

    /// From photo to two pages: the spread found at an angle, straightened
    /// as a crop is, its fold found, and the split line in the photo landing
    /// on the fold as drawn.
    @Test func aSpreadPhotographedAtAnAngleSplitsAtItsFold() throws {
        let outline = Scenes.corners((0.08, 0.22), (0.86, 0.12), (0.94, 0.86), (0.06, 0.80))
        let image = Self.photo(width: 1600, height: 1200, outline: outline, gutter: 0.5, fold: .shadow)
        let found = try spreadFound(image, outline: outline)
        // Straightened as ScannerPage crops: Core Image's perspective correction to the found corners.
        let source = CIImage(cgImage: image)
        func vector(_ point: CGPoint) -> CIVector { CIVector(x: point.x * source.extent.width, y: (1 - point.y) * source.extent.height) }
        let correction = try #require(CIFilter(name: "CIPerspectiveCorrection"))
        correction.setValue(source, forKey: kCIInputImageKey)
        correction.setValue(vector(found.topLeft), forKey: "inputTopLeft")
        correction.setValue(vector(found.topRight), forKey: "inputTopRight")
        correction.setValue(vector(found.bottomRight), forKey: "inputBottomRight")
        correction.setValue(vector(found.bottomLeft), forKey: "inputBottomLeft")
        let straightened = try #require(correction.outputImage)
        let spread = try #require(CIContext().createCGImage(straightened, from: straightened.extent))
        let gutter = ScanGutter.find(in: spread)
        let halves = ScanSpread.halves(of: found.corners, at: gutter)
        // The fold as drawn runs between the edges' midpoints (the drawing interpolates along the edges).
        let drawnTop = CGPoint(x: (outline[0].x + outline[1].x) / 2, y: (outline[0].y + outline[1].y) / 2)
        let drawnBottom = CGPoint(x: (outline[3].x + outline[2].x) / 2, y: (outline[3].y + outline[2].y) / 2)
        #expect(Double(hypot(halves[0][1].x - drawnTop.x, halves[0][1].y - drawnTop.y)) < 0.02, "top of the fold \(halves[0][1])")
        #expect(Double(hypot(halves[0][2].x - drawnBottom.x, halves[0][2].y - drawnBottom.y)) < 0.02,
                "bottom of the fold \(halves[0][2])")
    }
}

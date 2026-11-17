import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
@testable import PaperNestExport

private let letter = CGSize(width: 612, height: 792)

/// A template logo as `BrandMark` stores one: a white disc whose alpha is the
/// shape, on nothing.
func syntheticLogo(side: Int = 64) -> WatermarkLogo {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
    return WatermarkLogo(name: "test-disc", template: ctx.makeImage()!)!
}

/// Draws `watermark` onto white paper of `pageSize` at one pixel per point,
/// through the same page-space flip the exporter uses.
private func paper(_ watermark: Watermark?, pageSize: CGSize = letter) -> WatermarkBitmap {
    let width = Int(pageSize.width), height = Int(pageSize.height)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    if let watermark { WatermarkDrawing.draw(watermark, pageSize: pageSize, in: ctx) }
    return WatermarkBitmap(ctx.makeImage()!)
}

/// Pixels of a picture, addressed from the top-left in page points.
struct WatermarkBitmap: Equatable {
    let width: Int, height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// Pixels in `rect` (page points, top-left origin) that are not white,
    /// and their average colour.
    func marked(in rect: CGRect) -> (count: Int, red: Double, green: Double, blue: Double) {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull else { return (0, 0, 0, 0) }
        var count = 0, r = 0, g = 0, b = 0
        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            for x in Int(clipped.minX)..<Int(clipped.maxX) {
                let i = (y * width + x) * 4
                if bytes[i] < 250 || bytes[i + 1] < 250 || bytes[i + 2] < 250 {
                    count += 1; r += Int(bytes[i]); g += Int(bytes[i + 1]); b += Int(bytes[i + 2])
                }
            }
        }
        guard count > 0 else { return (0, 0, 0, 0) }
        return (count, Double(r) / Double(count), Double(g) / Double(count), Double(b) / Double(count))
    }

    /// The darkest any channel gets anywhere: how strongly the mark shows.
    var darkest: UInt8 {
        var lowest: UInt8 = 255
        for i in stride(from: 0, to: bytes.count, by: 4) { lowest = min(lowest, bytes[i], bytes[i + 1], bytes[i + 2]) }
        return lowest
    }
}

@Suite struct WatermarkModelTests {
    @Test func eachPresetStartsFromItsOwnLook() {
        let confidential = Watermark(preset: .confidential, text: "CONFIDENTIAL")
        #expect(confidential.placement == .center)
        #expect(confidential.rotation == -32)
        #expect(confidential.opacity == 0.18)
        #expect(confidential.shape == .text)

        let draft = Watermark(preset: .draft, text: "DRAFT")
        #expect(draft.placement == .topRight)
        #expect(draft.rotation == 0)
        #expect(draft.opacity == 0.9)
        #expect(draft.shape == .capsule)

        let approved = Watermark(preset: .approved, text: "APPROVED")
        #expect(approved.placement == .bottomRight)
        #expect(approved.shape == .stamp)
        #expect(approved.opacity == 0.85)

        let custom = Watermark(preset: .custom, text: "Acme Ltd")
        #expect(custom.placement == .center)
        #expect(custom.shape == .text)
        // Five presets, five colours a reader can tell apart.
        #expect(Set(WatermarkPreset.allCases.map(\.color)).count == 5)
    }

    /// The branded preset as the design gives it: centred, −32°, within
    /// 10–16% opacity, in the deep accent, the logo beside the name.
    @Test func thePaperNestPresetStartsFromTheDesign() {
        let mark = Watermark(preset: .paperNest, text: "PaperNest", logo: syntheticLogo())
        #expect(mark.placement == .center)
        #expect(mark.rotation == -32)
        #expect((0.10...0.16).contains(mark.opacity))
        #expect(mark.shape == .brand)
        #expect(mark.color == RGBAColor(red: 0.333, green: 0.129, blue: 0.796))
        #expect(mark.logo == syntheticLogo())
    }

    /// The small mark free exports carry, defined once.
    @Test func theFreeExportMarkIsSmallUprightAndBottomLeft() {
        let mark = Watermark.attribution(name: "PaperNest", logo: syntheticLogo())
        #expect(mark.preset == .paperNest)
        #expect(mark.placement == .bottomLeft)
        #expect(mark.rotation == 0)
        #expect(mark.opacity == 0.55)
        #expect(mark.text == "PaperNest")
    }

    /// A template becomes a mask of its shape: white where the disc is, black
    /// where there was nothing.
    @Test func aLogoIsKeptAsAMaskOfItsShape() {
        let mask = WatermarkBitmap(syntheticLogo().mask)
        #expect(mask.bytes[(32 * mask.width + 32) * 4] > 250, "the disc's middle is not white")
        #expect(mask.bytes[(1 * mask.width + 1) * 4] < 5, "the empty corner is not black")
        #expect(syntheticLogo() == syntheticLogo())
        #expect(syntheticLogo(side: 32) != syntheticLogo())
    }

    @Test func valuesOutsideTheirRangeAreBroughtBackIntoIt() {
        var mark = Watermark(preset: .custom, text: String(repeating: "x", count: 100), opacity: 3, rotation: 400)
        #expect(mark.text.count == Watermark.maxTextLength)
        #expect(mark.opacity == 1)
        #expect(mark.rotation == 90)
        mark.opacity = -1
        mark.rotation = -400
        mark.text = String(repeating: "y", count: 60)
        #expect(mark.opacity == Watermark.opacityRange.lowerBound)
        #expect(mark.rotation == -90)
        #expect(mark.text.count == Watermark.maxTextLength)
        mark.opacity = .nan
        #expect(mark.opacity == Watermark.opacityRange.lowerBound)
    }

    @Test func blankTextDrawsNothing() {
        #expect(!Watermark(preset: .custom, text: "   \n ").isVisible)
        #expect(Watermark(preset: .custom, text: "\n Acme \n").drawnText == "Acme")
        #expect(WatermarkDrawing.marks(for: Watermark(preset: .custom, text: " "), pageSize: letter).isEmpty)
        #expect(paper(Watermark(preset: .custom, text: " ")) == paper(nil))
    }

    /// A colour emoji has no outline to draw. Alone it is no watermark at all;
    /// beside letters, the letters still draw.
    @Test func textThatDrawsNoOutlineIsNotAWatermark() {
        let emoji = Watermark(preset: .custom, text: "🔒✅")
        #expect(!emoji.isVisible)
        #expect(WatermarkDrawing.marks(for: emoji, pageSize: letter).isEmpty)
        #expect(paper(emoji) == paper(nil))
        #expect(Watermark(preset: .custom, text: "TOP 🔒 SECRET").isVisible)
    }

    @Test func onlyFormatsWithAPictureOfThePageCarryOne() {
        #expect(ExportFormat.pdf.canCarryWatermark)
        #expect(ExportFormat.jpeg.canCarryWatermark)
        #expect(ExportFormat.png.canCarryWatermark)
        #expect(ExportFormat.heic.canCarryWatermark)
        #expect(!ExportFormat.txt.canCarryWatermark)
        #expect(!ExportFormat.docx.canCarryWatermark)
    }
}

@Suite struct WatermarkLayoutTests {
    @Test func centerIsInTheMiddleAndInsideThePage() throws {
        for size in [letter, CGSize(width: 842, height: 595)] {
            let marks = WatermarkDrawing.marks(for: Watermark(preset: .confidential, text: "CONFIDENTIAL"), pageSize: size)
            let mark = try #require(marks.first)
            #expect(marks.count == 1)
            #expect(abs(mark.center.x - size.width / 2) < 0.5)
            #expect(abs(mark.center.y - size.height / 2) < 0.5)
            #expect(CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.07, dy: size.height * 0.07)
                .contains(mark.boundingBox))
        }
    }

    @Test func cornersSitInsideTheMarginOfTheirCorner() throws {
        let margin = WatermarkDrawing.cornerMargin
        let top = try #require(WatermarkDrawing.marks(for: Watermark(preset: .draft, text: "DRAFT"), pageSize: letter).first)
        #expect(abs(top.boundingBox.maxX - (letter.width - margin)) < 0.5)
        #expect(abs(top.boundingBox.minY - margin) < 0.5)

        let bottom = try #require(WatermarkDrawing.marks(for: Watermark(preset: .approved, text: "APPROVED"),
                                                         pageSize: letter).first)
        #expect(abs(bottom.boundingBox.maxX - (letter.width - margin)) < 0.5)
        #expect(abs(bottom.boundingBox.maxY - (letter.height - margin)) < 0.5)

        // Any preset can go in any corner, turned or not.
        let turned = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .confidential, text: "CONFIDENTIAL", placement: .topRight, rotation: -32),
            pageSize: letter).first)
        #expect(abs(turned.boundingBox.maxX - (letter.width - margin)) < 0.5)
        #expect(abs(turned.boundingBox.minY - margin) < 0.5)
    }

    @Test func bottomLeftSitsInItsCorner() throws {
        let margin = WatermarkDrawing.cornerMargin
        let mark = try #require(WatermarkDrawing.marks(
            for: Watermark.attribution(name: "PaperNest", logo: syntheticLogo()), pageSize: letter).first)
        #expect(abs(mark.boundingBox.minX - margin) < 0.5)
        #expect(abs(mark.boundingBox.maxY - (letter.height - margin)) < 0.5)
        // Small: a line of type, not a banner.
        #expect(mark.boundingBox.height < 20)
        #expect(mark.boundingBox.width < 120)
    }

    /// The logo takes room beside the name; without one the name stands alone.
    @Test func theLogoSitsBeforeTheName() throws {
        let with = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .paperNest, text: "PaperNest", rotation: 0, logo: syntheticLogo()), pageSize: letter).first)
        let without = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .paperNest, text: "PaperNest", rotation: 0), pageSize: letter).first)
        #expect(with.size.width > without.size.width * 1.1)
    }

    @Test func rotationTurnsTheMark() throws {
        let flat = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .confidential, text: "CONFIDENTIAL", rotation: 0), pageSize: letter).first)
        let turned = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .confidential, text: "CONFIDENTIAL", rotation: -32), pageSize: letter).first)
        #expect(flat.angle == 0)
        #expect(abs(turned.angle - (-32 * .pi / 180)) < 0.0001)
        // A turned word stands taller than the same word lying flat.
        #expect(turned.boundingBox.height > flat.boundingBox.height * 2)
    }

    @Test func tiledCoversThePageToItsCorners() {
        let marks = WatermarkDrawing.marks(for: Watermark(preset: .custom, text: "Acme · 2026", placement: .tiled),
                                           pageSize: letter)
        #expect(marks.count >= 6)
        for corner in [CGPoint(x: 1, y: 1), CGPoint(x: 611, y: 1), CGPoint(x: 1, y: 791), CGPoint(x: 611, y: 791)] {
            let nearest = marks.map { hypot($0.center.x - corner.x, $0.center.y - corner.y) }.min() ?? .infinity
            let reach = marks.map { max($0.boundingBox.width, $0.boundingBox.height) }.max() ?? 0
            #expect(nearest < reach, "corner \(corner) is not near any tile")
        }
    }

    /// One narrow letter makes a capsule narrower than it is tall; it still
    /// draws, inside the page, in its corner.
    @Test func aSingleNarrowLetterStillDraws() throws {
        for preset in [WatermarkPreset.draft, .approved] {
            let mark = Watermark(preset: preset, text: "I")
            let laid = try #require(WatermarkDrawing.marks(for: mark, pageSize: letter).first)
            #expect(CGRect(origin: .zero, size: letter).contains(laid.boundingBox))
            #expect(paper(mark).marked(in: laid.boundingBox).count > 20)
        }
    }

    @Test func longTiledTextStillRepeats() {
        let long = Watermark(preset: .custom, text: String(repeating: "Acme ", count: 8), placement: .tiled)
        #expect(WatermarkDrawing.marks(for: long, pageSize: letter).count >= 6)
    }

    @Test func longTextShrinksToFitItsCorner() throws {
        let long = Watermark(preset: .approved, text: String(repeating: "W", count: 40), placement: .bottomRight)
        let mark = try #require(WatermarkDrawing.marks(for: long, pageSize: letter).first)
        #expect(CGRect(origin: .zero, size: letter).contains(mark.boundingBox))
    }

    @Test func sizesFollowThePageNotThePoint() throws {
        let draft = Watermark(preset: .draft, text: "DRAFT")
        let small = try #require(WatermarkDrawing.marks(for: draft, pageSize: letter).first)
        let large = try #require(WatermarkDrawing.marks(
            for: draft, pageSize: CGSize(width: letter.width * 2, height: letter.height * 2)).first)
        #expect(abs(large.size.width / small.size.width - 2) < 0.02)
        #expect(abs(large.size.height / small.size.height - 2) < 0.02)
    }

    @Test func aDateLineMakesTheStampTaller() throws {
        let plain = try #require(WatermarkDrawing.marks(for: Watermark(preset: .approved, text: "APPROVED"),
                                                        pageSize: letter).first)
        let dated = try #require(WatermarkDrawing.marks(
            for: Watermark(preset: .approved, text: "APPROVED", dateLine: "Nov 16, 2026"), pageSize: letter).first)
        #expect(dated.size.height > plain.size.height * 1.3)
    }
}

@Suite struct WatermarkDrawingTests {
    @Test func confidentialIsRedInTheMiddleOfThePage() {
        let page = paper(Watermark(preset: .confidential, text: "CONFIDENTIAL"))
        let middle = page.marked(in: CGRect(x: 156, y: 246, width: 300, height: 300))
        #expect(middle.count > 2_000)
        #expect(middle.red > middle.green + 15 && middle.red > middle.blue + 15)
        // Faint, as the design asks: a reader sees through it.
        #expect(page.darkest > 150)
    }

    @Test func draftIsATintedCapsuleTopRightAndNowhereElse() {
        let page = paper(Watermark(preset: .draft, text: "DRAFT"))
        let topRight = page.marked(in: CGRect(x: 412, y: 0, width: 200, height: 120))
        #expect(topRight.count > 500)
        #expect(topRight.blue > topRight.green + 15)
        #expect(page.marked(in: CGRect(x: 0, y: 200, width: 612, height: 592)).count == 0)
    }

    @Test func approvedIsGreenBottomRightAndNowhereElse() {
        let page = paper(Watermark(preset: .approved, text: "APPROVED", dateLine: "16 Nov 2026"))
        let bottomRight = page.marked(in: CGRect(x: 362, y: 642, width: 250, height: 150))
        #expect(bottomRight.count > 500)
        #expect(bottomRight.green > bottomRight.red + 15)
        #expect(page.marked(in: CGRect(x: 0, y: 0, width: 612, height: 500)).count == 0)
    }

    @Test func tiledMarksEveryQuarterOfThePage() {
        let page = paper(Watermark(preset: .custom, text: "Acme · 2026", placement: .tiled, opacity: 0.4))
        for quarter in [CGRect(x: 0, y: 0, width: 306, height: 396), CGRect(x: 306, y: 0, width: 306, height: 396),
                        CGRect(x: 0, y: 396, width: 306, height: 396), CGRect(x: 306, y: 396, width: 306, height: 396)] {
            #expect(page.marked(in: quarter).count > 300, "nothing drawn in \(quarter)")
        }
    }

    /// The brand mark draws its logo, in the brand's colour, to the left of
    /// the name: purple where the disc is, at the start of the mark.
    @Test func theBrandMarkPaintsItsLogoInTheBrandColour() throws {
        let mark = Watermark(preset: .paperNest, text: "PaperNest", opacity: 1, rotation: 0, logo: syntheticLogo())
        let laid = try #require(WatermarkDrawing.marks(for: mark, pageSize: letter).first)
        let page = paper(mark)
        let box = laid.boundingBox
        // The logo is a square as tall as the mark, at its left end.
        let logo = page.marked(in: CGRect(x: box.minX, y: box.minY, width: box.height, height: box.height))
        #expect(logo.count > Int(box.height * box.height * 0.5), "the logo's disc is not drawn")
        #expect(logo.blue > logo.green + 60 && logo.red > logo.green, "the logo is not in the brand's purple")
        // The free-export mark draws only in its corner.
        let free = paper(Watermark.attribution(name: "PaperNest", logo: syntheticLogo()))
        #expect(free.marked(in: CGRect(x: 0, y: 740, width: 160, height: 52)).count > 100)
        #expect(free.marked(in: CGRect(x: 0, y: 0, width: 612, height: 700)).count == 0)
        #expect(free.marked(in: CGRect(x: 200, y: 700, width: 412, height: 92)).count == 0)
    }

    /// A lopsided logo — its top half filled — comes out the right way up,
    /// so a flip missing or doubled in the logo's square cannot pass.
    @Test func theLogoIsUpright() throws {
        let side = 64
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))   // y-up: the top half
        let topHalf = try #require(WatermarkLogo(name: "top-half", template: ctx.makeImage()!))
        let mark = Watermark(preset: .paperNest, text: "PaperNest", opacity: 1, rotation: 0, logo: topHalf)
        let laid = try #require(WatermarkDrawing.marks(for: mark, pageSize: letter).first)
        let square = CGRect(x: laid.boundingBox.minX, y: laid.boundingBox.minY,
                            width: laid.boundingBox.height, height: laid.boundingBox.height)
        let page = paper(mark)
        let top = page.marked(in: CGRect(x: square.minX + 2, y: square.minY + 2, width: square.width - 4, height: square.height / 2 - 4))
        let bottom = page.marked(in: CGRect(x: square.minX + 2, y: square.midY + 2, width: square.width - 4, height: square.height / 2 - 4))
        #expect(top.count > bottom.count * 10, "the logo is upside down on a picture (top \(top.count), bottom \(bottom.count))")
    }

    @Test func higherOpacityShowsMoreStrongly() {
        let faint = paper(Watermark(preset: .confidential, text: "CONFIDENTIAL", opacity: 0.1))
        let strong = paper(Watermark(preset: .confidential, text: "CONFIDENTIAL", opacity: 0.8))
        #expect(Int(strong.darkest) + 60 < Int(faint.darkest))
    }

    @Test func drawingTwiceGivesTheSamePixels() {
        let mark = Watermark(preset: .approved, text: "APPROUVÉ", dateLine: "16 nov. 2026")
        #expect(paper(mark) == paper(mark))
    }

    /// The image export's path: over a picture of the page, at the picture's
    /// own resolution, the same marks as drawn straight onto the page.
    @Test func applyingToAPictureDrawsTheSameMarksAtItsResolution() throws {
        let mark = Watermark(preset: .draft, text: "DRAFT")
        let white = try #require(CGContext(data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        white.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        white.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
        let picture = WatermarkBitmap(try WatermarkDrawing.applying(mark, to: white.makeImage()!, pageSize: letter))
        #expect(picture.width == 1224 && picture.height == 1584)
        // Top right at twice the scale: the capsule is where it is on the page.
        let topRight = picture.marked(in: CGRect(x: 824, y: 0, width: 400, height: 240))
        #expect(topRight.count > 2_000)
        #expect(topRight.blue > topRight.green + 15)
        #expect(picture.marked(in: CGRect(x: 0, y: 400, width: 1224, height: 1184)).count == 0)

        let blank = white.makeImage()!
        #expect(try WatermarkDrawing.applying(Watermark(preset: .custom, text: ""), to: blank, pageSize: letter) === blank)
    }

    /// The letters are shapes: a reader searching or copying the page never
    /// finds the watermark's words.
    @Test func lettersAreOutlinesNotText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watermark-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(origin: .zero, size: letter)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Invoice total", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font]))
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, ctx)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: letter.height)
        ctx.scaleBy(x: 1, y: -1)
        WatermarkDrawing.draw(Watermark(preset: .approved, text: "APPROVED", dateLine: "Nov 16, 2026"),
                              pageSize: letter, in: ctx)
        ctx.restoreGState()
        ctx.endPDFPage()
        ctx.closePDF()

        let text = try #require(PDFDocument(url: url)?.page(at: 0)?.string)
        #expect(text.contains("Invoice total"))
        #expect(!text.contains("APPROVED"))
        #expect(!text.contains("2026"))
    }
}

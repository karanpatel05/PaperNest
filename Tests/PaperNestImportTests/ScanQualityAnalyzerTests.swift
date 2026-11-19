import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PaperNestCore
@testable import PaperNestRender

/// The advice after a capture, measured on drawn pages: print drawn sharp
/// and then blurred by a known amount, paper darkened, a page dense with
/// print, a blank sheet lit unevenly, and corners flat and steep. No camera
/// was used, so these fix what each measure means rather than proving it on
/// real photographs (`ScanQualityReport`).
@Suite struct ScanQualityAnalyzerTests {
    /// A page `width` × `height` pixels: lines of print sized for the page,
    /// in `ink` on `paper` (0 black … 1 white), then blurred by `blur`
    /// pixels (a Gaussian's sigma at this size). `letters` is the type size
    /// as a share of the width (0.012 is about 10 pt on A4). `cover` blackens
    /// that share of the page from the top first, as a printed photograph
    /// would; `grain` adds a camera's grain; `shade` darkens the paper down
    /// the page, as uneven light does.
    static func page(width: Int, height: Int, paper: CGFloat = 0.96, ink: CGFloat = 0.1, blur: Double = 0,
                     cover: Double = 0, print: Bool = true, letters: Double = 0.022, grain: Int = 0,
                     shade: CGFloat = 0) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: paper, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if shade > 0 {
            // Light falling off down the page: `paper` at the top, darker by `shade` at the foot.
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                      colors: [CGColor(gray: paper, alpha: 1), CGColor(gray: paper - shade, alpha: 1)] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        }
        let covered = CGFloat(cover) * CGFloat(height)
        if covered > 0 {
            context.setFillColor(gray: ink, alpha: 1)
            context.fill(CGRect(x: 0, y: CGFloat(height) - covered, width: CGFloat(width), height: covered))
        }
        if print {
            let size = CGFloat(width) * CGFloat(letters)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: ink, alpha: 1)] as CFDictionary
            let words = "The quarterly report shows steady growth in every region we serve, with costs held flat."
            var y = CGFloat(height) - covered - size * 3
            while y > size * 2 {
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, words as CFString, attributes))
                context.textPosition = CGPoint(x: CGFloat(width) * 0.06, y: y)
                CTLineDraw(line, context)
                y -= size * 1.6
            }
        }
        let image = context.makeImage()!
        let soft = blur > 0 ? blurred(image, sigma: blur) : image
        return grain > 0 ? grained(soft, by: grain) : soft
    }

    /// `image` with each pixel moved up or down by up to `amount` of 255, the
    /// same way every run: a camera's grain, roughly.
    static func grained(_ image: CGImage, by amount: Int) -> CGImage {
        let picture = DocumentComparer.gray(image)!
        var state: UInt64 = 0x9E3779B97F4A7C15
        let pixels = picture.pixels.map { value -> UInt8 in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let offset = Int((state >> 33) % UInt64(2 * amount + 1)) - amount
            return UInt8(max(0, min(255, Int(value) + offset)))
        }
        return grey(pixels, width: picture.width, height: picture.height)
    }

    /// `image` blurred by a Gaussian of `sigma` pixels, its edges extended.
    static func blurred(_ image: CGImage, sigma: Double) -> CGImage {
        let picture = DocumentComparer.gray(image)!
        let plane = ScanImageProcessor.Lighting.blurred(picture.pixels.map { Float($0) / 255 }, width: picture.width,
                                                        height: picture.height, sigma: sigma, extendingEdges: true)
        return grey(plane.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }, width: picture.width, height: picture.height)
    }

    static func grey(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func report(_ image: CGImage, corners: [CGPoint] = ScannerCorners.whole,
                photo: CGSize? = CGSize(width: 3000, height: 4000)) throws -> ScanQualityReport {
        try #require(ScanQualityAnalyzer.report(page: image, corners: corners, photoSize: photo))
    }

    /// Small print, ordinary print and headlines, drawn sharp, or softened
    /// by a sigma of 1 pixel at the measuring size (2 on these 2000-pixel
    /// pages): none is called blurry. Measured: 0.45, 0.62 and 0.38 sharp;
    /// 0.34, 0.49 and 0.34 softened.
    @Test(arguments: [0.012, 0.022, 0.06])
    func aSharpOrSlightlySoftPageIsNotCalledBlurry(letters: Double) throws {
        for blur in [0.0, 2.0] {
            let measured = try report(Self.page(width: 2000, height: 2600, blur: blur, letters: letters, grain: 4))
            #expect(measured.issues.isEmpty, "letters \(letters), blur \(blur): \(measured)")
            #expect(try #require(measured.sharpness) > ScanQualityReport.blurryBelow + 0.1, "too close to the line to trust")
        }
    }

    /// Blurred by 3.5 pixels at the measuring size, about 1 mm on a sheet
    /// of A4, the print can no longer be read, at any size, grain or not.
    /// Measured: 0.17, 0.10 and 0.16.
    @Test(arguments: [0.012, 0.022, 0.06])
    func aPageBlurredPastReadingIsBlurry(letters: Double) throws {
        let measured = try report(Self.page(width: 2000, height: 2600, blur: 7, letters: letters, grain: 4))
        #expect(measured.issues == [.blurry], "letters \(letters): \(measured)")
    }

    /// Blurred as a lens blurs, in linear light (Core Image), print goes
    /// grey faster than blurred in a grey picture's own shades: until, here,
    /// it is only a faint grey. The page is still blurry — not blank, and not
    /// sharp. Both happened: judged by the gap between the paper and the
    /// darkest marks on the whole page, faint print was taken for a blank
    /// sheet; and measured on the picture as it is, the steps between a grey
    /// picture's shades were all the edges left, and the page read as sharp.
    @Test(arguments: [0.018, 0.022])
    func printBlurredUntilFaintIsStillBlurry(letters: Double) throws {
        let source = CIImage(cgImage: Self.page(width: 1200, height: 1560, letters: letters))
        let soft = source.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: source.extent)
        let image = try #require(CIContext().createCGImage(soft, from: source.extent))
        let measured = try report(image)
        #expect(measured.sharpness != nil, "letters \(letters): taken for a blank page")
        #expect(measured.issues == [.blurry], "letters \(letters): \(measured)")
    }

    /// The same page with the same blur, photographed at half or twice the
    /// pixels, reads the same: the page is measured at one size. Without
    /// that, the larger photo's blur would count as fewer pixels' worth.
    @Test func theSamePageReadsTheSameAtAnyResolution() throws {
        for (blur, verdict) in [(1.0, [ScanQualityIssue]()), (3.5, [.blurry])] {
            let small = try report(Self.page(width: 1500, height: 1950, blur: blur * 1.5))
            let large = try report(Self.page(width: 3000, height: 3900, blur: blur * 3))
            #expect(abs(try #require(small.sharpness) - (try #require(large.sharpness))) < 0.03, "\(small) vs \(large)")
            #expect(small.issues == verdict && large.issues == verdict, "blur \(blur): \(small.issues), \(large.issues)")
        }
    }

    /// A blank sheet has no edges to judge, so it gets no verdict on focus,
    /// even unevenly lit and grainy.
    @Test func aBlankSheetIsNotJudgedForFocus() throws {
        let blank = try report(Self.page(width: 2000, height: 2600, paper: 0.92, print: false, grain: 2, shade: 0.08))
        #expect(blank.sharpness == nil)
        #expect(blank.issues.isEmpty)
    }

    /// Dark paper is too dark, and its focus is not judged however soft it
    /// is: a dark capture's grain would only mislead.
    @Test func aDarkPageIsTooDarkAndNothingElse() throws {
        let dark = try report(Self.page(width: 2000, height: 2600, paper: 0.2, ink: 0.03, blur: 7))
        #expect(dark.paperBrightness < ScanQualityReport.darkBelow)
        #expect(dark.issues == [.tooDark])
    }

    /// A page four fifths covered in black print, well lit: its paper is
    /// bright, though its average is darker than the darkness line.
    @Test func aPageDenseWithPrintIsNotTakenForADarkOne() throws {
        let dense = try report(Self.page(width: 2000, height: 2600, cover: 0.8))
        #expect(dense.paperBrightness > 0.9)
        #expect(dense.issues.isEmpty, "\(dense)")
    }

    /// `image` with a reflection on it: light of `strength` (0…1) added at
    /// `center` (shares of the page), falling off as a Gaussian `spread` (a
    /// share of the width) wide, washing out paper and ink alike.
    static func glared(_ image: CGImage, center: CGPoint = CGPoint(x: 0.6, y: 0.4), spread: Double = 0.05,
                       strength: Double = 0.6) -> CGImage {
        let picture = DocumentComparer.gray(image)!
        let width = picture.width, height = picture.height
        let x0 = Double(center.x) * Double(width), y0 = Double(center.y) * Double(height), sigma = spread * Double(width)
        var pixels = picture.pixels
        for y in 0..<height {
            for x in 0..<width {
                let r2 = (Double(x) - x0) * (Double(x) - x0) + (Double(y) - y0) * (Double(y) - y0)
                let added = strength * 255 * exp(-r2 / (2 * sigma * sigma))
                pixels[y * width + x] = UInt8(min(255, Double(pixels[y * width + x]) + added))
            }
        }
        return grey(pixels, width: width, height: height)
    }

    /// A reflection on a page of print, about 2% of the page blown out,
    /// is glare. Measured: 1.6%.
    @Test func aReflectionIsGlare() throws {
        let measured = try report(Self.glared(Self.page(width: 2000, height: 2600, paper: 0.85)))
        #expect(measured.issues == [.glare], "\(measured)")
        #expect(measured.glare > 2 * ScanQualityReport.glareAtLeast, "\(measured)")
    }

    /// A glint, about 0.1% of the page (measured), is not worth a word.
    @Test func aGlintIsNotGlare() throws {
        let measured = try report(Self.glared(Self.page(width: 2000, height: 2600, paper: 0.85), spread: 0.012))
        #expect(measured.issues.isEmpty, "\(measured)")
    }

    /// Paper exposed to white all over has nothing standing out: bright,
    /// not reflecting — with a reflection on it too, it cannot show.
    @Test func aPageExposedBrightAllOverIsNotGlare() throws {
        let bright = Self.page(width: 2000, height: 2600, paper: 1)
        #expect(try report(bright).glare == 0)
        #expect(try report(bright).issues.isEmpty)
        #expect(try report(Self.glared(bright)).glare == 0)
    }

    /// Hundreds of small white specks blow out more of the page than a
    /// reflection does, but no patch of them is a reflection: the largest
    /// measured 0.03%.
    @Test func scatteredWhiteSpecksAreNotGlare() throws {
        let context = try #require(CGContext(data: nil, width: 2000, height: 2600, bitsPerComponent: 8, bytesPerRow: 2000,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(Self.page(width: 2000, height: 2600, paper: 0.85), in: CGRect(x: 0, y: 0, width: 2000, height: 2600))
        context.setFillColor(gray: 1, alpha: 1)
        for y in stride(from: 60, to: 2600, by: 120) {
            for x in stride(from: 60, to: 2000, by: 120) { context.fillEllipse(in: CGRect(x: x - 20, y: y - 20, width: 40, height: 40)) }
        }
        let measured = try report(try #require(context.makeImage()))
        #expect(measured.glare < ScanQualityReport.glareAtLeast, "\(measured)")
        #expect(!measured.issues.contains(.glare))
    }

    /// White printed on tinted paper — a form's box, a panel on a card —
    /// blows out as much of the page as a reflection, but has no halo of
    /// light around it: a sharp edge, softened or not. Before the halo rule
    /// it was called glare. Measured halo: 0.01 to 0.02 (reflections 0.19
    /// and up).
    @Test(arguments: [140, 300])
    func whitePrintedOnTintedPaperIsNotGlare(size: Int) throws {
        let context = try #require(CGContext(data: nil, width: 2000, height: 2600, bitsPerComponent: 8, bytesPerRow: 2000,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(Self.page(width: 2000, height: 2600, paper: 0.85), in: CGRect(x: 0, y: 0, width: 2000, height: 2600))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 900, y: 1200, width: size * 2, height: size))
        let sharp = try #require(context.makeImage())
        for image in [sharp, Self.blurred(sharp, sigma: 2)] {
            let measured = try report(image)
            #expect(measured.glare == 0, "box \(size): \(measured)")
            #expect(!measured.issues.contains(.glare))
        }
    }

    /// The same reflection on the same page at half or twice the pixels
    /// covers the same share of it (measured: 1.58% both).
    @Test func glareReadsTheSameAtAnyResolution() throws {
        let small = try report(Self.glared(Self.page(width: 1500, height: 1950, paper: 0.85)))
        let large = try report(Self.glared(Self.page(width: 3000, height: 3900, paper: 0.85)))
        #expect(small.issues == [.glare] && large.issues == [.glare], "\(small) / \(large)")
        #expect(abs(small.glare - large.glare) < 0.25 * large.glare, "\(small.glare) vs \(large.glare)")
    }

    /// A reflection on dark paper — a flash in a dim room — is both
    /// (measured: 1.2%). A weaker one blew out too little of dark paper to
    /// count: there is further to go to white.
    @Test func aDarkPageCanHaveGlareToo() throws {
        let measured = try report(Self.glared(Self.page(width: 2000, height: 2600, paper: 0.22, ink: 0.03), spread: 0.08,
                                              strength: 1.2))
        #expect(measured.issues == [.tooDark, .glare], "\(measured)")
    }

    /// A black card with one line of white print, cropped to the card, is
    /// "too dark" by a page's measure: its own colour, not the light. So in
    /// Card mode its darkness is not said, and in Photo mode nothing is.
    @Test func aBlackCardIsNotCalledTooDarkAsACard() throws {
        let context = try #require(CGContext(data: nil, width: 856, height: 540, bitsPerComponent: 8, bytesPerRow: 856,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.08, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 856, height: 540))
        let font = CTFontCreateWithName("Helvetica" as CFString, 44, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.95, alpha: 1)] as CFDictionary
        context.textPosition = CGPoint(x: 60, y: 180)
        CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "4000 1234 5678 9010" as CFString, attributes)), context)
        let card = try report(try #require(context.makeImage()))
        #expect(card.issues.contains(.tooDark), "the measure itself: a black card's paper is dark")
        #expect(card.issues(in: .card).isEmpty, "\(card)")
        #expect(card.issues(in: .photo).isEmpty)
    }

    /// The far side three fifths of the near one in a 3000 × 4000 photo is
    /// steep; the whole frame is not; without the photo's size, no verdict.
    @Test func aPageFromASteepAngleSaysSo() throws {
        let page = Self.page(width: 1000, height: 1300)
        let steep = [CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2), CGPoint(x: 0.85, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        #expect(try report(page, corners: steep).issues == [.steepAngle])
        #expect(try report(page).issues.isEmpty)
        #expect(try report(page, corners: steep, photo: nil).issues.isEmpty)
    }

    /// The corners are shares of the photo as shown, so its size is read
    /// with its orientation applied: a photo stored on its side is shown
    /// upright, its width and height swapped.
    @Test func thePhotoSizeIsTheSizeAsShown() throws {
        func jpeg(orientation: Int) throws -> Data {
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, Self.page(width: 40, height: 30, print: false),
                                       [kCGImagePropertyOrientation: orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            return data as Data
        }
        #expect(ScanQualityAnalyzer.photoSize(of: try jpeg(orientation: 1)) == CGSize(width: 40, height: 30))
        #expect(ScanQualityAnalyzer.photoSize(of: try jpeg(orientation: 6)) == CGSize(width: 30, height: 40))
        #expect(ScanQualityAnalyzer.photoSize(of: Data("not a picture".utf8)) == nil)
    }
}

/// Corners for the tests, as shares of the photo from its top-left, in
/// order around the page.
enum ScannerCorners {
    static let whole = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
}

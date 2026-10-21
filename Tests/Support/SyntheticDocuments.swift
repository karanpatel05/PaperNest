import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Generates synthetic fixtures; no real user documents are used in tests,
/// samples or screenshots.
///
/// Every fixture carries an orientation marker: a solid square in the
/// top-left corner of its upright content (black in PDFs, red in images).
/// Rendering tests look for the marker to prove pages come out upright.
public enum SyntheticDocuments {
    public static let markerInset: CGFloat = 20
    public static let markerSize: CGFloat = 60

    /// A text PDF with one page per string, drawn with real text so it stays
    /// selectable and extractable.
    public static func textPDF(pages: [String], size: CGSize = CGSize(width: 612, height: 792)) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: "Synthetic"] as CFDictionary)!
        for text in pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: markerInset, y: size.height - markerInset - markerSize, width: markerSize, height: markerSize))
            drawText(text, in: ctx, at: CGPoint(x: 72, y: size.height - 140), size: 18)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// A PDF that opens only with `password`.
    public static func encryptedPDF(text: String, password: String) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = [kCGPDFContextUserPassword: password, kCGPDFContextOwnerPassword: password + "-owner"]
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, info as CFDictionary)!
        ctx.beginPDFPage(nil)
        drawText(text, in: ctx, at: CGPoint(x: 72, y: 600), size: 18)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    /// A text PDF whose pages carry a `/Rotate` entry.
    public static func rotatedPDF(degrees: Int, text: String = "Rotated page") -> Data {
        let base = textPDF(pages: [text])
        let document = PDFDocument(data: base)!
        document.page(at: 0)!.rotation = degrees
        return document.dataRepresentation()!
    }

    /// An image whose upright content is `width`×`height` pixels with a red
    /// marker top-left. `exifOrientation` 6 stores the pixels rotated a
    /// quarter turn counterclockwise, as a phone held upright does.
    public static func image(width: Int, height: Int, type: UTType, exifOrientation: Int = 1, dpi: Int? = nil,
                             transparentBackground: Bool = false) -> Data {
        let upright = drawUpright(width: width, height: height, transparent: transparentBackground)
        let stored: CGImage
        if exifOrientation == 6 {
            let ctx = bitmapContext(width: height, height: width, transparent: transparentBackground)
            ctx.translateBy(x: CGFloat(height), y: 0)
            ctx.rotate(by: .pi / 2)
            ctx.draw(upright, in: CGRect(x: 0, y: 0, width: width, height: height))
            stored = ctx.makeImage()!
        } else {
            stored = upright
        }
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyOrientation: exifOrientation]
        if let dpi {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(dest, stored, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private static func drawUpright(width: Int, height: Int, transparent: Bool) -> CGImage {
        let ctx = bitmapContext(width: width, height: height, transparent: transparent)
        if !transparent {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let marker = CGFloat(min(width, height)) / 5
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // Top-left in y-up bitmap coordinates.
        ctx.fill(CGRect(x: 0, y: CGFloat(height) - marker, width: marker, height: marker))
        // Dark ink stroke across the middle, used for transparency checks.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: CGFloat(height) / 2 - 2, width: CGFloat(width), height: 4))
        return ctx.makeImage()!
    }

    private static func bitmapContext(width: Int, height: Int, transparent: Bool) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    private static func drawText(_ text: String, in ctx: CGContext, at origin: CGPoint, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        var y = origin.y
        for line in text.components(separatedBy: "\n") {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: origin.x, y: y)
            CTLineDraw(ctLine, ctx)
            y -= size * 1.5
        }
    }
}

/// Reads pixels from rendered output for assertions.
public enum PixelProbe {
    public struct RGB: Equatable, CustomStringConvertible {
        public var r, g, b: UInt8
        public var description: String { "rgb(\(r),\(g),\(b))" }
        public var isWhite: Bool { r > 230 && g > 230 && b > 230 }
        public var isRed: Bool { r > 180 && g < 80 && b < 80 }
        public var isDark: Bool { r < 80 && g < 80 && b < 80 }
        public var isGray: Bool { abs(Int(r) - Int(g)) <= 2 && abs(Int(g) - Int(b)) <= 2 }
    }

    /// Pixel at a fractional position (0...1) measured from the top-left.
    public static func pixel(_ image: CGImage, x: Double, y: Double) -> RGB {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = min(width - 1, max(0, Int(Double(width) * x)))
        // Bitmap memory starts at the top row.
        let py = min(height - 1, max(0, Int(Double(height) * y)))
        let i = (py * width + px) * 4
        return RGB(r: buffer[i], g: buffer[i + 1], b: buffer[i + 2])
    }

    /// Distinct gray levels present, for checking black-and-white output.
    public static func grayLevels(_ image: CGImage) -> Set<UInt8> {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var levels = Set<UInt8>()
        for i in stride(from: 0, to: buffer.count, by: 4) { levels.insert(buffer[i]) }
        return levels
    }

    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Renders page `index` of a PDF to a bitmap, honoring `/Rotate`.
    public static func renderPDFPage(_ data: Data, index: Int, scale: CGFloat = 0.5) -> CGImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .cropBox).cgImageRepresentation
    }
}

#if canImport(AppKit)
import AppKit
extension NSImage {
    var cgImageRepresentation: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#else
import UIKit
extension UIImage {
    var cgImageRepresentation: CGImage? { cgImage }
}
#endif

extension SyntheticDocuments {
    /// A PDF that opens without a password but whose author forbids copying.
    public static func restrictedPDF() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = [kCGPDFContextOwnerPassword: "owner-only", kCGPDFContextAllowsCopying: false]
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, info as CFDictionary)!
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}

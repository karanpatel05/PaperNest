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

    /// White page carrying `lines` of black text, the first line near the
    /// top. Used to check text recognition against known words and places.
    public static func textImage(lines: [String], width: Int = 1000, height: Int = 1400,
                                 type: UTType = .png, fontSize: CGFloat = 48) -> Data {
        let ctx = bitmapContext(width: width, height: height, transparent: false)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // y-up bitmap: the first baseline sits a tenth from the top.
        drawText(lines.joined(separator: "\n"), in: ctx,
                 at: CGPoint(x: CGFloat(width) / 12, y: CGFloat(height) * 0.9), size: fontSize)
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
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

extension SyntheticDocuments {
    /// A PDF whose pages carry only raster content, the way a scan of paper
    /// arrives: there is no text layer to extract. Used to check that text
    /// indexing can tell "looked, found nothing" apart from "not looked at".
    /// `raster` is the bitmap the page is a photograph of. The default is small
    /// and nearly flat, which is enough to stand for "a PDF whose marks are an
    /// image". Pass a large, detailed one when the test is about *size* — a
    /// 400×560 near-flat PNG is already more compact than any re-encode of it,
    /// so it cannot show compression working.
    /// One field of a hand-built form.
    public struct FormFieldSpec: Sendable {
        /// `/FT` — `Tx` for text, `Btn` for a checkbox, `Ch` for a choice.
        public var type: String
        public var name: String
        public var value: String

        public init(type: String = "Tx", name: String, value: String = "") {
            self.type = type
            self.name = name
            self.value = value
        }
    }

    /// A PDF with a **real** document-level `/AcroForm`.
    ///
    /// Written as raw bytes with computed xref offsets because PDFKit cannot
    /// create a form: it keeps one it is given, but never makes one. Without
    /// this there is no honest way to test form filling at all — a widget
    /// annotation on its own is not a form, and PDFKit reports a `fieldName`
    /// for one either way, which misled this project once.
    public static func acroFormPDF(fields: [FormFieldSpec] = [FormFieldSpec(name: "customer")]) -> Data {
        let content = Data("BT /Helv 14 Tf 72 700 Td (Agreement) Tj ET\n".utf8)
        // Objects 1...5 are fixed; each field is an object after them.
        let fieldStart = 6
        let fieldRefs = fields.indices.map { "\(fieldStart + $0) 0 R" }.joined(separator: " ")
        var objects: [String] = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [\(fieldRefs)] /DA (/Helv 0 Tf 0 g) >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /Helv 5 0 R >> >> "
                + "/Annots [\(fieldRefs)] /Contents 4 0 R >>",
            "<< /Length \(content.count) >>\nstream\n" + String(decoding: content, as: UTF8.self) + "endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        ]
        for (index, field) in fields.enumerated() {
            let top = 630 - index * 40
            objects.append("<< /Type /Annot /Subtype /Widget /FT /\(field.type) /T (\(field.name)) "
                + "/V (\(field.value)) /Rect [72 \(top - 30) 300 \(top)] /P 3 0 R /F 4 /DA (/Helv 12 Tf 0 g) >>")
        }

        var out = Data("%PDF-1.7\n".utf8)
        out.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xrefAt = out.count
        out.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets {
            out.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        out.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefAt)\n%%EOF\n".utf8))
        return out
    }

    /// A PDF carrying the table of contents its author wrote.
    ///
    /// `entries` are `(title, pageIndex, children)`: a child becomes a nested
    /// outline entry under its parent, so depth can be checked rather than
    /// assumed. Verified to survive serialization — labels and page indices
    /// come back intact after a write and reopen.
    public static func outlinedPDF(pages: [String],
                                   entries: [(String, Int, [(String, Int)])]) -> Data {
        let document = PDFDocument(data: textPDF(pages: pages))!
        let root = PDFOutline()
        for (index, entry) in entries.enumerated() {
            let node = PDFOutline()
            node.label = entry.0
            if let page = document.page(at: entry.1) {
                node.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
            }
            root.insertChild(node, at: index)
            for (childIndex, child) in entry.2.enumerated() {
                let leaf = PDFOutline()
                leaf.label = child.0
                if let page = document.page(at: child.1) {
                    leaf.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
                }
                node.insertChild(leaf, at: childIndex)
            }
        }
        document.outlineRoot = root
        return document.dataRepresentation()!
    }

    /// A 16×16 lossless WebP: the top-left quadrant red, the rest white.
    ///
    /// A literal rather than drawn, because it cannot be drawn: ImageIO lists
    /// no WebP type among the ones it can *write*, so there is no way to
    /// encode one on this platform. The colours are the point — they let a
    /// test prove the file is really decoded rather than merely accepted.
    public static func webPImage() -> Data {
        Data(base64Encoded: "UklGRioAAABXRUJQVlA4TB4AAAAvD8ADAA/wiv93/7/if/7jAWLBJH/pzilE9H8CThw=")!
    }

    public static func scannedPDF(pages: Int = 1, size: CGSize = CGSize(width: 612, height: 792),
                                  raster: Data? = nil) -> Data {
        let bitmap = PixelProbe.decode(raster ?? image(width: 400, height: 560, type: .png))!
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: "Synthetic scan"] as CFDictionary)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: markerInset, y: size.height - markerInset - markerSize, width: markerSize, height: markerSize))
            ctx.draw(bitmap, in: CGRect(x: 72, y: 100, width: size.width - 144, height: size.height - 240))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}

extension SyntheticDocuments {
    /// A PDF carrying the things a redraw silently loses: a link and a text
    /// form field. Used to check that an unedited page is copied rather than
    /// reproduced as marks on a blank page.
    public static func annotatedPDF(linkURL: URL = URL(string: "https://example.com/invoice")!,
                                    fieldName: String = "customer") -> Data {
        let document = PDFDocument(data: textPDF(pages: ["Signed agreement"]))!
        let page = document.page(at: 0)!

        let link = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 140, height: 22),
                                 forType: .link, withProperties: nil)
        link.url = linkURL
        page.addAnnotation(link)

        let field = PDFAnnotation(bounds: CGRect(x: 72, y: 540, width: 160, height: 24),
                                  forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = fieldName
        page.addAnnotation(field)

        return document.dataRepresentation()!
    }
}

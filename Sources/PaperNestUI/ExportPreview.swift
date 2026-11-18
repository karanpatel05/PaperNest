import CoreGraphics
import Foundation
import ImageIO
import PaperNestExport
import PaperNestImport

/// What the export sheet shows of the file it will write: the first chosen
/// page, **read back from a real one-page export** with the sheet's options
/// (`Exporter.sample`). Not a second drawing of the page: the paper size, the
/// quality, a watermark, the PaperNest mark, a text format's words are what
/// the writer wrote.
enum ExportPreview {
    /// The page as a picture: a PDF's first page drawn, or the image itself.
    case picture(CGImage)
    /// The start of a text or editable Word file's words; empty when the
    /// page has none.
    case words(String)

    /// Characters of a text preview; the rest is in the file.
    static let wordLimit = 600

    /// Reads the one file of a one-page export. Nil when it cannot be read.
    static func read(_ output: ExportOutput, maxPixelSize: Int = 720) -> ExportPreview? {
        guard let file = output.files.first else { return nil }
        switch file.pathExtension.lowercased() {
        case "pdf": return pdfPage(file, maxPixelSize: maxPixelSize).map(ExportPreview.picture)
        case "jpg", "jpeg", "png", "heic": return (try? Data(contentsOf: file)).flatMap { picture($0, maxPixelSize: maxPixelSize) }
            .map(ExportPreview.picture)
        case "txt": return (try? String(contentsOf: file, encoding: .utf8)).map { .words(String($0.prefix(wordLimit))) }
        case "docx": return wordFile(file, maxPixelSize: maxPixelSize)
        default: return nil
        }
    }

    /// The first page of a PDF, fitted to `maxPixelSize` on white paper.
    private static func pdfPage(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let size = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(maxPixelSize) / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(target)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// An image file, turned upright and no larger than `maxPixelSize`.
    private static func picture(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    /// A Word file: its page picture when it holds one (page images), else
    /// the words of its paragraphs (editable text), one line each.
    private static func wordFile(_ url: URL, maxPixelSize: Int) -> ExportPreview? {
        guard let data = try? Data(contentsOf: url), let zip = try? ZipReader(data: data) else { return nil }
        if let media = zip.entries.first(where: { $0.path.hasPrefix("word/media/") && !$0.isDirectory }),
           let bytes = try? zip.contents(of: media), let image = picture(bytes, maxPixelSize: maxPixelSize) {
            return .picture(image)
        }
        guard let document = zip.entries.first(where: { $0.path == "word/document.xml" }),
              let xml = try? zip.contents(of: document) else { return nil }
        return .words(String(WordParagraphs.text(of: xml).prefix(wordLimit)))
    }
}

/// The words of a Word document's body: each `w:p` a line, each `w:t` its text.
enum WordParagraphs {
    static func text(of xml: Data) -> String {
        let reader = Reader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.parse()
        return reader.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var lines: [String] = []
        private var line = ""
        private var inText = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "w:t" { inText = true }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:t": inText = false
            case "w:p":
                if !line.isEmpty { lines.append(line) }
                line = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { line += string }
        }
    }
}

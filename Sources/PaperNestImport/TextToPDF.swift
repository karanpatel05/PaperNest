import CoreGraphics
import CoreText
import Foundation
import PaperNestCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Turns a plain text file into pages, so it can be annotated, cropped,
/// reordered and exported like any other document instead of sitting in the
/// library as an opaque file.
public enum TextToPDF {
    /// A4 in points, the paper the notebook templates already use.
    public static let a4 = CGSize(width: 595, height: 842)

    /// Lays `text` out over as many pages as it needs, and returns PDF data —
    /// or nil when there is nothing to lay out.
    ///
    /// CoreText does the line breaking and, more importantly, reports how much
    /// of the string each page actually consumed. That is what makes the page
    /// breaks correct: estimating by character count falls apart the moment a
    /// line wraps, and whatever runs past the bottom of the frame is simply
    /// lost. The result looks like a clean conversion and is not.
    ///
    /// The pages carry real text rather than a picture of it, so a converted
    /// document is searchable and its words can be annotated.
    public static func render(_ text: String, pageSize: CGSize = a4, margin: CGFloat = 54) -> Data? {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 11, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        return render(NSAttributedString(string: text, attributes: attributes), pageSize: pageSize, margin: margin)
    }

    /// The same, for text that carries its own fonts and styles (RTF).
    public static func render(_ attributed: NSAttributedString, pageSize: CGSize = a4, margin: CGFloat = 54) -> Data? {
        guard !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = CGRect(x: margin, y: margin,
                              width: pageSize.width - margin * 2,
                              height: pageSize.height - margin * 2)
        guard textRect.width > 0, textRect.height > 0 else { return nil }
        let path = CGPath(rect: textRect, transform: nil)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        var start = 0
        while start < attributed.length {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let consumed = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            // Nothing fitted: the frame is too small for even one line. Stop
            // rather than emitting blank pages for ever.
            guard consumed.length > 0 else { break }
            start += consumed.length
        }
        ctx.closePDF()
        return data as Data
    }
}

/// Files that are text, turned into pages on import so they open in the
/// editor to be marked up (owner, 2026-11-15: "all files should be editable").
///
/// Chosen by the file's type, never by whether its bytes happen to decode: any
/// binary decodes as Latin-1, and that would turn a spreadsheet into pages of
/// noise. HTML is left out because reading it into styled text needs WebKit on
/// the main thread, and imports run off it. On the Mac, Word too.
enum TextDocumentConverter {
    /// PDF data for `data`, or nil when the file is not text this can lay out,
    /// so it is kept as the file it is.
    static func pdf(from data: Data, filename: String) -> Data? {
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension) else { return nil }
        if type.conforms(to: .rtf) {
            guard let styled = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                       documentAttributes: nil) else { return nil }
            return TextToPDF.render(styled)
        }
        #if os(macOS)
        // The Mac reads Word itself. iPhone and iPad cannot here; the app lays
        // Word out with WebKit instead (`OfficeDocumentRenderer`).
        if let word = wordDocumentType(for: type) {
            guard let styled = try? NSAttributedString(data: data, options: [.documentType: word],
                                                       documentAttributes: nil) else { return nil }
            return TextToPDF.render(styled)
        }
        #endif
        guard type.conforms(to: .text), !type.conforms(to: .html), let text = decoded(data) else { return nil }
        return TextToPDF.render(text)
    }

    #if os(macOS)
    static func wordDocumentType(for type: UTType) -> NSAttributedString.DocumentType? {
        if let docx = UTType("org.openxmlformats.wordprocessingml.document"), type.conforms(to: docx) { return .officeOpenXML }
        if let doc = UTType("com.microsoft.word.doc"), type.conforms(to: doc) { return .docFormat }
        return nil
    }
    #endif

    /// UTF-16 when it says so with a byte-order mark, otherwise UTF-8. A NUL
    /// byte in what claims to be UTF-8 text means it is not text.
    static func decoded(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension DocumentImporter {
    /// Converts plain text into a page-based document.
    ///
    /// `importItem` now does this by itself for a text file; this call is for
    /// text that is not a file, such as words already in hand.
    ///
    /// The rendered PDF goes through the ordinary import path, so durability,
    /// content-addressed storage and name de-duplication are unchanged. Text
    /// with nothing in it is refused rather than producing a blank document.
    @discardableResult
    public func importTextAsDocument(_ text: String, named name: String,
                                     folderID: FolderID? = nil) async throws -> PaperNestCore.LibraryItem {
        guard let pdf = TextToPDF.render(text) else { throw ImportError.empty(filename: name) }
        return try await importItem(.data(pdf, name: name), folderID: folderID)
    }
}

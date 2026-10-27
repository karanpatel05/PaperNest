import CoreGraphics
import CoreText
import Foundation
import PaperNestCore

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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 11, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
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

extension DocumentImporter {
    /// Converts plain text into a page-based document.
    ///
    /// Deliberately a separate call rather than something `importItem` does on
    /// its own for a `.txt`: keeping a file as the bytes it arrived with is
    /// the right default, and existing behaviour depends on it. This is the
    /// conversion someone chooses when they want to annotate or crop the text
    /// instead of just keeping it.
    ///
    /// The rendered PDF goes through the ordinary import path, so durability,
    /// content-addressed storage and name de-duplication are unchanged. Text
    /// with nothing in it is refused rather than producing a blank document.
    @discardableResult
    public func importTextAsDocument(_ text: String, named name: String,
                                     folderID: FolderID? = nil) async throws -> LibraryItem {
        guard let pdf = TextToPDF.render(text) else { throw ImportError.empty(filename: name) }
        return try await importItem(.data(pdf, name: name), folderID: folderID)
    }
}

import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore
import PaperNestRender
#if canImport(AppKit)
import AppKit
private typealias NoteColor = NSColor
#elseif canImport(UIKit)
import UIKit
private typealias NoteColor = UIColor
#endif

/// Page comments written into an exported PDF as notes: standard PDF text
/// annotations, the sticky notes Preview and Acrobat show beside a page and
/// open with a click.
///
/// A comment is private in PaperNest; it reaches a file only when the export
/// asks (`ExportOptions.includesComments`). The notes are added to the file
/// the writer already finished — whichever path it took, the original handed
/// back, a rebuild, pages copied in — so nothing is drawn twice and every
/// page keeps what it already carries. The file is then written again under
/// the same password and author's limits it had, the way pass-through does.
enum PDFComments {
    /// A note's icon, in points.
    static let noteSide: CGFloat = 20
    /// Room between the page's edge and the first note, and between notes.
    static let gap: CGFloat = 6

    /// Where `count` notes go on a page laid on paper as `layout`, in the
    /// paper's own space (y down): a column down the page's top-left corner,
    /// as it sits on the sheet, starting a new column when one is full.
    static func noteRects(count: Int, layout: PaperLayout) -> [CGRect] {
        let content = layout.contentRect
        let side = max(1, min(noteSide, (content.width - gap) / 2, (content.height - gap) / 2))
        let step = side + gap
        let perColumn = max(1, Int((content.height - gap) / step))
        return (0..<count).map { index in
            let column = CGFloat(index / perColumn), row = CGFloat(index % perColumn)
            let x = min(content.minX + gap + column * step, content.maxX - side)
            return CGRect(x: x, y: content.minY + gap + row * step, width: side, height: side)
        }
    }

    /// Adds `comments` — by page index, each with the layout that page was
    /// written with — to the PDF at `url`, and writes it again in place.
    static func attach(_ comments: [Int: (texts: [String], layout: PaperLayout)], to url: URL,
                       password: String?, protection: AuthorProtection?) throws {
        guard !comments.isEmpty else { return }
        guard let document = PDFDocument(url: url) else { throw ExportError.writeFailed }
        // Encrypted by the context, and locked: annotations added to a locked
        // document are not written.
        if let password {
            guard document.unlock(withPassword: password), !document.isLocked else { throw ExportError.writeFailed }
        }
        try PDFKitAnnotationLock.run {
            for (index, entry) in comments.sorted(by: { $0.key < $1.key }) {
                guard let page = document.page(at: index) else { throw ExportError.writeFailed }
                // Paper space is the upright page as written: a drawn page's
                // box is the sheet, a copied page's is its own, perhaps
                // offset and turned by `/Rotate`. One mapping covers both.
                let paperToPDF = PageGeometry.pdfToSource(box: page.bounds(for: .cropBox),
                                                          rotationDegrees: page.rotation).inverted()
                for (text, rect) in zip(entry.texts, noteRects(count: entry.texts.count, layout: entry.layout)) {
                    let note = PDFAnnotation(bounds: rect.applying(paperToPDF), forType: .text, withProperties: nil)
                    note.contents = text
                    note.iconType = .comment
                    note.color = NoteColor(red: 1, green: 0.84, blue: 0.2, alpha: 1)
                    page.addAnnotation(note)
                }
            }
        }
        // Beside the file, not over it: the document has `url` mapped.
        let staged = url.deletingLastPathComponent().appendingPathComponent("comments-\(UUID().uuidString).pdf")
        let wrote = if let protection {
            document.write(to: staged, withOptions: protection.writeOptions(userPassword: password))
        } else if let password {
            document.write(to: staged, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
        } else {
            document.write(to: staged)
        }
        guard wrote else {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
        withExtendedLifetime(document) {}
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
    }
}

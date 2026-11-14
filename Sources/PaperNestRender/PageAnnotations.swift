import CoreGraphics
import Foundation
import PDFKit

/// PDFKit's annotation work, one caller at a time, across the whole app.
///
/// Building a form field's annotation makes PDFKit resolve the font its `/DA`
/// names — `/Helv` in most forms Acrobat writes, which is not a real
/// PostScript name — and CoreText looks that up over **synchronous XPC**.
/// Several of those at once on Swift concurrency's cooperative threads were
/// measured to deadlock (eight concurrent form fills never returned; see
/// `PDFForm`). Page pictures are drawn concurrently, and the form workspace
/// and the link reader read annotations as well, so every one of them takes
/// this one lock rather than a lock of its own: two locks would still let two
/// of them into PDFKit at once.
///
/// Recursive, so code already holding it cannot deadlock on itself. Held only
/// around synchronous work, never across an `await`.
public enum PDFKitAnnotationLock {
    public static let shared = NSRecursiveLock()

    public static func run<T>(_ body: () throws -> T) rethrows -> T {
        shared.lock()
        defer { shared.unlock() }
        return try body()
    }
}

/// What a PDF page shows through its **annotations** rather than its content:
/// the answer typed into a form field, a checkbox's tick, a box, stamp or
/// highlight another app drew.
///
/// Core Graphics' `drawPDFPage` draws page content only. Until this existed
/// every one of these was missing from the page PaperNest showed, from its
/// thumbnail, and from any page it had to redraw for an export or a print —
/// so a filled-in form opened with empty boxes, and drawing one line on it
/// lost its answers from the export.
///
/// PDFKit draws them, as it does for Preview: from the appearance the file
/// carries, or one PDFKit makes for a field that has a value and no
/// appearance. A link is not drawn (it is not a mark, and the reader finds
/// links itself), nor is a pop-up, nor anything its author hid.
///
/// `@unchecked Sendable` for the same reason as `PageRenderer.PreparedSource`:
/// it is made for one preparation, and every touch of the PDFKit objects
/// inside happens under `PDFKitAnnotationLock`.
public final class PageAnnotations: @unchecked Sendable {
    /// Which of the author's flags decide what is drawn.
    public enum Use: Sendable {
        /// On screen: everything the author lets a reader see.
        case screen
        /// On paper — a print, or an exported page PaperNest had to redraw —
        /// only what the author also marked for printing, as Acrobat prints.
        case paper
    }

    /// Kept because a `PDFPage` does not keep its document alive.
    private let document: PDFDocument
    private let page: PDFPage
    private let annotations: [PDFAnnotation]

    private init(document: PDFDocument, page: PDFPage, annotations: [PDFAnnotation]) {
        self.document = document
        self.page = page
        self.annotations = annotations
    }

    /// The marks page `pageNumber` (1-based, as Core Graphics counts) of the
    /// PDF in `data` carries, or nil when it carries none to draw.
    ///
    /// `document` is the same file opened by Core Graphics. It answers the
    /// first question — does the page list any annotation that could be a
    /// mark at all — without PDFKit, so the ordinary page with none never
    /// opens the file a second time or waits on the lock.
    public static func load(from data: Data, document: CGPDFDocument, pageNumber: Int,
                            use: Use) -> PageAnnotations? {
        guard let cgPage = document.page(at: pageNumber), listsMarks(cgPage) else { return nil }
        return PDFKitAnnotationLock.run {
            guard let kitDocument = PDFDocument(data: data),
                  let page = kitDocument.page(at: pageNumber - 1) else { return nil }
            let drawn = page.annotations.filter { isDrawn($0, for: use) }
            guard !drawn.isEmpty else { return nil }
            return PageAnnotations(document: kitDocument, page: page, annotations: drawn)
        }
    }

    /// Whether `page` lists an annotation other than a link or a pop-up.
    /// Read from the page dictionary, which costs nothing like building the
    /// annotations would.
    static func listsMarks(_ page: CGPDFPage) -> Bool {
        guard let dictionary = page.dictionary else { return false }
        var list: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Annots", &list), let list else { return false }
        for index in 0..<CGPDFArrayGetCount(list) {
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(list, index, &annotation), let annotation else { continue }
            var subtype: UnsafePointer<CChar>?
            // No subtype is a broken annotation; let PDFKit decide what it is.
            guard CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype else { return true }
            let name = String(cString: subtype)
            if name != "Link", name != "Popup" { return true }
        }
        return false
    }

    static func isDrawn(_ annotation: PDFAnnotation, for use: Use) -> Bool {
        guard let type = annotation.type, type != "Link", type != "Popup",
              annotation.shouldDisplay else { return false }
        switch use {
        case .screen: return true
        case .paper: return annotation.shouldPrint
        }
    }

    /// Draws the marks into `ctx`, whose user space must be the page's own PDF
    /// user space — the space `drawPDFPage` draws in.
    ///
    /// PDFKit draws an annotation the way it draws the page for display:
    /// moved to the box's origin **and turned by the page's `/Rotate`**. The
    /// caller has already placed the page, turn included, so PDFKit's own
    /// transform is undone first, leaving the mark in the page's user space.
    /// Both halves were measured: with the crop box, marks on a page whose crop
    /// box starts at (50, 40) landed 50 points left and 40 down; on a page
    /// turned 180° they came out turned twice, back where an unturned page has
    /// them.
    public func draw(in ctx: CGContext) {
        PDFKitAnnotationLock.run {
            let undo = page.transform(for: .mediaBox).inverted()
            for annotation in annotations {
                ctx.saveGState()
                ctx.concatenate(undo)
                annotation.draw(with: .mediaBox, in: ctx)
                ctx.restoreGState()
            }
        }
    }
}

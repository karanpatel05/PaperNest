import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore

extension Exporter {
    /// Whether this page can be copied from its source PDF instead of drawn.
    ///
    /// Drawing a page reproduces its marks and nothing else, so links, form
    /// fields and annotations are lost. For a page nobody has changed that is
    /// simply the wrong operation — the original page is exactly what the
    /// export should contain.
    ///
    /// Every condition has to hold, and each one is a way the drawn page would
    /// differ from the source:
    ///
    /// - It came from a PDF. There is no source page to copy otherwise.
    /// - Its transform is `identity`. A crop, rotation, filter or brightness
    ///   change is the user's edit, and copying the original would silently
    ///   export the page without it.
    /// - The paper is `.original`. Letter or A4 re-lays the page onto a sheet
    ///   of a different size, which is a new page.
    /// - It carries no ink. Ink is drawn by the exporter and lives nowhere in
    ///   the source file, so a copy would lose it.
    /// - No searchable-text layer is being written for it. That layer is drawn
    ///   too, and a copy would drop what was asked for.
    ///
    /// A compression preset is deliberately *not* among these, because for a
    /// page with text of its own copying costs nothing: vector content is
    /// drawn as vector, so every preset returns the same bytes, and the copy
    /// keeps the links and fields a drawing would lose. `writePDF` handles the
    /// other case ahead of this predicate: a page with **no** text, under a
    /// preset, is a scan, and it is re-encoded instead of copied whenever the
    /// re-encode actually comes out smaller.
    static func isUntouched(_ page: Page, options: ExportOptions,
                            hasInk: Bool, hasTextLayer: Bool) -> Bool {
        guard case .pdfPage = page.content else { return false }
        guard page.transform == .identity else { return false }
        guard options.paperSize == .original else { return false }
        guard !hasInk, !hasTextLayer else { return false }
        return true
    }

    /// What a source page costs as it stands, measured the way it will be
    /// written: alone in a document of its own.
    ///
    /// This is the budget a re-encode has to beat. It is measured per page
    /// rather than as a share of the source file, because a document of one
    /// photograph and nine blank pages has no meaningful average: the blank
    /// pages would each be allowed to grow and the photograph would be refused.
    static func byteCount(of page: PDFPage) -> Int? {
        guard let copy = page.copy() as? PDFPage else { return nil }
        let document = PDFDocument()
        document.insert(copy, at: 0)
        return document.dataRepresentation()?.count
    }

    /// Whether this source page has text of its own, rather than being a
    /// photograph of a page.
    ///
    /// This is the signal that decides whether compression may rasterize a PDF
    /// page. **Any** text at all counts as text, so a scan carrying a stamped
    /// page number is left alone and does not compress. That is a miss in the
    /// safe direction: guessing wrong the other way turns a page of real text
    /// into a blurry picture of itself and loses every word for a reader, a
    /// search and an export.
    ///
    /// It also bounds how often compression can help. Most scanner apps —
    /// Notes, Adobe Scan, ScanSnap — embed an invisible OCR layer, and that
    /// counts as text here, so those files will not compress either. Only
    /// image-only scans do.
    static func carriesText(_ document: PDFDocument, at index: Int) -> Bool {
        guard let page = document.page(at: index), let text = page.string else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Puts each copied source page into the slot its placeholder is holding,
    /// keeping position and order.
    ///
    /// The result is assembled into a *fresh* document rather than edited in
    /// place, and that is load-bearing. A form field's name lives in the
    /// document-level AcroForm; the file `CGContext` wrote has no AcroForm at
    /// all, and inserting a widget into a document opened from it leaves the
    /// field unnamed, so PDFKit invents one (`text5`, `text10`, a different
    /// name each run). Built fresh, the same copy keeps the name it came with.
    /// Traced at every stage: stored asset `customer`, exported `text5` when
    /// assembled in place, `customer` when assembled fresh.
    ///
    /// Callers hand over pages they have already read successfully, so a
    /// missing slot here means the written file is not what this just drew.
    /// That throws rather than shipping the blank placeholder, which would be
    /// a page of content quietly replaced by nothing.
    static func replaceWithSourcePages(_ sourcePages: [Int: PDFPage], in url: URL,
                                       password: String? = nil) throws {
        guard let drawn = PDFDocument(url: url) else { throw ExportError.writeFailed }
        // This is the file the context just wrote, so when a password was used
        // it is encrypted and locked. Every page that did not pass through is
        // copied out of it below, and a locked document yields blank pages —
        // and loses the title with them.
        if let password {
            guard drawn.unlock(withPassword: password), !drawn.isLocked else {
                throw ExportError.writeFailed
            }
        }
        let output = PDFDocument()
        // Title and creator live here, and a fresh document starts without them.
        output.documentAttributes = drawn.documentAttributes

        for index in 0..<drawn.pageCount {
            if let replacement = sourcePages[index] {
                output.insert(replacement, at: output.pageCount)
                continue
            }
            guard let drawnPage = drawn.page(at: index)?.copy() as? PDFPage else {
                throw ExportError.writeFailed
            }
            output.insert(drawnPage, at: output.pageCount)
        }
        guard output.pageCount == drawn.pageCount else { throw ExportError.writeFailed }

        // Written beside the file rather than over it: PDFDocument has this
        // url memory-mapped, and writing back to it while that mapping is
        // live fails. The finished file then replaces the placeholder one.
        let staged = url.deletingLastPathComponent()
            .appendingPathComponent("passthrough-\(UUID().uuidString).pdf")
        // The password has to be re-applied here. This write replaces the file
        // the context encrypted, so without it the export arrives unprotected
        // while the caller believes it is protected.
        let wrote = if let password {
            output.write(to: staged, withOptions: [.userPasswordOption: password,
                                                   .ownerPasswordOption: password])
        } else {
            output.write(to: staged)
        }
        guard wrote else {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
        withExtendedLifetime(drawn) {}
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
    }
}

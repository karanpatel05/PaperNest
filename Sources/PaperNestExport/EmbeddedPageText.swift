import Foundation
import PDFKit
import PaperNestCore

extension Exporter {
    /// Opens each distinct source PDF among `pages` once, so a hundred-page
    /// document reads its file once rather than a hundred times.
    func sourceDocuments(for pages: [Page]) async throws -> [AssetID: PDFDocument] {
        var documents: [AssetID: PDFDocument] = [:]
        for page in pages {
            guard case .pdfPage(let assetID, _) = page.content, documents[assetID] == nil else { continue }
            if let data = try await renderer.sourcePDFData(for: page) {
                documents[assetID] = PDFDocument(data: data)
            }
        }
        return documents
    }

    /// The text a page's own PDF carries, line by line.
    ///
    /// Deliberately not `LibraryStore.embeddedText`, which a text export used
    /// to read. That copy is the **search index**: normalized for matching, so
    /// it comes back as one run-on paragraph and loses exactly the structure a
    /// text or Word export exists to carry. It is also written by a background
    /// pass, so a PDF exported soon after import had no text at all and the
    /// export was refused as `noTextToExport` — for a document whose every
    /// word was sitting in the file.
    ///
    /// Reading the page's own file has neither problem, and the text is
    /// current by construction: `page.content` names the asset the page shows
    /// now, so a rescanned page cannot export words from the paper it replaced.
    ///
    /// The whole page's text is returned, including anything outside a crop.
    /// A crop is a display transform, not a redaction; that was true of the
    /// indexed copy too and is unchanged here.
    static func textLines(of page: Page, in documents: [AssetID: PDFDocument]) -> [String] {
        guard case .pdfPage(let assetID, let index) = page.content,
              let text = documents[assetID]?.page(at: index)?.string else { return [] }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

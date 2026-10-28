import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore

/// One line of a document's table of contents, already resolved to a page the
/// document actually has.
public struct DocumentOutlineEntry: Sendable, Hashable {
    /// The title its author wrote.
    public let title: String
    /// The page in *this* document it leads to — not an index into the file it
    /// came from.
    public let pageID: PageID
    /// Nesting as authored: 0 for a top-level entry, 1 for its child.
    public let depth: Int

    public init(title: String, pageID: PageID, depth: Int) {
        self.title = title
        self.pageID = pageID
        self.depth = depth
    }
}

extension PageRenderer {
    /// The table of contents a document's PDFs carry, resolved against the
    /// pages the document shows now.
    ///
    /// A PDF's outline points at pages of **that file**, and a PaperNest
    /// document is not that file: its pages may have been reordered, cropped,
    /// deleted, or drawn from several PDFs at once. So every entry is resolved
    /// through the current pages by asset and source index, never by trusting
    /// the index, and an entry whose page is no longer in the document is
    /// dropped — an outline that leads somewhere the document does not have is
    /// worse than no outline.
    ///
    /// Entries keep the order and nesting their author wrote, because that is
    /// what a table of contents is. If the pages were reordered, the outline
    /// will not ascend through the document; that is a true description of the
    /// file rather than something to quietly re-sort. For the same reason a
    /// child whose parent entry was dropped keeps its own depth.
    ///
    /// Image and template pages contribute nothing, and a PDF with no outline
    /// contributes nothing: both are ordinary answers, not failures.
    ///
    /// Nothing is stored or cached. The outline is read from the asset each
    /// page points at, so it cannot describe paper the page no longer shows.
    public func outline(for pages: [Page]) async throws -> [DocumentOutlineEntry] {
        // Where each source page ended up in this document. The first page
        // wins if the same source page was duplicated.
        var pageFor: [AssetID: [Int: PageID]] = [:]
        var sourceOrder: [AssetID] = []
        var representative: [AssetID: Page] = [:]
        for page in pages {
            guard case .pdfPage(let assetID, let index) = page.content else { continue }
            if representative[assetID] == nil {
                sourceOrder.append(assetID)
                representative[assetID] = page
            }
            if pageFor[assetID]?[index] == nil {
                pageFor[assetID, default: [:]][index] = page.id
            }
        }

        var entries: [DocumentOutlineEntry] = []
        for assetID in sourceOrder {
            guard let page = representative[assetID],
                  let data = try await sourcePDFData(for: page),
                  let document = PDFDocument(data: data),
                  let root = document.outlineRoot else { continue }
            Self.collect(root, in: document, landing: pageFor[assetID] ?? [:],
                         depth: 0, into: &entries)
        }
        return entries
    }

    private static func collect(_ node: PDFOutline, in document: PDFDocument,
                                landing: [Int: PageID], depth: Int,
                                into entries: inout [DocumentOutlineEntry]) {
        for index in 0..<node.numberOfChildren {
            guard let child = node.child(at: index) else { continue }
            if let title = child.label, !title.isEmpty,
               let destination = child.destination?.page,
               let pageID = landing[document.index(for: destination)] {
                entries.append(DocumentOutlineEntry(title: title, pageID: pageID, depth: depth))
            }
            collect(child, in: document, landing: landing, depth: depth + 1, into: &entries)
        }
    }
}

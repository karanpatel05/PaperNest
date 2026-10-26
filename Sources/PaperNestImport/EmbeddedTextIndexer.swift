import Foundation
import PaperNestCore
import PaperNestStore

/// Reads the text out of PDF pages nobody has looked at yet, so a library
/// that predates this feature becomes searchable by its contents too.
///
/// An actor, so two callers — launch, and a later library change — cannot read
/// the same pages at the same time: whichever runs second finds the work
/// already recorded and has nothing to do.
public actor EmbeddedTextIndexer {
    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// Records the text for PDF pages that have not been read yet, a batch at
    /// a time, and returns how many pages it recorded.
    ///
    /// A page whose original is not on this device is left unrecorded so a
    /// later pass can retry it. When a whole batch is unrecordable there is no
    /// progress left to make, and this returns rather than asking again.
    @discardableResult
    public func indexMissing(batchSize: Int = 50) async throws -> Int {
        var recorded = 0
        while true {
            try Task.checkCancellation()
            let pages = try await store.pagesMissingEmbeddedText(limit: batchSize)
            guard !pages.isEmpty else { return recorded }

            var progressed = false
            // Grouped by original, so a long PDF is read and parsed once for
            // all of its pages instead of once per page.
            for (assetID, group) in Dictionary(grouping: pages, by: \.pdfAssetID) {
                try Task.checkCancellation()
                guard let assetID, let record = try? await store.assetRecord(assetID),
                      record.availability == .local else { continue }
                // Read the original off disk rather than loading its bytes:
                // the record's own kind names the file, as the preview path
                // does, and PDFKit memory-maps what it opens.
                let url = store.assets.url(for: assetID, kind: record.kind)
                // Nil means the original could not be opened at all, which
                // is not the same as carrying no text: leave those pages
                // unrecorded so a later pass can try again.
                guard let found = PDFTextExtractor.text(at: url, pageIndexes: group.compactMap(\.pdfPageIndex))
                else { continue }
                for page in group {
                    try Task.checkCancellation()
                    guard let index = page.pdfPageIndex else { continue }
                    if try await store.indexEmbeddedText(found[index], for: page.id, expecting: page.content) {
                        recorded += 1
                        progressed = true
                    }
                }
            }
            guard progressed else { return recorded }
        }
    }
}

private extension Page {
    var pdfAssetID: AssetID? {
        if case .pdfPage(let assetID, _) = content { return assetID }
        return nil
    }

    var pdfPageIndex: Int? {
        if case .pdfPage(_, let index) = content { return index }
        return nil
    }
}

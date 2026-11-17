import Foundation
import PaperNestCore

extension LibraryStore {
    /// Other documents in the library identical to `itemID`: the same kind,
    /// the same pages in the same order (the same originals, crops and
    /// rotations), and the same marks on each. Private comments are not
    /// compared. Files, and documents in Recently Deleted, are left out.
    /// Near-copies — another scan of the same paper — are not found.
    public func identicalDocuments(to itemID: ItemID) throws -> [LibraryItem] {
        guard let item = try item(itemID), !item.isDeleted, item.kind != .file else { return [] }
        let mine = try pageSignatures(of: itemID)
        guard !mine.isEmpty else { return [] }
        return try items(in: .all).filter {
            $0.item.id != itemID && $0.item.kind == item.kind && $0.pageCount == mine.count
        }.compactMap { summary in
            try pageSignatures(of: summary.item.id) == mine ? summary.item : nil
        }
    }

    private struct PageSignature: Equatable {
        var content: PageContent
        var transform: PageTransform
        var marks: [PageObject.Payload]
    }

    private func pageSignatures(of itemID: ItemID) throws -> [PageSignature] {
        try pages(of: itemID).map { page in
            PageSignature(content: page.content, transform: page.transform, marks: try objects(on: page.id).compactMap {
                if case .comment = $0.payload { return nil }
                return $0.payload
            })
        }
    }
}

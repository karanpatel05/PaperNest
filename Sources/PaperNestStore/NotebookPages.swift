import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// Opaque, in-session undo token. The complete stored row and related data
    /// protect against edits that do not increment the page revision (e.g. OCR).
    public struct NotebookPageChange: Sendable {
        public let page: Page
        public let isDeleted: Bool
        fileprivate let row: [String?]
        fileprivate let objects: [PageObject]
        fileprivate let recognition: PageRecognition?
        fileprivate let surroundingOrder: [String]
    }

    public func addNotebookPage(_ template: PageTemplate, to itemID: ItemID, after anchor: PageID?) throws -> NotebookPageChange {
        try db.transaction {
            try requireActiveNotebook(itemID)
            let inserted = try insertPages([
                .init(sourceSize: CGSize(width: 595.28, height: 841.89), content: .template(template))
            ], into: itemID, after: anchor, assets: [])
            return try notebookPageChange(inserted[0], deleted: false)
        }
    }

    /// Toggles only the same content state that produced the token. A failure changes
    /// nothing, including when another window edited, moved or deleted a page.
    public func toggleNotebookPage(_ expected: NotebookPageChange) throws -> NotebookPageChange {
        try db.transaction {
            try requireActiveNotebook(expected.page.itemID)
            let current = try notebookPageChange(expected.page, deleted: expected.isDeleted)
            // Fully undone ink restores content but advances cache revisions/timestamps.
            // Keep every semantic field (including deletion identity), objects and OCR guarded.
            let semanticColumns = Array(0..<10) + [11, 13]
            guard semanticColumns.allSatisfy({ current.row[$0] == expected.row[$0] }),
                  current.objects == expected.objects,
                  current.recognition == expected.recognition,
                  current.surroundingOrder == expected.surroundingOrder else {
                throw StoreError.notebookPageChanged
            }
            if expected.isDeleted {
                try restorePages([DeletedPage(page: expected.page)])
            } else {
                _ = try deletePages([expected.page.id])
            }
            return try notebookPageChange(expected.page, deleted: !expected.isDeleted)
        }
    }

    private func requireActiveNotebook(_ id: ItemID) throws {
        guard let item = try item(id), item.kind == .notebook, !item.isDeleted else { throw StoreError.itemNotFound }
    }

    private func notebookPageChange(_ page: Page, deleted: Bool) throws -> NotebookPageChange {
        let rows = try db.query("""
            SELECT id, item_id, sort_key, source_width, source_height, content_kind,
                   asset_id, pdf_page_index, template, transform_json, revision,
                   created_at, modified_at, deleted_at FROM pages WHERE id = ?
            """, [.text(page.id.rawValue)]) { statement in
                (0..<14).map { statement.optionalText(Int32($0)) }
            }
        guard let row = rows.first, (row[13] != nil) == deleted else { throw StoreError.notebookPageChanged }
        let order = try pages(of: page.itemID).filter { $0.id != page.id }.map { "\($0.id.rawValue):\($0.sortKey)" }
        return NotebookPageChange(page: page, isDeleted: deleted, row: row,
                                  objects: try objects(on: page.id), recognition: try recognition(for: page.id),
                                  surroundingOrder: order)
    }
}

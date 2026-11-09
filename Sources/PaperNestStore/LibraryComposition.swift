import Foundation
import PaperNestCore

extension LibraryStore {
    /// Copies active items in selection order, including empty items. The
    /// entire batch (including name allocation) commits or rolls back together.
    public func duplicateItems(_ ids: [ItemID]) throws -> [LibraryItem] {
        try db.transaction {
            guard !ids.isEmpty, Set(ids).count == ids.count else { throw StoreError.invalidOrder }
            var checkedAssets = Set<AssetID>()
            return try ids.map { id in
                let source = try compositionSource(id)
                let copy = try composeItem(kind: source.kind, named: source.name, folderID: source.folderID,
                                           colorLabel: source.colorLabel, pages: pages(of: id), checkedAssets: &checkedAssets)
                if let payload = try filePayload(id) {
                    // A file item has no pages: its copy points at the same
                    // immutable bytes, under its own name.
                    try validateCompositionAsset(payload.assetID, checked: &checkedAssets)
                    try insertFileRow(copy.id, payload)
                }
                return copy
            }
        }
    }

    /// Joins at least two distinct, active, nonempty items, first by selection
    /// order and then by each item's stored live-page order. Sources stay intact.
    public func mergeItems(_ ids: [ItemID], named name: String, folderID: FolderID?) throws -> LibraryItem {
        try db.transaction {
            guard ids.count >= 2, Set(ids).count == ids.count else { throw StoreError.invalidOrder }
            var ordered: [Page] = []
            for id in ids {
                let source = try compositionSource(id)
                guard source.kind != .file else { throw StoreError.invalidOrder }
                let sourcePages = try pages(of: id)
                guard !sourcePages.isEmpty else { throw StoreError.invalidOrder }
                ordered.append(contentsOf: sourcePages)
            }
            var checkedAssets = Set<AssetID>()
            return try composeItem(kind: .document, named: name, folderID: folderID,
                                   colorLabel: nil, pages: ordered, checkedAssets: &checkedAssets)
        }
    }

    /// Copies every live page of an active item into a document of its own, in
    /// stored page order. `nameForPage` receives the 1-based page number and the
    /// page count. The source stays intact and the whole batch commits together.
    public func splitItem(_ id: ItemID, nameForPage: @Sendable (Int, Int) -> String) throws -> [LibraryItem] {
        try db.transaction {
            let source = try compositionSource(id)
            guard source.kind != .file else { throw StoreError.invalidOrder }
            let sourcePages = try pages(of: id)
            guard !sourcePages.isEmpty else { throw StoreError.invalidOrder }
            var checkedAssets = Set<AssetID>()
            return try sourcePages.enumerated().map { index, page in
                try composeItem(kind: .document, named: nameForPage(index + 1, sourcePages.count),
                                folderID: source.folderID, colorLabel: source.colorLabel,
                                pages: [page], checkedAssets: &checkedAssets)
            }
        }
    }

    /// Copies a nonempty set of distinct live pages into a document in the
    /// source's folder. Stored page order wins over the order of selection taps.
    public func extractPages(_ pageIDs: [PageID], from itemID: ItemID, named name: String) throws -> LibraryItem {
        try db.transaction {
            let source = try compositionSource(itemID)
            guard source.kind != .file else { throw StoreError.invalidOrder }
            let selected = Set(pageIDs)
            guard !pageIDs.isEmpty, selected.count == pageIDs.count else { throw StoreError.invalidOrder }
            let ordered = try pages(of: itemID).filter { selected.contains($0.id) }
            // Also rejects missing, deleted and wrong-owner pages, without
            // silently accepting the valid subset of a bad selection.
            guard ordered.count == selected.count else { throw StoreError.invalidOrder }
            var checkedAssets = Set<AssetID>()
            return try composeItem(kind: .document, named: name, folderID: source.folderID,
                                   colorLabel: source.colorLabel, pages: ordered, checkedAssets: &checkedAssets)
        }
    }

    /// One atomic insertion and its guarded, in-session undo token.
    public struct PageDuplicationChange: Sendable {
        public let pages: [Page]
        public let isDeleted: Bool
        fileprivate let snapshots: [DuplicatedPageSnapshot]
        fileprivate let order: [PageID]
    }

    fileprivate struct DuplicatedPageSnapshot: Sendable {
        let row: [String?]
        let objects: [PageObject]
    }

    /// Copies selected pages in source order after `anchor`, keeping their
    /// editable objects and derived text under fresh identities. The complete
    /// batch commits or rolls back together, including late asset validation.
    public func duplicatePages(_ pageIDs: [PageID], in itemID: ItemID, after anchor: PageID?) throws -> PageDuplicationChange {
        try db.transaction {
            let item = try compositionSource(itemID)
            guard item.kind != .file, !pageIDs.isEmpty, Set(pageIDs).count == pageIDs.count else { throw StoreError.invalidOrder }
            let wanted = Set(pageIDs)
            let sourcePages = try pages(of: itemID).filter { wanted.contains($0.id) }
            guard sourcePages.count == wanted.count else { throw StoreError.invalidOrder }
            var checked = Set<AssetID>()
            for page in sourcePages {
                if let asset = page.content.assetID { try validateCompositionAsset(asset, checked: &checked) }
            }
            let inserted = try insertPages(sourcePages.map {
                NewPage(sourceSize: $0.sourceSize, content: $0.content, transform: $0.transform)
            }, into: itemID, after: anchor, assets: [])
            var copies: [Page] = []
            for (source, destination) in zip(sourcePages, inserted) {
                copies.append(try copyPageContents(from: source, to: destination, checkedAssets: &checked))
            }
            return try duplicationChange(copies, deleted: false)
        }
    }

    /// Refuses to remove or restore a copy another window changed. Cache
    /// revisions and timestamps can advance through fully undone edits; page
    /// semantics, current objects and ordering must still match. Derived OCR
    /// may finish in the background; soft deletion keeps those rows for redo.
    public func toggleDuplicatedPages(_ expected: PageDuplicationChange) throws -> PageDuplicationChange {
        try db.transaction {
            guard let first = expected.pages.first else { throw StoreError.invalidOrder }
            _ = try compositionSource(first.itemID)
            let current = try duplicationChange(expected.pages, deleted: expected.isDeleted)
            let semanticColumns = [0, 1] + Array(3..<10) + [11, 13]
            guard current.order == expected.order,
                  zip(current.snapshots, expected.snapshots).allSatisfy({ actual, old in
                      semanticColumns.allSatisfy { actual.row[$0] == old.row[$0] }
                          && actual.objects == old.objects
                  }) else { throw StoreError.notebookPageChanged }
            if expected.isDeleted {
                try restorePages(expected.pages.map { DeletedPage(page: $0) })
            } else { _ = try deletePages(expected.pages.map(\.id)) }
            let live = try expected.pages.map { try page($0.id) ?? $0 }
            return try duplicationChange(live, deleted: !expected.isDeleted)
        }
    }

    private func duplicationChange(_ copied: [Page], deleted: Bool) throws -> PageDuplicationChange {
        guard let first = copied.first else { throw StoreError.invalidOrder }
        let snapshots = try copied.map { page in
            let rows = try db.query("""
                SELECT id, item_id, sort_key, source_width, source_height, content_kind,
                       asset_id, pdf_page_index, template, transform_json, revision,
                       created_at, modified_at, deleted_at FROM pages WHERE id = ?
                """, [.text(page.id.rawValue)]) { statement in
                    (0..<14).map { statement.optionalText(Int32($0)) }
                }
            guard let row = rows.first, (row[13] != nil) == deleted else { throw StoreError.notebookPageChanged }
            return DuplicatedPageSnapshot(row: row, objects: try objects(on: page.id))
        }
        return PageDuplicationChange(pages: copied, isDeleted: deleted, snapshots: snapshots,
                                     order: try pages(of: first.itemID).map(\.id))
    }

    private func compositionSource(_ id: ItemID) throws -> LibraryItem {
        guard let source = try item(id), !source.isDeleted else { throw StoreError.itemNotFound }
        return source
    }

    /// Called only inside a composition transaction. Existing public store
    /// mutations nest as savepoints, so neither intermediate items nor index
    /// rows become visible before the outer operation commits.
    private func composeItem(
        kind: ItemKind, named name: String, folderID: FolderID?, colorLabel: ItemColor?,
        pages sourcePages: [Page], checkedAssets: inout Set<AssetID>
    ) throws -> LibraryItem {
        if let folderID {
            guard try folders().contains(where: { $0.id == folderID }) else { throw StoreError.folderNotFound }
        }
        for source in sourcePages {
            if let assetID = source.content.assetID {
                try validateCompositionAsset(assetID, checked: &checkedAssets)
            }
        }
        let created = try createItem(kind: kind, name: name, folderID: folderID, pages: sourcePages.map {
            NewPage(sourceSize: $0.sourceSize, content: $0.content, transform: $0.transform)
        }, assets: [])
        if let colorLabel { try setColorLabel(colorLabel, for: [created.id]) }

        // Copies start a new editing lifetime: current transforms and objects
        // are retained, but transform/rescan undo history and deleted pages
        // are deliberately not cloned. Immutable assets are shared by hash.
        let destinations = try pages(of: created.id)
        for (source, destination) in zip(sourcePages, destinations) {
            _ = try copyPageContents(from: source, to: destination, checkedAssets: &checkedAssets)
        }
        // Object and label mutations may have advanced modifiedAt; return the
        // committed metadata as it now stands, rather than createItem's snapshot.
        guard let result = try item(created.id) else { throw StoreError.itemNotFound }
        return result
    }

    private func copyPageContents(from source: Page, to destination: Page, checkedAssets: inout Set<AssetID>) throws -> Page {
        let sourceObjects = try objects(on: source.id)
        for object in sourceObjects {
            if case .image(let image) = object.payload {
                try validateCompositionAsset(image.assetID, checked: &checkedAssets)
            }
        }
        // Fresh IDs change the tie-breaker for equal z-keys. Respacing in
        // stored order preserves the exact paint order, even after sync
        // has left tied keys. Payloads remain fully editable and unchanged.
        let keys = SortKey.evenlySpaced(count: sourceObjects.count)
        let copies = zip(sourceObjects, keys).map { object, key in
            PageObject(pageID: destination.id, zKey: key, payload: object.payload, modifiedAt: destination.modifiedAt)
        }
        let current = try applyObjectChanges(on: destination.id, saving: copies, deleting: [])
        try copyCompositionRecognition(from: source, to: current)
        try copyEmbeddedText(from: source, to: current)

        return current
    }

    private func validateCompositionAsset(_ id: AssetID, checked: inout Set<AssetID>) throws {
        guard !checked.contains(id) else { return }
        // Checks metadata, local availability and readable bytes, including
        // placed images whose asset references live inside object JSON.
        _ = try assetData(id)
        checked.insert(id)
    }

    private func copyCompositionRecognition(from source: Page, to destination: Page) throws {
        guard var recognition = try recognition(for: source.id) else { return }
        let isCurrent = recognition.pageID == source.id
            && recognition.sourceRevision == source.revision && recognition.status == .completed
        recognition.pageID = destination.id
        recognition.sourceRevision = destination.revision
        if !isCurrent {
            // Resetting revisions on a fresh page must not accidentally make
            // old OCR current. Pending/failed work also belongs to the old
            // page; explicitly request recognition anew and discard its text.
            recognition.status = .pending
            recognition.lines = []
        }
        // `saveRecognition` indexes the text itself, including clearing it
        // when the copied result is not current.
        try saveRecognition(recognition)
    }

}

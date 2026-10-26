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

            // Rebuild derived text rows from current objects rather than
            // carrying stale content or source item/page IDs into the copy.
            let text = sourceObjects.compactMap { object -> String? in
                if case .text(let box) = object.payload { return box.text }
                return nil
            }.joined(separator: "\n")
            try indexCompositionText(text, field: "text", on: current)
        }
        // Object and label mutations may have advanced modifiedAt; return the
        // committed metadata as it now stands, rather than createItem's snapshot.
        guard let result = try item(created.id) else { throw StoreError.itemNotFound }
        return result
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

    private func indexCompositionText(_ text: String, field: String, on page: Page) throws {
        guard !text.isEmpty else { return }
        try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                   [.text(page.itemID.rawValue), .text(page.id.rawValue), .text(field), .text(text)])
    }
}

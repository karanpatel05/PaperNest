import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct DocumentCompositionTests {
    enum Operation: String, CaseIterable, Sendable {
        case duplicate, merge, extract

        func compose(_ store: LibraryStore, source: ItemID, other: ItemID) async throws -> LibraryItem {
            switch self {
            case .duplicate:
                return try await store.duplicateItems([source])[0]
            case .merge:
                return try await store.mergeItems([source, other], named: "Composed", folderID: nil)
            case .extract:
                let pages = try await store.pages(of: source)
                return try await store.extractPages(pages.reversed().map(\.id), from: source, named: "Composed")
            }
        }
    }

    @Test func duplicateKeepsKindsFoldersAndEmptyItemsWithUniqueNames() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let folder = try await store.createFolder(named: "Notes")
        let first = try await store.createItem(kind: .notebook, name: "Résumé", folderID: folder.id,
                                               pages: [], assets: [])
        let second = try await store.createItem(kind: .document, name: "resume 2", folderID: folder.id,
                                                pages: [], assets: [])
        let copies = try await store.duplicateItems([second.id, first.id])
        #expect(copies.map(\.name) == ["resume 2 2", "Résumé 3"])
        #expect(copies.map(\.kind) == [.document, .notebook])
        #expect(copies.allSatisfy { $0.folderID == folder.id })
        #expect(Set(copies.map(\.id)).isDisjoint(with: [first.id, second.id]))
        for copy in copies { #expect(try await store.pages(of: copy.id).isEmpty) }
        #expect(try await store.duplicateItems([first.id])[0].name == "Résumé 4")
        #expect(try await store.item(first.id) == first)
        #expect(try await store.item(second.id) == second)
    }

    @Test func mergeUsesSelectionItemOrderAndStoredLivePageOrder() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("ordered PDF".utf8), kind: .pdf, originalFilename: nil)
        let a = try await store.createItem(kind: .notebook, name: "A", pages: samplePages(asset, count: 3), assets: [asset])
        let b = try await store.createItem(kind: .document, name: "B", pages: samplePages(asset, count: 2), assets: [])
        let aPages = try await store.pages(of: a.id)
        let bPages = try await store.pages(of: b.id)
        try await store.movePage(aPages[2].id, toIndex: 0)
        try await store.deletePages([aPages[1].id])
        try await store.movePage(bPages[1].id, toIndex: 0)
        let beforeA = try await store.pages(of: a.id)
        let beforeB = try await store.pages(of: b.id)
        let folder = try await store.createFolder(named: "Output")
        _ = try await store.createItem(kind: .document, name: "Combined", folderID: folder.id, pages: [], assets: [])

        let merged = try await store.mergeItems([b.id, a.id], named: "Combined", folderID: folder.id)
        let pages = try await store.pages(of: merged.id)
        #expect(merged.kind == .document && merged.folderID == folder.id && merged.name == "Combined 2")
        #expect(pages.map(\.content) == [1, 0, 2, 0].map { .pdfPage(asset.id, index: $0) })
        #expect(pages.allSatisfy { $0.itemID == merged.id })
        #expect(Set(pages.map(\.id)).isDisjoint(with: (aPages + bPages).map(\.id)))
        #expect(try await store.pages(of: a.id) == beforeA)
        #expect(try await store.pages(of: b.id) == beforeB)
    }

    @Test func extractionUsesSourceOrderAndFolderWithoutRemovingPages() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("extract PDF".utf8), kind: .pdf, originalFilename: nil)
        let folder = try await store.createFolder(named: "Source")
        let source = try await store.createItem(kind: .notebook, name: "Pages", folderID: folder.id,
                                                pages: samplePages(asset, count: 4), assets: [asset])
        let original = try await store.pages(of: source.id)
        try await store.movePage(original[3].id, toIndex: 0)
        let before = try await store.pages(of: source.id)
        let extracted = try await store.extractPages([original[0].id, original[3].id], from: source.id, named: "Pages")
        #expect(extracted.kind == .document && extracted.folderID == folder.id && extracted.name == "Pages 2")
        #expect(try await store.pages(of: extracted.id).map(\.content) == [.pdfPage(asset.id, index: 3), .pdfPage(asset.id, index: 0)])
        #expect(try await store.pages(of: source.id) == before)
    }

    @Test(arguments: Operation.allCases)
    func sourceColorIsPreservedExceptForMerge(_ operation: Operation) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let pages: [LibraryStore.NewPage] = [.init(sourceSize: CGSize(width: 100, height: 200), content: .template(.lined))]
        let source = try await store.createItem(kind: .notebook, name: "Source", pages: pages, assets: [])
        let other = try await store.createItem(kind: .document, name: "Other", pages: pages, assets: [])
        try await store.setColorLabel(.purple, for: [source.id])
        try await store.setColorLabel(.blue, for: [other.id])
        let result = try await operation.compose(store, source: source.id, other: other.id)
        #expect(result.colorLabel == (operation == .merge ? nil : .purple))
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.item(result.id)?.colorLabel == result.colorLabel)
        #expect(try await reopened.item(source.id)?.colorLabel == .purple)
        #expect(try await reopened.item(other.id)?.colorLabel == .blue)
    }

    @Test(arguments: Operation.allCases)
    func editableContentRecognitionAndAssetsSurviveIndependentEditsDeletionAndReopen(_ operation: Operation) async throws {
        let dir = TempDirectory()
        let result: LibraryItem
        let resultPages: [Page]
        let resultObjects: [PageObject]
        let background: AssetFileStore.StagedAsset
        let placed: AssetFileStore.StagedAsset
        do {
            let store = try LibraryStore(directory: dir.url)
            background = try store.assets.store(Data("current scan".utf8), kind: .png, originalFilename: "scan.png")
            placed = try store.assets.store(Data("placed photo".utf8), kind: .jpeg, originalFilename: "photo.jpg")
            let old = try store.assets.store(Data("previous scan".utf8), kind: .png, originalFilename: nil)
            let source = try await store.createItem(kind: .notebook, name: "Source", pages: [
                .init(sourceSize: CGSize(width: 400, height: 600), content: .image(old.id)),
                .init(sourceSize: CGSize(width: 612, height: 792), content: .template(.grid)),
            ], assets: [background, placed, old])
            let other = try await store.createItem(kind: .document, name: "Other", pages: [
                .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.lined)),
            ], assets: [])
            let initial = try await store.pages(of: source.id)
            let transform = PageTransform(crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                                          rotation: .clockwise270, filter: .grayscale, brightness: 0.2, contrast: 1.7)
            try await store.replacePageContent(initial[0].id, with: .init(sourceSize: CGSize(width: 500, height: 700),
                                                                         content: .image(background.id), transform: .identity), assets: [])
            try await store.updateTransform(initial[0].id, to: transform)
            // Equal z-keys can arise from sync. Fresh IDs must not shuffle paint order.
            let objects = [
                PageObject(id: .init(rawValue: "a"), pageID: initial[0].id, zKey: "V",
                           payload: .ink(.init(tool: .highlighter, color: .init(red: 0.8, green: 0.3, blue: 0.1), width: 3,
                                               points: [.init(x: 10, y: 20, widthScale: 0.7), .init(x: 90, y: 80, time: 0.3)])), modifiedAt: source.createdAt),
                PageObject(id: .init(rawValue: "b"), pageID: initial[0].id, zKey: "V",
                           payload: .text(.init(frame: CGRect(x: 20, y: 30, width: 200, height: 80), text: "Editablecafé",
                                                fontSize: 19, alignment: .center)), modifiedAt: source.createdAt),
                PageObject(id: .init(rawValue: "c"), pageID: initial[0].id, zKey: "V",
                           payload: .image(.init(assetID: placed.id, frame: CGRect(x: 50, y: 100, width: 120, height: 90))),
                           modifiedAt: source.createdAt),
            ]
            try await store.applyObjectChanges(on: initial[0].id, saving: objects, deleting: [])
            let current = try await store.pages(of: source.id)
            let recognized = PageRecognition(pageID: current[0].id, sourceRevision: current[0].revision,
                                             engineVersion: "synthetic", status: .completed, languages: ["fr-FR"],
                                             lines: [.init(text: "Recognizedcafé", box: .init(x: 0.1, y: 0.2, width: 0.4, height: 0.1), confidence: 0.96)])
            try await store.saveRecognition(recognized)
            try await store.saveRecognition(.init(pageID: current[1].id, sourceRevision: current[1].revision,
                                                   engineVersion: "synthetic", status: .completed, languages: ["es-ES"],
                                                   lines: [.init(text: "Obsoleterecognition", box: .full, confidence: 0.8)]))
            try await store.updateTransform(current[1].id, to: .init(rotation: .half))
            let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
            for (page, field, text) in [(current[0].id, "ocr", "Recognizedcafé"), (current[0].id, "text", "Editablecafé"),
                                        (current[1].id, "ocr", "Obsoleterecognition")] {
                try raw.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                            [.text(source.id.rawValue), .text(page.rawValue), .text(field), .text(text)])
            }
            raw.close()
            let sourcePages = try await store.pages(of: source.id)
            result = try await operation.compose(store, source: source.id, other: other.id)
            resultPages = try await store.pages(of: result.id)
            resultObjects = try await store.objects(on: resultPages[0].id)
            #expect(resultPages.count == (operation == .merge ? 3 : 2))
            #expect(resultPages[0].sourceSize == CGSize(width: 500, height: 700))
            #expect(resultPages[0].transform == transform)
            #expect(resultPages[1].content == .template(.grid))
            #expect(resultPages[1].transform.rotation == .half)
            #expect(resultObjects.map(\.payload) == objects.map(\.payload))
            #expect(resultObjects.allSatisfy { $0.pageID == resultPages[0].id })
            #expect(Set(resultObjects.map(\.id)).count == 3)
            #expect(Set(resultObjects.map(\.id)).isDisjoint(with: objects.map(\.id)))
            #expect(Set(resultPages.map(\.id)).isDisjoint(with: sourcePages.map(\.id)))
            #expect(try await store.transformHistory(resultPages[0].id).isEmpty)
            #expect(try await store.pages(of: source.id) == sourcePages)
            #expect(try await store.objects(on: current[0].id) == objects)
            let copiedRecognition = try #require(try await store.recognition(for: resultPages[0].id))
            #expect(copiedRecognition.pageID == resultPages[0].id)
            #expect(copiedRecognition.sourceRevision == resultPages[0].revision)
            #expect(copiedRecognition.status == .completed && copiedRecognition.lines == recognized.lines)
            #expect(copiedRecognition.languages == recognized.languages && copiedRecognition.engineVersion == recognized.engineVersion)
            let stale = try #require(try await store.recognition(for: resultPages[1].id))
            #expect(stale.pageID == resultPages[1].id && stale.status == .pending && stale.lines.isEmpty)
            #expect(try await store.search("Recognizedcafe").contains(result.id))
            #expect(try await store.search("Editablecafe").contains(result.id))
            #expect(try await store.search("Obsoleterecognition").contains(result.id) == false)
            let index = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
            let indexedPages = try index.query("SELECT page_id FROM search_index WHERE item_id = ? AND field <> 'title'",
                                                [.text(result.id.rawValue)]) { PageID(rawValue: $0.text(0)) }
            #expect(indexedPages.count == 2 && indexedPages.allSatisfy { $0 == resultPages[0].id })
            index.close()

            // Editing a copy must never edit the original object with the same payload.
            var edited = resultObjects[1]
            edited.payload = .text(.init(frame: .zero, text: "Changed only in copy"))
            try await store.saveObject(edited)
            #expect(try await store.objects(on: current[0].id) == objects)
            try await store.saveObject(resultObjects[1])
            try await store.updateTransform(current[0].id, to: .identity)
            try await store.deleteObject(objects[0].id)
            #expect(try await store.objects(on: resultPages[0].id) == resultObjects)
            #expect(try await store.page(resultPages[0].id)?.transform == transform)

            try await store.moveToRecentlyDeleted([source.id, other.id])
            #expect(try await store.deletePermanently([source.id, other.id]) == 2)
            #expect(try await store.purgeReplacedPageContent() == 0) // No copied rescan undo history.
            try await store.purgeDeletedPages()
            try await store.sweepOrphanAssets(gracePeriod: 0)
            #expect(try await store.assetRecord(old.id) == nil)
            #expect(try await store.assetData(background.id).0 == Data("current scan".utf8))
            #expect(try await store.assetData(placed.id).0 == Data("placed photo".utf8))
            #expect(try await store.search("Recognizedcafe") == [result.id])
        }
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.item(result.id)?.name == result.name)
        let pages = try await reopened.pages(of: result.id)
        #expect(pages.map(\.id) == resultPages.map(\.id))
        #expect(pages.map(\.content) == resultPages.map(\.content))
        #expect(pages.map(\.transform) == resultPages.map(\.transform))
        #expect(try await reopened.objects(on: pages[0].id) == resultObjects)
        #expect(try await reopened.recognition(for: pages[0].id)?.pageID == pages[0].id)
        #expect(try await reopened.recognition(for: pages[0].id)?.text == "Recognizedcafé")
        #expect(try await reopened.recognition(for: pages[1].id)?.status == .pending)
        #expect(try await reopened.assetData(background.id).0 == Data("current scan".utf8))
        #expect(try await reopened.assetData(placed.id).0 == Data("placed photo".utf8))
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func invalidItemSelectionsAreRejectedWithoutCreatingAnything() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("selection".utf8), kind: .pdf, originalFilename: nil)
        let a = try await store.createItem(kind: .document, name: "A", pages: samplePages(asset, count: 1), assets: [asset])
        let empty = try await store.createItem(kind: .document, name: "Empty", pages: [], assets: [])
        let deleted = try await store.createItem(kind: .document, name: "Deleted", pages: samplePages(asset, count: 1), assets: [])
        try await store.moveToRecentlyDeleted([deleted.id])
        let before = try await store.items(in: .all)
        for ids in [[], [a.id, a.id]] {
            await #expect(throws: StoreError.invalidOrder) { try await store.duplicateItems(ids) }
        }
        for ids in [[], [a.id], [a.id, a.id], [a.id, empty.id]] {
            await #expect(throws: StoreError.invalidOrder) { try await store.mergeItems(ids, named: "Invalid", folderID: nil) }
        }
        for missing in [ItemID.make(), deleted.id] {
            await #expect(throws: StoreError.itemNotFound) { try await store.duplicateItems([a.id, missing]) }
            await #expect(throws: StoreError.itemNotFound) { try await store.mergeItems([a.id, missing], named: "Invalid", folderID: nil) }
            await #expect(throws: StoreError.itemNotFound) {
                try await store.extractPages([PageID.make()], from: missing, named: "Invalid")
            }
        }
        #expect(try await store.items(in: .all) == before)
    }

    @Test(arguments: [PageRecognition.Status.pending, .failed, .completed])
    func unfinishedOrMismatchedRecognitionCannotBecomeCurrentByResettingRevision(_ status: PageRecognition.Status) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let source = try await store.createItem(kind: .document, name: "Source", pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.blank)),
        ], assets: [])
        let page = try await store.pages(of: source.id)[0]
        let recognition = PageRecognition(pageID: page.id, sourceRevision: status == .completed ? page.revision + 1 : page.revision,
                                           engineVersion: "synthetic", status: status, languages: ["en-US"],
                                           lines: [.init(text: "Untrustworthytext", box: .full, confidence: 0.9)])
        try await store.saveRecognition(recognition)
        let duplicate = try await store.duplicateItems([source.id])[0]
        let copiedPage = try await store.pages(of: duplicate.id)[0]
        let copied = try #require(try await store.recognition(for: copiedPage.id))
        #expect(copied.pageID == copiedPage.id && copied.status == .pending && copied.lines.isEmpty)
        #expect(try await store.search("Untrustworthytext").isEmpty)
        #expect(try await store.recognition(for: page.id) == recognition)
    }

    @Test func extractionRejectsEmptyRepeatedMissingDeletedAndWrongOwnerPages() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("page selection".utf8), kind: .pdf, originalFilename: nil)
        let a = try await store.createItem(kind: .document, name: "A", pages: samplePages(asset, count: 2), assets: [asset])
        let b = try await store.createItem(kind: .document, name: "B", pages: samplePages(asset, count: 1), assets: [])
        let pages = try await store.pages(of: a.id)
        let otherPage = try await store.pages(of: b.id)[0]
        try await store.deletePages([pages[1].id])
        let before = try await store.items(in: .all)
        for ids in [[], [pages[0].id, pages[0].id], [PageID.make()], [pages[0].id, pages[1].id], [pages[0].id, otherPage.id]] {
            await #expect(throws: StoreError.invalidOrder) { try await store.extractPages(ids, from: a.id, named: "Invalid") }
        }
        #expect(try await store.items(in: .all) == before)
    }

    @Test(arguments: Operation.allCases)
    func lateDatabaseFailureRollsBackEveryItemPageObjectAndIndex(_ operation: Operation) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("rollback".utf8), kind: .pdf, originalFilename: nil)
        let first = try await store.createItem(kind: .document, name: "First", pages: samplePages(asset, count: 1), assets: [asset])
        let second = try await store.createItem(kind: .document, name: "Second", pages: samplePages(asset, count: 2), assets: [])
        let page = try await store.pages(of: second.id)[1]
        try await store.saveObject(.init(pageID: page.id, zKey: "V", payload: .text(.init(frame: .zero, text: "late failure")), modifiedAt: second.createdAt))
        let before = try await store.items(in: .all)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        let tables = ["items", "pages", "page_objects", "page_recognition", "search_index", "page_transform_history", "page_content_history", "assets"]
        let counts = try tables.map { table in try raw.query("SELECT count(*) FROM \(table)") { $0.int(0) }[0] }
        try raw.execute("CREATE TRIGGER reject_composed_objects BEFORE INSERT ON page_objects BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END")
        await #expect(throws: StoreError.self) {
            if operation == .duplicate {
                _ = try await store.duplicateItems([first.id, second.id])
            } else {
                _ = try await operation.compose(store, source: second.id, other: first.id)
            }
        }
        #expect(try await store.items(in: .all) == before)
        #expect(try tables.map { table in try raw.query("SELECT count(*) FROM \(table)") { $0.int(0) }[0] } == counts)
        try raw.execute("DROP TRIGGER reject_composed_objects")
        raw.close()
        if operation == .duplicate {
            #expect(try await store.duplicateItems([first.id, second.id]).map(\.name) == ["First 2", "Second 2"])
        } else {
            #expect(try await operation.compose(store, source: second.id, other: first.id).name == "Composed")
        }
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    enum MissingAsset: CaseIterable, Sendable { case backgroundFile, backgroundRecord, placedFile, placedRecord, remoteOnly }

    @Test(arguments: Operation.allCases, MissingAsset.allCases)
    func missingReferencedAssetsAbortComposition(_ operation: Operation, _ missing: MissingAsset) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let background = try store.assets.store(Data("background".utf8), kind: .pdf, originalFilename: nil)
        let placed = try store.assets.store(Data("placement".utf8), kind: .png, originalFilename: nil)
        let source = try await store.createItem(kind: .document, name: "Source", pages: samplePages(background, count: 1), assets: [background, placed])
        let other = try await store.createItem(kind: .document, name: "Other", pages: [
            .init(sourceSize: CGSize(width: 100, height: 100), content: .template(.blank)),
        ], assets: [])
        let page = try await store.pages(of: source.id)[0]
        try await store.saveObject(.init(pageID: page.id, zKey: "V", payload: .image(.init(assetID: placed.id, frame: .zero)), modifiedAt: source.createdAt))
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        let missingID: AssetID
        switch missing {
        case .backgroundFile:
            missingID = background.id
            try store.assets.remove(background.id, kind: background.kind)
        case .backgroundRecord:
            missingID = background.id
            try raw.run("DELETE FROM assets WHERE id = ?", [.text(background.id.sha256)])
        case .placedFile:
            missingID = placed.id
            try store.assets.remove(placed.id, kind: placed.kind)
        case .placedRecord:
            missingID = placed.id
            try raw.run("DELETE FROM assets WHERE id = ?", [.text(placed.id.sha256)])
        case .remoteOnly:
            missingID = background.id
            try raw.run("UPDATE assets SET availability = 'remoteOnly' WHERE id = ?", [.text(background.id.sha256)])
        }
        raw.close()
        let before = try await store.items(in: .all)
        await #expect(throws: StoreError.assetMissing(missingID.sha256)) {
            if operation == .duplicate {
                _ = try await store.duplicateItems([other.id, source.id])
            } else {
                _ = try await operation.compose(store, source: source.id, other: other.id)
            }
        }
        #expect(try await store.items(in: .all) == before)
    }

    @Test(arguments: Operation.allCases, [false, true])
    func missingOrDeletedDestinationFolderIsRejected(_ operation: Operation, _ deleted: Bool) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let folder = try await store.createFolder(named: "Destination")
        let source = try await store.createItem(kind: .document, name: "Source", folderID: folder.id, pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.blank)),
        ], assets: [])
        let other = try await store.createItem(kind: .document, name: "Other", pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.blank)),
        ], assets: [])
        // Model a dangling or tombstoned folder reference from an interrupted sync.
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        try raw.run(deleted ? "UPDATE folders SET deleted_at = 1 WHERE id = ?" : "DELETE FROM folders WHERE id = ?", [.text(folder.id.rawValue)])
        raw.close()
        let before = try await store.items(in: .all)
        await #expect(throws: StoreError.folderNotFound) {
            if operation == .merge {
                _ = try await store.mergeItems([source.id, other.id], named: "Composed", folderID: folder.id)
            } else {
                _ = try await operation.compose(store, source: source.id, other: other.id)
            }
        }
        #expect(try await store.items(in: .all) == before)
    }
}

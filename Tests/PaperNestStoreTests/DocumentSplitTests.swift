import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F1 follow-up: one document per page. Splitting is composition, so it shares
/// `LibraryComposition`'s guarantees: fresh identities, shared immutable assets,
/// sources left intact, and the whole batch committing or rolling back together.
@Suite struct DocumentSplitTests {
    @Test func splitMakesOneDocumentPerLivePageInOrderAndLeavesTheSourceIntact() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("split PDF".utf8), kind: .pdf, originalFilename: nil)
        let folder = try await store.createFolder(named: "Scans")
        let source = try await store.createItem(kind: .notebook, name: "Lease", folderID: folder.id,
                                                pages: samplePages(asset, count: 3), assets: [asset])
        try await store.setColorLabel(.green, for: [source.id])
        let original = try await store.pages(of: source.id)
        try await store.movePage(original[2].id, toIndex: 0)
        let before = try await store.pages(of: source.id)

        let parts = try await store.splitItem(source.id) { index, total in "Lease — Page \(index) of \(total)" }

        #expect(parts.map(\.name) == ["Lease — Page 1 of 3", "Lease — Page 2 of 3", "Lease — Page 3 of 3"])
        // A split page becomes an ordinary document, even from a notebook, and
        // keeps the source's folder and color so the parts stay findable.
        #expect(parts.allSatisfy { $0.kind == .document && $0.folderID == folder.id && $0.colorLabel == .green })
        #expect(Set(parts.map(\.id)).count == 3)
        for (part, page) in zip(parts, before) {
            let copied = try await store.pages(of: part.id)
            #expect(copied.count == 1)
            #expect(copied[0].content == page.content)
            #expect(copied[0].sourceSize == page.sourceSize)
            #expect(copied[0].id != page.id)
        }
        #expect(try await store.pages(of: source.id) == before)
        #expect(try await store.item(source.id)?.name == "Lease")

        // Identical names from the caller still land as distinct siblings.
        let again = try await store.splitItem(source.id) { _, _ in "Lease" }
        #expect(again.map(\.name) == ["Lease 2", "Lease 3", "Lease 4"])
    }

    @Test func splitIgnoresDeletedPagesAndCopiesEditableObjectsThatOutliveTheOriginal() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("objects".utf8), kind: .pdf, originalFilename: nil)
        let source = try await store.createItem(kind: .document, name: "Notes",
                                                pages: samplePages(asset, count: 3), assets: [asset])
        let pages = try await store.pages(of: source.id)
        let note = PageObject(pageID: pages[1].id, zKey: "V", payload: .text(.init(frame: .zero, text: "keep me")),
                              modifiedAt: source.createdAt)
        try await store.saveObject(note)
        _ = try await store.deletePages([pages[0].id])

        let parts = try await store.splitItem(source.id) { index, _ in "Notes \(index)" }

        #expect(parts.count == 2)
        let carried = try await store.objects(on: store.pages(of: parts[0].id)[0].id)
        #expect(carried.count == 1)
        #expect(carried[0].id != note.id)
        if case .text(let box) = carried[0].payload { #expect(box.text == "keep me") } else { Issue.record("payload changed") }
        #expect(try await store.objects(on: store.pages(of: parts[1].id)[0].id).isEmpty)

        // The parts own their content: deleting the source for good leaves them readable.
        try await store.moveToRecentlyDeleted([source.id])
        _ = try await store.deletePermanently([source.id])
        let reopened = try LibraryStore(directory: dir.url)
        // Page 0 was deleted before the split, so the parts hold pages 1 and 2.
        for (part, index) in zip(parts, [1, 2]) {
            #expect(try await reopened.pages(of: part.id)[0].content == .pdfPage(asset.id, index: index))
        }
        #expect(try await reopened.assetData(asset.id).0 == Data("objects".utf8))
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func splitRejectsEmptyMissingAndDeletedItemsWithoutCreatingAnything() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("reject".utf8), kind: .pdf, originalFilename: nil)
        let empty = try await store.createItem(kind: .document, name: "Empty", pages: [], assets: [])
        let gone = try await store.createItem(kind: .document, name: "Gone", pages: samplePages(asset, count: 1), assets: [asset])
        try await store.moveToRecentlyDeleted([gone.id])
        let before = try await store.items(in: .all)

        await #expect(throws: StoreError.invalidOrder) { try await store.splitItem(empty.id) { i, _ in "\(i)" } }
        for missing in [ItemID.make(), gone.id] {
            await #expect(throws: StoreError.itemNotFound) { try await store.splitItem(missing) { i, _ in "\(i)" } }
        }
        #expect(try await store.items(in: .all) == before)
    }

    @Test func aFailurePartWayThroughRollsBackEveryDocumentTheSplitHadCreated() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("rollback".utf8), kind: .pdf, originalFilename: nil)
        let source = try await store.createItem(kind: .document, name: "Batch",
                                                pages: samplePages(asset, count: 3), assets: [asset])
        let pages = try await store.pages(of: source.id)
        // The object is on the last page, so two documents already exist when it fails.
        try await store.saveObject(PageObject(pageID: pages[2].id, zKey: "V",
                                              payload: .text(.init(frame: .zero, text: "boom")),
                                              modifiedAt: source.createdAt))
        let before = try await store.items(in: .all)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        let tables = ["items", "pages", "page_objects", "search_index", "assets"]
        let counts = try tables.map { table in try raw.query("SELECT count(*) FROM \(table)") { $0.int(0) }[0] }
        try raw.execute("CREATE TRIGGER reject_split BEFORE INSERT ON page_objects BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END")

        await #expect(throws: StoreError.self) { try await store.splitItem(source.id) { i, _ in "Part \(i)" } }

        #expect(try await store.items(in: .all) == before)
        #expect(try tables.map { table in try raw.query("SELECT count(*) FROM \(table)") { $0.int(0) }[0] } == counts)
        try raw.execute("DROP TRIGGER reject_split")
        raw.close()
        #expect(try await store.splitItem(source.id) { i, _ in "Part \(i)" }.map(\.name) == ["Part 1", "Part 2", "Part 3"])
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.integrityCheck().isEmpty)
    }
}

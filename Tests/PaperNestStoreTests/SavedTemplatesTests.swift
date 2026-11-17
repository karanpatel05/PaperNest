import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Pages saved as templates: what is kept, what a page made from one gets,
/// and that a template keeps its originals alive everywhere the library
/// decides whether an original is still needed.
@Suite struct SavedTemplatesTests {
    private func notebook(_ store: LibraryStore, _ name: String, paper: PageTemplate = .lined) async throws -> (LibraryItem, Page) {
        let book = try await store.createNotebook(named: name, folderID: nil, template: paper)
        return (book, try #require(try await store.pages(of: book.id).first))
    }

    private func object(_ page: Page, _ key: String, _ payload: PageObject.Payload) -> PageObject {
        PageObject(pageID: page.id, zKey: key, payload: payload, modifiedAt: Date())
    }

    private let ink = PageObject.Payload.ink(InkStroke(tool: .pen, color: .black, width: 2,
                                                        points: [InkPoint(x: 100, y: 100), InkPoint(x: 200, y: 120)]))
    private let agenda = PageObject.Payload.text(TextBox(frame: CGRect(x: 40, y: 40, width: 200, height: 20), text: "Quarterly agenda"))

    @Test func aTemplateKeepsThePagesPaperAndMarksButNotItsComments() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store, "Source", paper: .grid)
        try await store.saveObject(object(page, "V", ink))
        try await store.saveObject(object(page, "W", agenda))
        try await store.saveObject(object(page, "X", .comment("Only for me")))

        let template = try await store.saveTemplate(from: page.id, named: "Weekly review")

        #expect(template.name == "Weekly review")
        #expect(template.content == .template(.grid))
        #expect(template.sourceSize == page.sourceSize && template.transform == page.transform)
        #expect(template.objects == [ink, agenda], "in paint order, and never the private comment")
        #expect(try await store.savedTemplates() == [template], "on disk when the call returns")
    }

    @Test func aPageMadeFromATemplateIsACopyAndUndoTakesItAway() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (source, page) = try await notebook(store, "Source", paper: .dotted)
        try await store.saveObject(object(page, "V", ink))
        try await store.saveObject(object(page, "W", agenda))
        let template = try await store.saveTemplate(from: page.id, named: "Review")
        // The source goes; the template's words are not findable on their own.
        try await store.moveToRecentlyDeleted([source.id])
        #expect(try await store.search("quarterly").isEmpty, "a template's text is not in the index")

        let (target, first) = try await notebook(store, "Target")
        let change = try await store.addNotebookPage(fromTemplate: template.id, to: target.id, after: first.id)

        #expect(change.page.content == .template(.dotted))
        #expect(change.page.sourceSize == page.sourceSize)
        let copied = try await store.objects(on: change.page.id)
        #expect(copied.map(\.payload) == [ink, agenda])
        #expect(Set(copied.map(\.id)).isDisjoint(with: try await store.objects(on: page.id).map(\.id)), "new identities")
        #expect(try await store.search("quarterly") == [target.id], "the page's typed text is findable")

        let undone = try await store.toggleNotebookPage(change)
        #expect(try await store.pages(of: target.id).count == 1)
        _ = try await store.toggleNotebookPage(undone)
        #expect(try await store.objects(on: change.page.id).map(\.payload) == [ink, agenda], "redo, once")
    }

    /// A PDF page's own size and background come along: a letterhead or a form.
    @Test func aDocumentPageCanBeSavedAndKeepsItsSizeAndBackground() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("letterhead pdf".utf8), kind: .pdf, originalFilename: "l.pdf")
        let document = try await store.createItem(kind: .document, name: "Letterhead", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0),
                  transform: PageTransform(rotation: .clockwise90))
        ], assets: [asset])
        let page = try #require(try await store.pages(of: document.id).first)
        let template = try await store.saveTemplate(from: page.id, named: "Letterhead")

        let (book, first) = try await notebook(store, "Letters")
        let change = try await store.addNotebookPage(fromTemplate: template.id, to: book.id, after: first.id)

        #expect(change.page.content == .pdfPage(asset.id, index: 0))
        #expect(change.page.sourceSize == CGSize(width: 612, height: 792), "not forced to A4")
        #expect(change.page.transform.rotation == .clockwise90)
        // Only notebooks take pages from templates.
        await #expect(throws: StoreError.itemNotFound) {
            try await store.addNotebookPage(fromTemplate: template.id, to: document.id, after: page.id)
        }
    }

    // MARK: - Originals

    /// A template made from a scan with a picture on it, whose document is
    /// then deleted for good: the sweep runs, keeps both originals, and
    /// takes them only once the template goes.
    @Test func aTemplateKeepsItsOriginalsUntilItIsDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let scan = try store.assets.store(Data("scan".utf8), kind: .png, originalFilename: "s.png")
        let sticker = try store.assets.store(Data("sticker".utf8), kind: .png, originalFilename: "sticker.png")
        let document = try await store.createItem(kind: .document, name: "Scan", pages: [
            .init(sourceSize: CGSize(width: 300, height: 400), content: .image(scan.id))
        ], assets: [scan, sticker])
        let page = try #require(try await store.pages(of: document.id).first)
        try await store.saveObject(object(page, "V", .image(PlacedImage(assetID: sticker.id,
                                                                       frame: CGRect(x: 10, y: 10, width: 40, height: 40)))))
        let template = try await store.saveTemplate(from: page.id, named: "Stamped scan")
        #expect(template.assetIDs == [scan.id, sticker.id])

        try await store.moveToRecentlyDeleted([document.id])
        // Deleting for good drops unreferenced originals itself: it must keep these.
        #expect(try await store.deletePermanently([document.id]) == 1)
        #expect(try await store.pages(of: document.id).isEmpty)
        let swept = try await store.sweepOrphanAssets(gracePeriod: 0)

        #expect(swept == 0, "the sweep ran and took nothing a template keeps")
        for id in [scan.id, sticker.id] {
            #expect(try await store.assetRecord(id) != nil)
            #expect(try await store.isAssetReferenced(id))
            #expect(try await !store.deleteAssetIfUnreferenced(id), "refused while the template keeps it")
        }

        try await store.deleteSavedTemplate(template.id)
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) >= 2)
        #expect(try await store.assetRecord(scan.id) == nil)
        #expect(try await store.assetRecord(sticker.id) == nil)
    }

    /// Redacting a page whose original a template keeps cannot remove it.
    @Test func theRedactionCheckCountsATemplate() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let scan = try store.assets.store(Data("scan".utf8), kind: .png, originalFilename: "s.png")
        let document = try await store.createItem(kind: .document, name: "Scan", pages: [
            .init(sourceSize: CGSize(width: 300, height: 400), content: .image(scan.id))
        ], assets: [scan])
        let page = try #require(try await store.pages(of: document.id).first)
        #expect(try await !store.isAssetUsedElsewhere(scan.id, besides: page.id))

        _ = try await store.saveTemplate(from: page.id, named: "Copy")

        #expect(try await store.isAssetUsedElsewhere(scan.id, besides: page.id))
    }

    /// Templates are not synced, so iCloud does not speak for them: an
    /// original a template keeps is never offered for removal from the device.
    @Test func syncNeverEvictsAnOriginalATemplateKeeps() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        try await store.syncSetEnabled(true)
        let scan = try store.assets.store(Data("scan".utf8), kind: .png, originalFilename: "s.png")
        let document = try await store.createItem(kind: .document, name: "Scan", pages: [
            .init(sourceSize: CGSize(width: 300, height: 400), content: .image(scan.id))
        ], assets: [scan])
        for upload in try await store.syncAssetsPendingUpload() { try await store.syncAssetDidUpload(upload.record.id) }
        #expect(try await store.syncEvictableAssets(of: document.id).map(\.id) == [scan.id], "precondition: evictable")

        let page = try #require(try await store.pages(of: document.id).first)
        _ = try await store.saveTemplate(from: page.id, named: "Copy")

        #expect(try await store.syncEvictableAssets(of: document.id).isEmpty)
    }

    // MARK: - Names

    @Test func templatesAreListedByNameAndRenamedAndDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store, "Source")
        let b = try await store.saveTemplate(from: page.id, named: "beta")
        let a = try await store.saveTemplate(from: page.id, named: "Alpha")
        let again = try await store.saveTemplate(from: page.id, named: "Alpha")
        #expect(again.name != "Alpha", "two templates are never called the same")
        #expect(try await store.savedTemplates().map(\.id).prefix(1) == [a.id])

        try await store.renameSavedTemplate(b.id, to: "  Zeta  ")
        #expect(try await store.savedTemplate(b.id)?.name == "Zeta")
        try await store.deleteSavedTemplate(a.id)
        #expect(try await store.savedTemplate(a.id) == nil)
        await #expect(throws: StoreError.itemNotFound) { try await store.renameSavedTemplate(a.id, to: "Gone") }
    }

    // MARK: - Schema v12

    @Test func aLibraryFromSchemaElevenKeepsEverythingAndCanSaveTemplates() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 11 { try raw.execute(migration.sql) }
        try raw.setUserVersion(11)
        let transform = #"{"crop":{"x":0,"y":0,"width":1,"height":1},"rotation":0,"filter":"original","brightness":0,"contrast":1}"#
        try raw.execute("""
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('n1', 'notebook', 'Journal', NULL, 0, 100, 100, NULL, 1, NULL);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p1', 'n1', 'V', 595.28, 841.89, 'template', NULL, NULL, 'lined', '\(transform)', 1, 100, 100);
            INSERT INTO bookmarks (id, page_id, name, created_at, modified_at) VALUES ('b1', 'p1', 'Start', 100, 100);
            """)
        raw.close()

        let store = try LibraryStore(directory: dir.url)

        // v12 brought templates; later versions keep them.
        #expect(try await store.schemaVersion() == Schema.latestVersion)
        let page = try #require(try await store.pages(of: ItemID(rawValue: "n1")).first)
        #expect(page.content == .template(.lined))
        #expect(try await store.bookmarks(of: ItemID(rawValue: "n1")).map(\.name) == ["Start"])
        #expect(try await store.savedTemplates().isEmpty)
        let template = try await store.saveTemplate(from: page.id, named: "Journal page")
        #expect(try await store.savedTemplates() == [template])
    }
}

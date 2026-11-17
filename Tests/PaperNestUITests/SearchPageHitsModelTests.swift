import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

/// The library's page hits and opening a document at a hit's page, as the
/// screens drive them.
@MainActor @Suite(.serialized) struct SearchPageHitsModelTests {
    private func ready() async throws -> (URL, LibrarySession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestHits-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        _ = try #require(session.environment)
        return (root, session)
    }

    /// Template pages, so automatic recognition never reads them and the
    /// seeded words are the only ones; `texts[i]` is page i's.
    private func document(_ store: LibraryStore, _ name: String, kind: ItemKind = .document,
                          _ texts: [String?]) async throws -> (ItemID, [Page]) {
        let item = try await store.createItem(kind: kind, name: name, pages: texts.map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let pages = try await store.pages(of: item.id)
        for (page, text) in zip(pages, texts) {
            guard let text else { continue }
            try await store.saveRecognition(PageRecognition(
                pageID: page.id, sourceRevision: page.revision, engineVersion: "test", status: .completed,
                languages: ["en-US"], lines: [RecognizedLine(text: text, box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.03),
                                                             confidence: 0.9)]))
        }
        return (item.id, pages)
    }

    @Test func pageHitsFollowTheSearchAndOnlyTheDocumentsShown() async throws {
        let (root, session) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let (receipts, _) = try await document(store, "Receipts", [nil, "Invoice total 42"])
        let (notes, _) = try await document(store, "Notes", kind: .notebook, ["Invoice reminder"])
        let library = LibraryModel(session: session)

        library.searchText = "invoice"
        await library.reload()
        #expect(Set(library.pageHits.map(\.itemID)) == [receipts, notes])
        let receiptHit = try #require(library.pageHits.first { $0.itemID == receipts })
        #expect(receiptHit.pageNumber == 2)
        #expect(receiptHit.itemName == "Receipts")
        #expect(receiptHit.snippet.runs.contains { $0.isMatch && $0.text == "Invoice" })

        // A kind that leaves the notebook out leaves its hit out too.
        library.contentKind = .documents
        await library.reload()
        #expect(library.pageHits.map(\.itemID) == [receipts])

        // Not searching, no hits.
        library.searchText = ""
        await library.reload()
        #expect(library.pageHits.isEmpty)
    }

    @Test func hitsAreInTheDocumentListsOrder() async throws {
        let (root, session) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let (zebra, _) = try await document(store, "Zebra", ["Invoice Z"])
        let (alpha, _) = try await document(store, "Alpha", ["Invoice A", "Invoice A2"])
        let library = LibraryModel(session: session)
        // The sort is a preference; leave it as other tests expect to find it.
        let previousSort = UserDefaults.standard.object(forKey: "librarySort")
        defer { UserDefaults.standard.set(previousSort, forKey: "librarySort") }
        library.sortOrder = .name
        library.searchText = "invoice"

        await library.reload()

        #expect(library.items.map(\.id) == [alpha, zebra])
        #expect(library.pageHits.map(\.itemID) == [alpha, alpha, zebra])
        #expect(library.pageHits.map(\.pageNumber) == [1, 2, 1])
    }

    /// Searching inside a folder: the folder's document is the oldest, and
    /// twenty-five newer documents elsewhere match on three pages each — more
    /// than the sixty hits allowed. The folder's page must still be listed.
    @Test func aFoldersHitsAreNotCrowdedOutByDocumentsElsewhere() async throws {
        let (root, session) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let folder = try await store.createFolder(named: "Taxes")
        let item = try await store.createItem(kind: .document, name: "Old return", folderID: folder.id, pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: "test", status: .completed,
            languages: ["en-US"], lines: [RecognizedLine(text: "Invoice from last year",
                                                         box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.03),
                                                         confidence: 0.9)]))
        for index in 0..<25 { _ = try await document(store, "Newer \(index)", ["Invoice a", "Invoice b", "Invoice c"]) }
        let library = LibraryModel(session: session)
        library.sidebarSelection = .folder(folder.id)
        library.searchText = "invoice"

        await library.reload()

        #expect(library.items.map(\.id) == [item.id])
        #expect(library.pageHits.map(\.pageID) == [page.id], "the folder's page was crowded out")
    }

    /// The document is not open yet: the request waits for its first load.
    @Test func aDocumentOpenedFromAHitShowsThatPage() async throws {
        let (root, session) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let (id, pages) = try await document(store, "Long", [nil, nil, "Invoice on three"])
        let library = LibraryModel(session: session)

        library.open(id, at: pages[2].id)
        let document = DocumentModel(itemID: id, session: session)
        document.applyPageRequest()  // before the first load: kept for it
        await document.load()

        #expect(document.selectedPageID == pages[2].id)
        #expect(session.pageRequest == nil, "shown once, then forgotten")
    }

    /// The document is already open on another page, as in an iPad tab.
    @Test func anOpenDocumentGoesToTheRequestedPageAndOthersIgnoreIt() async throws {
        let (root, session) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let (id, pages) = try await document(store, "Open", [nil, nil, "Invoice"])
        let (otherID, _) = try await document(store, "Other", ["Unrelated"])
        let open = DocumentModel(itemID: id, session: session)
        await open.load()
        let other = DocumentModel(itemID: otherID, session: session)
        await other.load()
        #expect(open.selectedPageID == pages[0].id)

        session.requestPage(pages[2].id, in: id)
        other.applyPageRequest()
        #expect(session.pageRequest != nil, "another document's window must not take it")
        open.applyPageRequest()

        #expect(open.selectedPageID == pages[2].id)
        #expect(session.pageRequest == nil)
    }
}

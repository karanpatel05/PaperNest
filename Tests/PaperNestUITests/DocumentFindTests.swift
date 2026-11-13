import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Find in a document, as the find bar drives it: what is counted, which hit
/// is the current one, and what moving between them does.
@MainActor @Suite struct DocumentFindTests {
    private func library() -> (URL, LibraryStore)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestFind-\(UUID().uuidString)", isDirectory: true)
        return (try? LibraryStore(directory: url)).map { (url, $0) }
    }

    private func document(_ pages: [String], in store: LibraryStore) async throws -> [Page] {
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: pages), name: "Report"))
        return try await store.pages(of: item.id)
    }

    @Test func hitsAreCountedAcrossThePagesInOrder() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget and budget", "Nothing here", "Final budget"], in: store)
        let find = DocumentFind()

        await find.index(pages, with: PageRenderer(store: store))
        find.query = "BUDGET"

        #expect(find.hits.map(\.pageID) == [pages[0].id, pages[0].id, pages[2].id])
        #expect(find.currentIndex == 0)
        #expect(find.hits(on: pages[0].id).count == 2)
        #expect(find.hits(on: pages[1].id).isEmpty)
        #expect(!find.isIndexing)
    }

    /// Typing before the pages have been read is the ordinary case: the bar
    /// opens with the keyboard up.
    @Test func aQueryTypedBeforeThePagesWereReadIsAnsweredOnceTheyAre() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Budget again"], in: store)
        let find = DocumentFind()
        find.query = "budget"
        #expect(find.hits.isEmpty)

        await find.index(pages, with: PageRenderer(store: store))

        #expect(find.hits.count == 2)
        #expect(find.currentIndex == 0)
    }

    /// Someone on page 3 who searches wants what is in front of them first,
    /// not to be thrown back to page 1.
    @Test func theFirstCurrentHitIsOnOrAfterThePageBeingRead() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Nothing", "Budget", "Budget"], in: store)
        let find = DocumentFind()
        await find.index(pages, with: PageRenderer(store: store))

        find.anchorPageID = pages[1].id
        find.query = "budget"

        #expect(find.current?.pageID == pages[2].id)
        #expect(find.currentIndex == 1)
    }

    @Test func nextAndPreviousWrapAround() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Budget", "Budget"], in: store)
        let find = DocumentFind()
        await find.index(pages, with: PageRenderer(store: store))
        find.query = "budget"
        let asked = find.focusRequest

        find.next()
        #expect(find.currentIndex == 1)
        find.next()
        find.next()
        #expect(find.currentIndex == 0, "next did not wrap from the last hit to the first")
        find.previous()
        #expect(find.currentIndex == 2, "previous did not wrap from the first hit to the last")
        #expect(find.focusRequest == asked + 4, "moving to a hit did not ask for it to be shown")
    }

    @Test func aQueryWithNoHitsHasNoCurrentHitAndMovingDoesNothing() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget"], in: store)
        let find = DocumentFind()
        await find.index(pages, with: PageRenderer(store: store))

        find.query = "zebra"
        find.next()
        find.previous()

        #expect(find.hits.isEmpty)
        #expect(find.currentIndex == nil)
        #expect(find.hasSearchableText)
    }

    /// The count must not jump back to "1 of n" every time another page of a
    /// long document finishes being read.
    @Test func readingMorePagesKeepsTheHitTheReaderIsOn() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Budget", "Budget"], in: store)
        let renderer = PageRenderer(store: store)
        let find = DocumentFind()
        await find.index(Array(pages[1...]), with: renderer)
        find.query = "budget"
        find.next()
        let held = try #require(find.current)
        #expect(held.pageID == pages[2].id)

        // The whole document, with an earlier page now ahead of that hit.
        await find.index(pages, with: renderer)

        #expect(find.hits.count == 3)
        #expect(find.current == held)
        #expect(find.currentIndex == 2)
    }

    /// A page that changed is read again; one that did not is not.
    @Test func aPageIsReadAgainOnlyWhenItChanged() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await document(["Budget", "Plain"], in: store)
        let renderer = PageRenderer(store: store)
        let find = DocumentFind()
        await find.index(pages, with: renderer)
        find.query = "budget"
        #expect(find.hits.count == 1)
        #expect(find.pagesRead == 2)

        pages[1] = try await store.placeText("New budget line", on: pages[1].id,
                                             frame: CGRect(x: 80, y: 400, width: 200, height: 30), fontSize: 14,
                                             color: .black, alignment: .leading).page
        await find.index(pages, with: renderer)

        #expect(find.hits.map(\.pageID) == [pages[0].id, pages[1].id])
        #expect(find.pagesRead == 3, "an unchanged page was read again, or the changed one was not")
    }

    /// A deleted page takes its hits with it.
    @Test func hitsOnAPageThatLeftTheDocumentGoWithIt() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Budget"], in: store)
        let renderer = PageRenderer(store: store)
        let find = DocumentFind()
        await find.index(pages, with: renderer)
        find.query = "budget"
        find.next()

        await find.index([pages[0]], with: renderer)

        #expect(find.hits.map(\.pageID) == [pages[0].id])
        #expect(find.currentIndex == 0)
    }

    /// A scan nobody has run recognition on has nothing to search, and the
    /// bar says that instead of "No Results" — which would read as "the word
    /// is not in this document".
    @Test func aDocumentWithNoTextAtAllSaysSo() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.scannedPDF(pages: 2), name: "Scan"))
        let pages = try await store.pages(of: item.id)
        let find = DocumentFind()

        await find.index(pages, with: PageRenderer(store: store))
        find.query = "budget"

        #expect(!find.hasSearchableText)
        #expect(find.status == .noText)
    }

    @Test func theStatusFollowsTheSearch() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget", "Budget"], in: store)
        let find = DocumentFind()
        #expect(find.status == .idle)

        await find.index(pages, with: PageRenderer(store: store))
        find.query = "budget"
        #expect(find.status == .hit(1, of: 2))
        find.next()
        #expect(find.status == .hit(2, of: 2))
        find.query = "zebra"
        #expect(find.status == .noResults)
        find.query = "   "
        #expect(find.status == .idle)
    }

    /// Closing the bar takes the highlights off the page but keeps what was
    /// typed, so opening it again carries on.
    @Test func closingKeepsTheQuery() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await document(["Budget"], in: store)
        let find = DocumentFind()
        find.isPresented = true
        await find.index(pages, with: PageRenderer(store: store))
        find.query = "budget"

        find.close()

        #expect(!find.isPresented)
        #expect(find.query == "budget")
        #expect(find.hits.count == 1)
    }
}

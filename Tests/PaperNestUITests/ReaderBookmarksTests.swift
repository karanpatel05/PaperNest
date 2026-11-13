import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The editor's bookmarks: what the list shows after each thing a reader can
/// do, read back from the library every time.
@MainActor @Suite struct ReaderBookmarksTests {
    private struct Library {
        let url: URL
        let session: LibrarySession
        let store: LibraryStore
        let item: PaperNestCore.LibraryItem
        var pages: [Page]
    }

    private func makeLibrary(pages texts: [String] = ["One", "Two", "Three"]) async throws -> Library {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestBookmarks-\(UUID().uuidString)", isDirectory: true)
        let session = LibrarySession(libraryURL: url)
        await session.bootstrap()
        let environment = try #require(session.environment)
        let item = try await environment.importer
            .importItem(.data(SyntheticDocuments.textPDF(pages: texts), name: "Report"))
        return Library(url: url, session: session, store: environment.store, item: item,
                       pages: try await environment.store.pages(of: item.id))
    }

    private func opened(_ library: Library) async -> ReaderBookmarks {
        let bookmarks = ReaderBookmarks()
        bookmarks.attach(to: library.item.id, in: library.session)
        await bookmarks.load()
        return bookmarks
    }

    @Test func markingThePageBeingReadPutsItInTheListAndInTheLibrary() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        #expect(bookmarks.bookmarks.isEmpty)
        #expect(!bookmarks.isBookmarked(library.pages[1].id))

        await bookmarks.toggle(on: library.pages[1].id)

        #expect(bookmarks.bookmarks.map(\.pageID) == [library.pages[1].id])
        #expect(bookmarks.isBookmarked(library.pages[1].id))
        #expect(!bookmarks.isBookmarked(library.pages[0].id))
        #expect(try await library.store.bookmarks(of: library.item.id) == bookmarks.bookmarks)
        #expect(!bookmarks.isShowingFailure)
    }

    @Test func markingAMarkedPageTakesTheMarkAway() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        await bookmarks.toggle(on: library.pages[0].id)
        await bookmarks.toggle(on: library.pages[2].id)

        await bookmarks.toggle(on: library.pages[0].id)

        #expect(bookmarks.bookmarks.map(\.pageID) == [library.pages[2].id])
        #expect(try await library.store.bookmarks(of: library.item.id).count == 1)
    }

    /// Unnamed, a bookmark is called by its page's number — the number the
    /// page has now, not the one it had when it was marked.
    @Test func anUnnamedBookmarkIsCalledByWhereItsPageIsNow() async throws {
        var library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        await bookmarks.toggle(on: library.pages[0].id)
        let bookmark = try #require(bookmarks.bookmarks.first)
        #expect(ReaderBookmarks.title(of: bookmark, in: library.pages) == "Page 1")

        try await library.store.movePage(library.pages[0].id, toIndex: 2)
        library.pages = try await library.store.pages(of: library.item.id)
        await bookmarks.load()

        let moved = try #require(bookmarks.bookmarks.first)
        #expect(ReaderBookmarks.title(of: moved, in: library.pages) == "Page 3")
    }

    @Test func aNamedBookmarkKeepsItsNameAndStillSaysItsPage() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        await bookmarks.toggle(on: library.pages[1].id)

        await bookmarks.rename(try #require(bookmarks.bookmarks.first), to: "  The figures ")

        let named = try #require(bookmarks.bookmarks.first)
        #expect(named.name == "The figures")
        #expect(ReaderBookmarks.title(of: named, in: library.pages) == "The figures")
        #expect(ReaderBookmarks.pageTitle(of: named, in: library.pages) == "Page 2")
        #expect(try await library.store.bookmarks(of: library.item.id).first?.name == "The figures")

        // An empty name goes back to the page number.
        await bookmarks.rename(named, to: "")
        #expect(ReaderBookmarks.title(of: try #require(bookmarks.bookmarks.first), in: library.pages) == "Page 2")
    }

    @Test func theListIsInPageOrderHoweverThePagesWereMarked() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)

        await bookmarks.toggle(on: library.pages[2].id)
        await bookmarks.toggle(on: library.pages[0].id)
        await bookmarks.toggle(on: library.pages[1].id)

        #expect(bookmarks.bookmarks.map(\.pageID) == library.pages.map(\.id))
    }

    /// Every other window showing this document reloads on the session's
    /// change token; a bookmark has to move it like any other saved change.
    @Test func aSavedChangeIsAnnouncedToOtherWindows() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        let other = await opened(library)
        let before = library.session.changeToken

        await bookmarks.toggle(on: library.pages[0].id)

        #expect(library.session.changeToken != before)
        await other.load()
        #expect(other.bookmarks == bookmarks.bookmarks)
    }

    /// The page was deleted in another window after this one drew its menu.
    @Test func aPageThatHasGoneCannotBeMarkedAndTheReaderIsTold() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        try await library.store.deletePages([library.pages[1].id])

        await bookmarks.toggle(on: library.pages[1].id)

        #expect(bookmarks.isShowingFailure)
        #expect(bookmarks.bookmarks.isEmpty)
    }

    @Test func aBookmarkWhosePageIsDeletedLeavesTheListAndComesBackOnUndo() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)
        await bookmarks.toggle(on: library.pages[1].id)

        let deleted = try await library.store.deletePages([library.pages[1].id])
        await bookmarks.load()
        #expect(bookmarks.bookmarks.isEmpty)

        try await library.store.restorePages(deleted)
        await bookmarks.load()
        #expect(bookmarks.bookmarks.map(\.pageID) == [library.pages[1].id])
    }

    @Test func withNoPageThereIsNothingToMark() async throws {
        let library = try await makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.url) }
        let bookmarks = await opened(library)

        await bookmarks.toggle(on: nil)

        #expect(bookmarks.bookmarks.isEmpty)
        #expect(!bookmarks.isShowingFailure)
        #expect(bookmarks.bookmark(on: nil) == nil)
    }
}

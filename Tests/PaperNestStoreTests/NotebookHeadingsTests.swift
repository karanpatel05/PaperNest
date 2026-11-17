import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// A new page's headings are written with it, in one transaction, as typed
/// text: undo and redo bring back exactly them, and they are findable.
@Suite struct NotebookHeadingsTests {
    private let headings = [TextBox(frame: CGRect(x: 40, y: 34, width: 300, height: 18), text: "Meeting", fontSize: 13, isBold: true),
                            TextBox(frame: CGRect(x: 40, y: 88, width: 150, height: 14), text: "Attendees", fontSize: 10)]

    private func texts(_ store: LibraryStore, _ pageID: PageID) async throws -> [String] {
        try await store.objects(on: pageID).compactMap { if case .text(let box) = $0.payload { box.text } else { nil } }
    }

    @Test func aNewPagesHeadingsAreWrittenWithItAndSurviveUndoAndRedo() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Minutes", pages: [
            .init(sourceSize: LibraryStore.notebookPageSize, content: .template(.lined))
        ], assets: [])
        let first = try #require(try await store.pages(of: book.id).first)

        let change = try await store.addNotebookPage(.meeting, to: book.id, after: first.id, headings: headings)

        #expect(change.page.content == .template(.meeting))
        #expect(try await texts(store, change.page.id) == ["Meeting", "Attendees"], "in the order given")
        #expect(try await store.search("attendees") == [book.id], "a heading is typed text, and findable")

        let undone = try await store.toggleNotebookPage(change)
        #expect(try await store.pages(of: book.id).count == 1)
        #expect(try await store.search("attendees").isEmpty, "a deleted page's words stop answering")
        _ = try await store.toggleNotebookPage(undone)
        #expect(try await store.pages(of: book.id).count == 2)
        #expect(try await texts(store, change.page.id) == ["Meeting", "Attendees"], "redo brings back the headings, once")
    }

    @Test func aNewNotebooksFirstPageHasItsHeadings() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)

        let book = try await store.createNotebook(named: "Week", folderID: nil, template: .planner, headings: headings)

        #expect(book.kind == .notebook)
        let pages = try await store.pages(of: book.id)
        #expect(pages.count == 1 && pages[0].content == .template(.planner))
        #expect(pages[0].sourceSize == LibraryStore.notebookPageSize)
        #expect(try await texts(store, pages[0].id) == ["Meeting", "Attendees"])
    }

    @Test func aPageWithoutHeadingsHasNoObjects() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createNotebook(named: "Plain", folderID: nil, template: .dotted)
        let page = try #require(try await store.pages(of: book.id).first)
        #expect(try await store.objects(on: page.id).isEmpty)
        let change = try await store.addNotebookPage(.cornell, to: book.id, after: page.id)
        #expect(try await store.objects(on: change.page.id).isEmpty)
    }

    /// Every paper, the new ones included, is stored and read back as itself.
    @Test func everyPaperIsStoredAndReadBack() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        for template in PageTemplate.allCases {
            let book = try await store.createNotebook(named: template.rawValue, folderID: nil, template: template)
            #expect(try await store.pages(of: book.id).first?.content == .template(template))
        }
    }
}

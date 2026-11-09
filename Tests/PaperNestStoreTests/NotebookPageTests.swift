import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct NotebookPageTests {
    @Test func continuationKeepsPaperGeometryButDoesNotCopyWritingAndRejectsStaleTail() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let transform = PageTransform(rotation: .clockwise90)
        let book = try await store.createItem(kind: .notebook, name: "Continue", pages: [
            .init(sourceSize: CGSize(width: 420, height: 600), content: .template(.grid), transform: transform)
        ], assets: [])
        let tail = try #require(try await store.pages(of: book.id).last)
        let mark = PageObject(pageID: tail.id, zKey: "V", payload: .text(.init(frame: .zero, text: "Keep here")), modifiedAt: Date())
        try await store.saveObject(mark)
        let latest = try #require(try await store.pages(of: book.id).last)
        let change = try await store.appendNotebookPage(matching: latest)
        #expect(change.page.content == .template(.grid))
        #expect(change.page.sourceSize == latest.sourceSize)
        #expect(change.page.transform == latest.transform)
        #expect(try await store.objects(on: change.page.id).isEmpty)
        await #expect(throws: StoreError.notebookPageChanged) { try await store.appendNotebookPage(matching: latest) }
        #expect(try await store.pages(of: book.id).count == 2)
        let undone = try await store.toggleNotebookPage(change)
        #expect(try await store.pages(of: book.id).count == 1)
        _ = try await store.toggleNotebookPage(undone)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.pages(of: book.id).last == change.page)
        #expect(try await reopened.objects(on: latest.id) == [mark])
    }

    @Test(arguments: PageTemplate.allCases)
    func insertsAfterSelectionAndRestoresIdentity(_ template: PageTemplate) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Book", pages: [], assets: [])
        let first = try await store.addNotebookPage(template, to: book.id, after: nil)
        let last = try await store.addNotebookPage(.blank, to: book.id, after: nil)
        let middle = try await store.addNotebookPage(template, to: book.id, after: first.page.id)
        #expect(try await store.pages(of: book.id).map(\.id) == [first.page.id, middle.page.id, last.page.id])
        #expect(middle.page.content == .template(template))
        #expect(middle.page.sourceSize == CGSize(width: 595.28, height: 841.89))
        let hidden = try await store.toggleNotebookPage(middle)
        #expect(try await store.pages(of: book.id).map(\.id) == [first.page.id, last.page.id])
        let restored = try await store.toggleNotebookPage(hidden)
        #expect(restored.page == middle.page)
        let again = try await store.toggleNotebookPage(restored)
        _ = try await store.toggleNotebookPage(again)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.pages(of: book.id).map(\.id) == [first.page.id, middle.page.id, last.page.id])
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func rejectsInvalidParentsAndAnchorsWithoutWrites() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Book", pages: [], assets: [])
        let document = try await store.createItem(kind: .document, name: "PDF", pages: [], assets: [])
        let other = try await store.createItem(kind: .notebook, name: "Other", pages: [], assets: [])
        let foreign = try await store.addNotebookPage(.grid, to: other.id, after: nil)
        await #expect(throws: StoreError.self) { try await store.addNotebookPage(.blank, to: document.id, after: nil) }
        await #expect(throws: StoreError.self) { try await store.addNotebookPage(.blank, to: book.id, after: foreign.page.id) }
        _ = try await store.toggleNotebookPage(foreign)
        await #expect(throws: StoreError.self) { try await store.addNotebookPage(.blank, to: other.id, after: foreign.page.id) }
        try await store.moveToRecentlyDeleted([book.id])
        await #expect(throws: StoreError.self) { try await store.addNotebookPage(.blank, to: book.id, after: nil) }
        #expect(try await store.pages(of: book.id).isEmpty)
        #expect(try await store.pages(of: document.id).isEmpty)
    }

    @Test func undoPreservesAnotherWindowsEdits() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Book", pages: [], assets: [])
        let change = try await store.addNotebookPage(.lined, to: book.id, after: nil)
        let mark = PageObject(pageID: change.page.id, zKey: "V", payload: .text(.init(frame: .zero, text: "Other window")), modifiedAt: Date())
        try await store.saveObject(mark)
        await #expect(throws: StoreError.self) { try await store.toggleNotebookPage(change) }
        #expect(try await store.page(change.page.id) != nil)
        #expect(try await store.objects(on: change.page.id) == [mark])
    }

    @Test func redoRejectsChangedOrderDeletedParentAndPurgedPage() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Book", pages: [], assets: [])
        let change = try await store.addNotebookPage(.grid, to: book.id, after: nil)
        let hidden = try await store.toggleNotebookPage(change)
        _ = try await store.addNotebookPage(.blank, to: book.id, after: nil)
        await #expect(throws: StoreError.self) { try await store.toggleNotebookPage(hidden) }
        try await store.moveToRecentlyDeleted([book.id])
        await #expect(throws: StoreError.self) { try await store.toggleNotebookPage(hidden) }
        _ = try await store.purgeDeletedPages()
        await #expect(throws: StoreError.self) { try await store.toggleNotebookPage(hidden) }
    }
}

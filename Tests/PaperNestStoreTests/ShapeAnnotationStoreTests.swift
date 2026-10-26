import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct ShapeAnnotationStoreTests {
    @Test func insertionRejectsStaleOrDeletedPageAndPersistsOneStroke() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Shapes", pages: [], assets: [])
        let page = try await store.addNotebookPage(.blank, to: item.id, after: nil).page
        let result = try await store.addShape(to: page, kind: .rectangle, start: .init(x: 0.2, y: 0.2), end: .init(x: 0.8, y: 0.8), color: .black, width: 2)
        #expect(result.objects.count == 1)
        #expect(try await store.objects(on: page.id) == result.objects)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.addShape(to: page, kind: .line, start: .zero, end: .init(x: 1, y: 1), color: .black, width: 2)
        }
        try await store.moveToRecentlyDeleted([item.id])
        await #expect(throws: StoreError.pageNotFound) {
            try await store.addShape(to: result.page, kind: .line, start: .zero, end: .init(x: 1, y: 1), color: .black, width: 2)
        }
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.objects(on: page.id) == result.objects)
    }
}

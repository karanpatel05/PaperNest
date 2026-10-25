import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct InkEditTests {
    @Test func guardedInkChangesAllowUnrelatedEditsAndRejectConflictsAtomically() async throws {
        let dir = TempDirectory(), store = try LibraryStore(directory: dir.url)
        let (page, objects) = try await seed(store)
        let (otherPage, otherObjects) = try await seed(store)
        var changed = objects[1]; changed.zKey = "Z"
        try await store.saveObject(changed)
        let before = try await store.objects(on: page.id)
        let revision = try #require(try await store.page(page.id)?.revision)
        var replacement = objects[0]; replacement.zKey = "Y"
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.applyInkChanges(on: page.id, saving: [replacement], replacing: [objects[0]], deleting: [objects[1]])
        }
        // An absent-on-this-page ID must not steal an object from another page.
        var foreignID = otherObjects[0]; foreignID.pageID = page.id
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.applyInkChanges(on: page.id, saving: [foreignID], replacing: [], deleting: [objects[0]])
        }
        #expect(try await store.objects(on: page.id) == before)
        #expect(try await store.objects(on: otherPage.id) == otherObjects)
        #expect(try await store.page(page.id)?.revision == revision)
        // Object-level guards let an undo coexist with changes to other marks.
        let updated = try await store.applyInkChanges(on: page.id, saving: [replacement], replacing: [objects[0]], deleting: [])
        #expect(updated.revision == revision + 1)
        let after = try await store.objects(on: page.id)
        #expect(Set(after) == Set([replacement, changed, objects[2]]))
        #expect(try await store.search("Searchable").contains(page.itemID))
    }

    private func seed(_ store: LibraryStore) async throws -> (Page, [PageObject]) {
        let item = try await store.createItem(kind: .document, name: "Synthetic ink", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        let ink = InkStroke(tool: .pen, color: .black, width: 3, points: [InkPoint(x: 60, y: 80), InkPoint(x: 300, y: 80)])
        let objects = [PageObject(pageID: page.id, zKey: "A", payload: .ink(ink), modifiedAt: Date()),
                       PageObject(pageID: page.id, zKey: "B", payload: .ink(ink), modifiedAt: Date()),
                       PageObject(pageID: page.id, zKey: "C", payload: .text(.init(frame: CGRect(x: 1, y: 1, width: 30, height: 10), text: "Keep")), modifiedAt: Date())]
        let updated = try await store.applyObjectChanges(on: page.id, saving: objects, deleting: [])
        try await store.saveRecognition(.init(pageID: page.id, sourceRevision: updated.revision, engineVersion: "test", status: .completed,
            languages: ["en"], lines: [.init(text: "Searchable", box: .exact(x: 0.1, y: 0.1, width: 0.4, height: 0.03), confidence: 1)]))
        return (updated, try await store.objects(on: page.id))
    }

    @Test func recolorAndRemovePersistWithoutChangingOtherObjectsOrOCR() async throws {
        let dir = TempDirectory(), green = RGBAColor(red: 0, green: 0.65, blue: 0.2)
        let store = try LibraryStore(directory: dir.url)
        let (page, objects) = try await seed(store)
        let colored = try await store.editInk(on: page.id, expectedRevision: page.revision, objects: [objects[0]], edit: .recolor(green))
        #expect(colored.previous == [objects[0]])
        #expect(colored.page.revision == page.revision + 1)
        guard case .ink(let stroke) = colored.saved[0].payload, case .ink(let old) = objects[0].payload else { Issue.record("Expected ink"); return }
        #expect(stroke.color == green)
        #expect(stroke.points == old.points && stroke.width == old.width && stroke.tool == old.tool)
        #expect(colored.saved[0].id == objects[0].id && colored.saved[0].zKey == objects[0].zKey)
        let removed = try await store.editInk(on: page.id, expectedRevision: colored.page.revision, objects: colored.saved, edit: .remove)
        #expect(removed.previous == colored.saved && removed.saved.isEmpty)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.objects(on: page.id) == Array(objects.dropFirst()))
        #expect(try await reopened.recognition(for: page.id)?.sourceRevision == removed.page.revision)
        #expect(try await reopened.search("Searchable") == [page.itemID])
    }

    @Test func staleOrInvalidSelectionsNeverPartiallyChangeInk() async throws {
        let dir = TempDirectory(), store = try LibraryStore(directory: dir.url)
        let (page, objects) = try await seed(store)
        let blue = RGBAColor(red: 0, green: 0.2, blue: 1)
        var changed = objects[1]; changed.zKey = "Z"
        for selection in [[objects[0], changed], [objects[0], objects[2]]] {
            await #expect(throws: StoreError.pageObjectsChanged) {
                try await store.editInk(on: page.id, expectedRevision: page.revision, objects: selection, edit: .remove)
            }
        }
        for selection in [[], [objects[0], objects[0]]] {
            await #expect(throws: StoreError.invalidOrder) {
                try await store.editInk(on: page.id, expectedRevision: page.revision, objects: selection, edit: .recolor(blue))
            }
        }
        await #expect(throws: TextMarkupError.invalidColor) {
            try await store.editInk(on: page.id, expectedRevision: page.revision, objects: [objects[0]], edit: .recolor(.init(red: -1, green: 0, blue: 0)))
        }
        #expect(try await store.objects(on: page.id) == objects)
        #expect(try await store.page(page.id)?.revision == page.revision)
        let rotated = try await store.updateTransform(page.id, to: .init(rotation: .clockwise90))
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.editInk(on: page.id, expectedRevision: page.revision, objects: [objects[0]], edit: .remove)
        }
        #expect(try await store.page(page.id)?.revision == rotated.revision)
        #expect(try await store.objects(on: page.id) == objects)
    }

    @Test func foreignPageAndDeletedDocumentCannotBeEdited() async throws {
        let dir = TempDirectory(), store = try LibraryStore(directory: dir.url)
        let (page, objects) = try await seed(store)
        let (_, other) = try await seed(store)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.editInk(on: page.id, expectedRevision: page.revision, objects: [objects[0], other[0]], edit: .remove)
        }
        try await store.moveToRecentlyDeleted([page.itemID])
        await #expect(throws: StoreError.pageNotFound) {
            try await store.editInk(on: page.id, expectedRevision: page.revision, objects: [objects[0]], edit: .remove)
        }
        #expect(try await store.objects(on: page.id) == objects)
    }
}

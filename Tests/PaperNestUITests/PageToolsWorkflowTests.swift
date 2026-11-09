import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct PageToolsWorkflowTests {
    @Test func duplicateUndoRedoAndReopenKeepEditableObjects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PageTools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let item = try await env.store.createItem(kind: .document, name: "Pages", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let original = try #require(model.selectedPage)
        _ = try await model.saveInlineText(.init(frame: CGRect(x: 10, y: 10, width: 100, height: 50), text: "Retained"), replacing: nil, on: original, undoManager: nil)
        await session.backgroundTextWork?.value
        await model.load()
        let undo = UndoManager()
        try await model.duplicateSelectedPage(undoManager: undo)
        let copy = try #require(model.selectedPage)
        #expect(copy.id != original.id && model.pages.count == 2)
        let copiedObjects = try await env.store.objects(on: copy.id)
        #expect(copiedObjects.count == 1)
        undo.undo(); undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2 && model.selectedPageID == copy.id)
        #expect(try await env.store.objects(on: copy.id) == copiedObjects)
        undo.undo()
        try await settled(model)
        #expect(model.pages.map(\.id) == [original.id])
        undo.redo()
        try await settled(model)
        let reopened = DocumentModel(itemID: item.id, session: session)
        await reopened.load()
        #expect(reopened.pages.map(\.id) == [original.id, copy.id])
        #expect(try await env.store.objects(on: copy.id) == copiedObjects)
        #expect(model.presentedError == nil)
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<200 {
            if !model.isChangingNotebookPage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Page history did not settle")
    }
}

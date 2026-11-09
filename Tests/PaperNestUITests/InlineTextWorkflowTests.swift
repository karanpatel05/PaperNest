import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct InlineTextWorkflowTests {
    @Test func inlineCreationUpdateDeletionUndoRedoAndReopenKeepExactDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Inline", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let page = try #require(model.selectedPage)
        let undo = UndoManager()
        undo.groupsByEvent = false
        var draft = TextBox(frame: CGRect(x: 31, y: 77, width: 210, height: 123), text: "  First\n",
            fontSize: 23, color: RGBAColor(red: 0.8, green: 0.1, blue: 0.2), alignment: .trailing,
            fontFamily: .serif, isBold: true, isItalic: true)
        undo.beginUndoGrouping()
        let original = try await model.saveInlineText(draft, replacing: nil, on: page, undoManager: undo)
        undo.endUndoGrouping()
        #expect(original.payload == .text(draft))
        draft.text = "  Second\nLine\n"
        draft.frame = CGRect(x: 90, y: 140, width: 270, height: 180)
        draft.fontSize = 32
        draft.fontFamily = .monospaced
        draft.isItalic = false
        undo.beginUndoGrouping()
        let edited = try await model.saveInlineText(draft, replacing: original, on: page, undoManager: undo)
        undo.endUndoGrouping()
        #expect(edited.id == original.id && edited.zKey == original.zKey)
        #expect(edited.payload == .text(draft))
        undo.undo()
        try await settled(model)
        #expect(try await env.store.objects(on: page.id) == [original])
        undo.redo()
        try await settled(model)
        #expect(try await env.store.objects(on: page.id) == [edited])
        undo.beginUndoGrouping()
        try await model.deleteInlineText(edited, undoManager: undo)
        undo.endUndoGrouping()
        #expect(try await env.store.objects(on: page.id).isEmpty)
        undo.undo()
        try await settled(model)
        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        await reopened.loadSelectedPageObjects()
        #expect(reopened.selectedPageObjects == [edited])
        #expect(model.presentedError == nil)
    }

    @Test func conflictingUpdateAndDeleteNeverOverwriteAnotherWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Conflict", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let page = try #require(model.selectedPage)
        var draft = TextBox(frame: CGRect(x: 20, y: 30, width: 200, height: 100), text: "First")
        let original = try await model.saveInlineText(draft, replacing: nil, on: page, undoManager: nil)
        let (_, other) = try await env.store.updateText(original, text: "Other window", frame: draft.frame,
            fontSize: 30, color: .black, alignment: .center, fontFamily: .serif, isBold: true)
        draft.text = "My unsaved draft"
        let undo = UndoManager()
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await model.saveInlineText(draft, replacing: original, on: page, undoManager: undo)
        }
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await model.deleteInlineText(original, undoManager: undo)
        }
        #expect(try await env.store.objects(on: page.id) == [other])
        #expect(!undo.canUndo)
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

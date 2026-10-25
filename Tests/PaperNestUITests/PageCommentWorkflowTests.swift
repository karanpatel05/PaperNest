import Foundation
import PDFKit
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct PageCommentWorkflowTests {
    @Test func commentsEditDeleteUndoReopenAndStayOutOfExports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Comments", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let pageID = try #require(model.selectedPageID)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.setComment(on: pageID, replacing: nil, text: "Private draft", undoManager: undo)
        undo.endUndoGrouping()
        var note = try #require(try await model.comments(on: pageID).first)
        undo.beginUndoGrouping()
        try await model.setComment(on: pageID, replacing: note, text: "Private revision", undoManager: undo)
        undo.endUndoGrouping()
        note = try #require(try await model.comments(on: pageID).first)
        undo.beginUndoGrouping()
        try await model.setComment(on: pageID, replacing: note, text: nil, undoManager: undo)
        undo.endUndoGrouping()
        #expect(try await model.comments(on: pageID).isEmpty)
        undo.undo()
        undo.redo()
        undo.undo()
        try await settled(model)
        #expect(try await model.comments(on: pageID).first?.commentText == "Private revision")
        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        #expect(try await reopened.comments(on: pageID).first?.commentText == "Private revision")
        let output = try await env.exporter.export(itemName: "Comments", pages: model.pages, options: .init(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(pdf.pageCount == 1)
        #expect(!(pdf.string ?? "").contains("Private"))
        #expect(pdf.page(at: 0)?.annotations.isEmpty == true)
    }

    @Test func conflictingUndoKeepsOtherWindowComment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Comments", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let pageID = try #require(model.selectedPageID)
        let undo = UndoManager()
        try await model.setComment(on: pageID, replacing: nil, text: "Original", undoManager: undo)
        let note = try #require(try await model.comments(on: pageID).first)
        _ = try await env.store.setPageComment(on: pageID, replacing: note, text: "Other window")
        undo.undo()
        try await settled(model)
        #expect(try await model.comments(on: pageID).first?.commentText == "Other window")
        #expect(model.presentedError != nil)
        #expect(!undo.canUndo && !undo.canRedo)
    }

    @Test func commentUndoDoesNotInvalidateEarlierPageInsertion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let id = try await LibraryModel(session: session).createNotebook(named: "Mixed", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.addNotebookPage(.lined, after: model.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()
        let pageID = try #require(model.selectedPageID)
        undo.beginUndoGrouping()
        try await model.setComment(on: pageID, replacing: nil, text: "Comment", undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 1)
        #expect(model.presentedError == nil)
        undo.redo()
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2)
        #expect(try await model.comments(on: pageID).first?.commentText == "Comment")
    }

    @Test func conflictingDraftCanBeSavedAsNewWithoutLosingEitherText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Drafts", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let pageID = try #require(model.selectedPageID)
        try await model.setComment(on: pageID, replacing: nil, text: "Original", undoManager: nil)
        let original = try #require(try await model.comments(on: pageID).first)
        let draft = PageCommentDraft(model: model, pageID: pageID, original: original, undoManager: nil)
        draft.text = "My unsaved draft"
        _ = try await env.store.setPageComment(on: pageID, replacing: original, text: "Other window")
        #expect(await draft.save() == false)
        #expect(draft.text == "My unsaved draft")
        #expect(draft.canSaveAsNew)
        #expect(await draft.save(asNew: true))
        #expect(try await model.comments(on: pageID).compactMap(\.commentText) == ["Other window", "My unsaved draft"])
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

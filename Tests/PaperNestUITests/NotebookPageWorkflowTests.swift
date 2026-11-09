import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct NotebookPageWorkflowTests {
    @Test func scrollingAppendSelectsMatchingBlankPageAndCanUndoRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let id = try await LibraryModel(session: session).createNotebook(named: "Scroll", template: .lined)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let first = try #require(model.selectedPageID)
        let undo = UndoManager()
        try await model.appendNotebookPage(after: first, undoManager: undo)
        let added = try #require(model.selectedPageID)
        #expect(added != first)
        #expect(model.pages.count == 2)
        #expect(model.selectedPage?.content == .template(.lined))
        try await model.appendNotebookPage(after: first, undoManager: undo)
        #expect(model.pages.count == 2)
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 1)
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2)
        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        #expect(reopened.pages == model.pages)
    }

    @Test func insertionUndoRedoAndExportSurviveReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let library = LibraryModel(session: session)
        let id = try await library.createNotebook(named: "Notebook", template: .lined)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let first = try #require(model.selectedPageID)
        let undo = UndoManager()
        try await model.addNotebookPage(.grid, after: first, undoManager: undo)
        let inserted = try #require(model.selectedPageID)
        #expect(model.pages.count == 2)
        #expect(model.selectedPage?.content == .template(.grid))
        undo.undo()
        try await settled(model)
        #expect(model.pages.map(\.id) == [first])
        #expect(undo.canRedo)
        undo.redo()
        try await settled(model)
        #expect(model.selectedPageID == inserted)
        #expect(model.pages.map(\.id) == [first, inserted])
        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        #expect(reopened.pages == model.pages)
        let output = try await env.exporter.export(itemName: "Notebook", pages: model.pages, options: .init(format: .pdf))
        defer { output.removeTemporaryFiles() }
        #expect(PDFDocument(url: output.files[0])?.pageCount == 2)
    }

    @Test func immediateNativeUndoRedoPreservesPageAndHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let id = try await LibraryModel(session: session).createNotebook(named: "Rapid history", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        try await model.addNotebookPage(.lined, after: model.selectedPageID, undoManager: undo)
        let inserted = try #require(model.selectedPageID)
        undo.undo()
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2)
        #expect(model.selectedPageID == inserted)
        #expect(undo.canUndo)
        #expect(model.presentedError == nil)
        undo.undo()
        undo.redo()
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 1)
        #expect(undo.canRedo)
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2)
    }

    @Test func rapidMixedDeleteAndNotebookHistoryStaysOrdered() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let id = try await LibraryModel(session: session).createNotebook(named: "Mixed history", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.addNotebookPage(.lined, after: model.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        await model.deleteSelectedPage(undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        undo.undo()
        undo.redo()
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 1)
        #expect(model.presentedError == nil)
        #expect(undo.canUndo)
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 2)
    }

    @Test func newDeletionWaitsForPendingNotebookHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let id = try await LibraryModel(session: session).createNotebook(named: "New edit", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.addNotebookPage(.lined, after: model.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        undo.redo()
        undo.beginUndoGrouping()
        await model.deleteSelectedPage(undoManager: undo)
        undo.endUndoGrouping()
        try await settled(model)
        #expect(model.pages.count == 1)
        #expect(model.presentedError == nil)
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 2)
    }

    @Test(arguments: [false, true]) func conflictingUndoKeepsOtherWindowsPageAndClearsHistory(queueRedo: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Notebook", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        try await model.addNotebookPage(.lined, after: model.selectedPageID, undoManager: undo)
        let page = try #require(model.selectedPage)
        var transform = page.transform
        transform.rotation = .init(rawValue: 1)!
        _ = try await env.store.updateTransform(page.id, to: transform)
        undo.undo()
        if queueRedo { undo.redo() }
        try await settled(model)
        #expect(model.pages.count == 2)
        #expect(model.selectedPage?.transform == transform)
        #expect(model.presentedError != nil)
        #expect(!undo.canUndo && !undo.canRedo)
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isChangingNotebookPage)
    }
}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Saved templates through the document's model: saved from one document,
/// offered in another, a page made from one undoable like any added page.
@MainActor @Suite(.serialized) struct SavedTemplateWorkflowTests {
    @Test func aTemplateSavedInOneNotebookMakesPagesInAnother() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let library = LibraryModel(session: session, startsAtHome: true)
        let sourceID = try await library.createNotebook(named: "Planning", template: .meeting)
        let targetID = try await library.createNotebook(named: "Q3", template: .blank)

        let source = DocumentModel(itemID: sourceID, session: session)
        await source.load()
        try await source.saveTemplate(from: try #require(source.selectedPageID), named: "Team meeting")
        #expect(source.savedTemplates.map(\.name) == ["Team meeting"])

        let target = DocumentModel(itemID: targetID, session: session)
        await target.load()
        let template = try #require(target.savedTemplates.first, "offered in another notebook")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await target.addNotebookPage(fromTemplate: template.id, after: target.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()

        #expect(target.pages.count == 2)
        let made = try #require(target.pages.last)
        #expect(made.content == .template(.meeting))
        #expect(try await store.objects(on: made.id).count == 5, "the meeting's headings came with it")
        #expect(target.selectedPageID == made.id)
        #expect(undo.canUndo)

        try await target.renameSavedTemplate(template.id, to: "Weekly sync")
        #expect(target.savedTemplates.map(\.name) == ["Weekly sync"])
        try await target.deleteSavedTemplate(template.id)
        #expect(target.savedTemplates.isEmpty)
        #expect(try await store.pages(of: targetID).count == 2, "a page made from it stays")
    }
}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Writing a speaker note from the document: committed when the call
/// returns, one undo step back, redo forward, and nothing registered when
/// nothing changed.
@MainActor @Suite(.serialized) struct SpeakerNoteModelTests {
    private func notebook() async throws -> (DocumentModel, Page) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session)
        let id = try await library.createNotebook(named: "Talk", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        return (model, try #require(model.selectedPage))
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }

    @Test func aNoteIsSavedAndUndoAndRedoWalkIt() async throws {
        let (model, page) = try await notebook()
        let undo = UndoManager()

        await model.setSpeakerNote("Open with the chart", on: page.id, undoManager: undo)
        #expect(await model.speakerNote(on: page.id) == "Open with the chart")
        #expect(await model.speakerNotes() == [page.id: "Open with the chart"])
        await model.setSpeakerNote("Open with the numbers", on: page.id, undoManager: undo)

        undo.undo()
        try await settled(model)
        #expect(await model.speakerNote(on: page.id) == "Open with the chart")
        undo.undo()
        try await settled(model)
        #expect(await model.speakerNote(on: page.id) == "", "undone back to no note")
        undo.redo()
        try await settled(model)
        #expect(await model.speakerNote(on: page.id) == "Open with the chart")
    }

    @Test func nothingChangedRegistersNothing() async throws {
        let (model, page) = try await notebook()
        let undo = UndoManager()
        await model.setSpeakerNote("   ", on: page.id, undoManager: undo)
        #expect(!undo.canUndo, "blank text on a page with no note changes nothing")
        await model.setSpeakerNote("Same", on: page.id, undoManager: undo)
        while undo.canUndo { undo.removeAllActions() }
        await model.setSpeakerNote("Same", on: page.id, undoManager: undo)
        #expect(!undo.canUndo, "the same text again changes nothing")
    }
}

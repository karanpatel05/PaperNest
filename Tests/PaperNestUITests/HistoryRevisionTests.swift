import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// The editor's Undo and Redo buttons read `UndoManager.canUndo` and
/// `canRedo`, which are **not** observable SwiftUI state, so the row that
/// holds them only re-reads them when one of its own inputs changes.
///
/// Drawing a stroke changed none of them. The undo was registered from inside
/// a `Task`, so no `NSUndoManagerDidCloseUndoGroup` reached the row either,
/// and it went on showing the state from *before* the stroke: **Undo greyed
/// out on the mark someone had just drawn**, and Redo lit with nothing to
/// redo. Driven by hand in the Mac app before this was written — ⌘Z still
/// undid the stroke the button refused, which is what placed the fault in the
/// row rather than in the history.
///
/// `historyRevision` is the input the row was missing: the model says when it
/// has touched the undo stack, because the model is the only thing that knows.
@MainActor @Suite(.serialized) struct HistoryRevisionTests {
    private func notebook() async throws -> (DocumentModel, Page) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session)
        let id = try await library.createNotebook(named: "Notebook", template: .lined)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        return (model, try #require(model.selectedPage))
    }

    private func stroke() -> InkStroke {
        InkStroke(tool: .pen, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), width: 2,
                  points: [InkPoint(x: 10, y: 10), InkPoint(x: 90, y: 10)])
    }

    /// Drawing has to be visible to the row, or Undo stays greyed on it.
    @Test func drawingAdvancesTheHistoryRevision() async throws {
        let (model, page) = try await notebook()
        let undo = UndoManager()
        let before = model.historyRevision

        try await model.addInkStroke(stroke(), to: page, undoManager: undo)

        #expect(undo.canUndo, "nothing was registered, so this tests the wrong thing")
        #expect(model.historyRevision != before, "the row has no way to know the stroke happened")
    }

    /// Erasing and moving go through their own calls; each has to say so too.
    @Test func erasingAndMovingAdvanceItAsWell() async throws {
        let (model, page) = try await notebook()
        let undo = UndoManager()
        try await model.addInkStroke(stroke(), to: page, undoManager: undo)
        let drawn = try #require(model.selectedPageObjects.first { object in
            if case .ink = object.payload { return true }
            return false
        })

        let afterDrawing = model.historyRevision
        try await model.moveInk([drawn.id], on: page, by: CGPoint(x: 5, y: 5), undoManager: undo)
        let afterMoving = model.historyRevision
        #expect(afterMoving != afterDrawing, "a move is invisible to the row")

        let moved = try #require(model.selectedPageObjects.first { $0.id == drawn.id })
        try await model.eraseInk([moved], on: page, undoManager: undo)
        #expect(model.historyRevision != afterMoving, "an erase is invisible to the row")
    }

    /// Undoing already reached the row through `NSUndoManagerDidUndoChange`,
    /// so this is not the bug — but the revision must not go *backwards* and
    /// leave the row keyed to a value it has already drawn.
    @Test func undoingAdvancesItFurtherStill() async throws {
        let (model, page) = try await notebook()
        let undo = UndoManager()
        try await model.addInkStroke(stroke(), to: page, undoManager: undo)
        let afterDrawing = model.historyRevision

        undo.undo()
        try await settled(model)

        #expect(model.historyRevision > afterDrawing)
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isChangingNotebookPage)
    }
}

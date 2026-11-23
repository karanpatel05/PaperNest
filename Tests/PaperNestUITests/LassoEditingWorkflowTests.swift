import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The lasso's editing actions as the overlay calls them: each one saved
/// before it returns, each one a single undo step, and each one refused whole
/// when what it was started on has changed.
@MainActor @Suite(.serialized) struct LassoEditingWorkflowTests {
    @Test func deleteAfterAMoveTakesTheMovedMarksAndUndoPutsBothStepsBack() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undo = grouped()
        try await step(undo) {
            try await fixture.model.moveSelection(fixture.objects, on: fixture.page, by: CGPoint(x: 30, y: 10),
                                                  undoManager: undo)
        }
        let moved = try await fixture.store.objects(on: fixture.page.id)
        // The overlay holds the selection by id and reads it back after a
        // move, so Delete is given the moved marks and the page as it now is.
        let page = try #require(fixture.model.selectedPage)
        #expect(fixture.model.selectedPageObjects == moved)
        try await step(undo) {
            try await fixture.model.deleteSelection(fixture.model.selectedPageObjects, on: page, undoManager: undo)
        }
        #expect(try await fixture.store.objects(on: page.id).isEmpty)
        #expect(undo.undoActionName == L10n.selectionDelete)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: page.id) == moved)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: page.id) == fixture.objects)
        #expect(fixture.model.presentedError == nil)
    }

    @Test func duplicateLaysCopiesAsideAndOneUndoTakesThemAway() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undo = grouped()
        var copies: [PageObject] = []
        try await step(undo) {
            copies = try await fixture.model.duplicateSelection(fixture.objects, on: fixture.page, undoManager: undo)
        }
        #expect(copies.count == 3)
        #expect(Set(copies.map(\.id)).isDisjoint(with: fixture.objects.map(\.id)))
        let stored = try await fixture.store.objects(on: fixture.page.id)
        #expect(stored.map(\.id) == fixture.objects.map(\.id) + copies.map(\.id), "copies go on top, in order")
        guard case .ink(let ink) = copies[0].payload, case .ink(let original) = fixture.objects[0].payload,
              case .text(let box) = copies[1].payload, case .text(let originalBox) = fixture.objects[1].payload else {
            Issue.record("Copies keep their kinds"); return
        }
        #expect(ink.points.map(\.x) == original.points.map { $0.x + 20 })
        #expect(box.frame == originalBox.frame.offsetBy(dx: 20, dy: 20))
        #expect(box.text == originalBox.text && box.fontSize == originalBox.fontSize)
        #expect(undo.undoActionName == L10n.selectionDuplicate)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        undo.redo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == stored)
    }

    @Test func cutThenPasteMovesMarksToAnotherPageInTheSamePlace() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        MarkupClipboard.shared.clear()
        defer { MarkupClipboard.shared.clear() }
        let undo = grouped()
        try await step(undo) {
            try await fixture.model.cutSelection(fixture.objects, on: fixture.page, undoManager: undo)
        }
        #expect(try await fixture.store.objects(on: fixture.page.id).isEmpty)
        #expect(MarkupClipboard.shared.content?.objects == fixture.objects)
        #expect(undo.undoActionName == L10n.selectionCut)

        let second = try #require(fixture.model.pages.last)
        var pasted: [PageObject] = []
        try await step(undo) { pasted = try await fixture.model.paste(on: second, undoManager: undo) }
        #expect(pasted.map(\.payload) == fixture.objects.map(\.payload), "same place, same marks")
        #expect(pasted.allSatisfy { $0.pageID == second.id })
        #expect(try await fixture.store.objects(on: second.id) == pasted)
        // The picture is shared, not lost, and still has its bytes.
        guard case .image(let picture) = pasted[2].payload else { Issue.record("still a picture"); return }
        #expect(try await fixture.store.isAssetReferenced(picture.assetID))
        #expect(undo.undoActionName == L10n.selectionPaste)

        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: second.id).isEmpty)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        #expect(fixture.model.presentedError == nil)
    }

    @Test func pastingWhereTheOriginalsStillLieMovesTheCopyAside() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        MarkupClipboard.shared.clear()
        defer { MarkupClipboard.shared.clear() }
        fixture.model.copySelection([fixture.objects[1]], on: fixture.page)
        let pasted = try await fixture.model.paste(on: fixture.page, undoManager: nil)
        guard case .text(let box) = pasted.first?.payload, case .text(let original) = fixture.objects[1].payload else {
            Issue.record("a text box was pasted"); return
        }
        #expect(box.frame == original.frame.offsetBy(dx: 20, dy: 20))
        // With nothing copied there is nothing to paste, and nothing is written.
        MarkupClipboard.shared.clear()
        let page = try #require(fixture.model.selectedPage)
        #expect(try await fixture.model.paste(on: page, undoManager: nil).isEmpty)
        #expect(try await fixture.store.page(page.id) == page)
    }

    @Test func recolourChangesOnlyTheInkInAMixedSelection() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undo = grouped()
        let green = RGBAColor(red: 0.1, green: 0.6, blue: 0.2)
        try await step(undo) {
            try await fixture.model.recolorSelection(fixture.objects, to: green, on: fixture.page, undoManager: undo)
        }
        let stored = try await fixture.store.objects(on: fixture.page.id)
        guard case .ink(let ink) = stored[0].payload else { Issue.record("still ink"); return }
        #expect(ink.color == green)
        #expect(stored[1].payload == fixture.objects[1].payload)
        #expect(stored[2].payload == fixture.objects[2].payload)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
    }

    @Test func resizeGrowsEveryKindAndUndoShrinksItBack() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undo = grouped()
        let bounds = try #require(SelectionEdits.pageBounds(of: fixture.objects, in: fixture.page.geometry))
        try await step(undo) {
            try await fixture.model.scaleSelection(fixture.objects, on: fixture.page, by: 1.2, about: bounds.origin,
                                                   undoManager: undo)
        }
        let stored = try await fixture.store.objects(on: fixture.page.id)
        #expect(stored.map(\.id) == fixture.objects.map(\.id))
        guard case .text(let box) = stored[1].payload, case .text(let original) = fixture.objects[1].payload else {
            Issue.record("still a text box"); return
        }
        #expect(abs(box.fontSize - original.fontSize * 1.2) < 1e-9)
        let grown = try #require(SelectionEdits.pageBounds(of: stored, in: fixture.page.geometry))
        #expect(abs(grown.width - bounds.width * 1.2) < 1e-6)
        #expect(undo.undoActionName == L10n.selectionResize)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
    }

    @Test func rotateTurnsInkAndRefusesASelectionWithATextBox() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(DocumentModel.canRotate([fixture.objects[0]]))
        #expect(!DocumentModel.canRotate(fixture.objects))
        await #expect(throws: StoreError.invalidPlacement) {
            try await fixture.model.rotateSelection(fixture.objects, on: fixture.page, by: .pi / 2, undoManager: nil)
        }
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        let undo = grouped()
        try await step(undo) {
            try await fixture.model.rotateSelection([fixture.objects[0]], on: fixture.page, by: .pi / 2, undoManager: undo)
        }
        let stored = try await fixture.store.objects(on: fixture.page.id)
        #expect(stored[0].id == fixture.objects[0].id)
        #expect(stored[0].payload != fixture.objects[0].payload)
        #expect(Array(stored.dropFirst()) == Array(fixture.objects.dropFirst()))
        #expect(undo.undoActionName == L10n.selectionRotate)
        undo.undo(); try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
    }

    @Test func aSelectionChangedElsewhereRefusesEveryEdit() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // Another window moves the text box after the lasso picked it up.
        _ = try await fixture.store.updateText(fixture.objects[1], text: "Other window",
            frame: CGRect(x: 10, y: 10, width: 180, height: 70), fontSize: 21, color: .black, alignment: .leading)
        let after = try await fixture.store.objects(on: fixture.page.id)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.deleteSelection(fixture.objects, on: fixture.page, undoManager: nil)
        }
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.scaleSelection(fixture.objects, on: fixture.page, by: 1.5, about: .zero, undoManager: nil)
        }
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.duplicateSelection(fixture.objects, on: fixture.page, undoManager: nil)
        }
        #expect(try await fixture.store.objects(on: fixture.page.id) == after)
    }

    // MARK: - Fixture

    private struct Fixture {
        let root: URL
        let store: LibraryStore
        let model: DocumentModel
        let page: Page
        let objects: [PageObject]
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LassoEditing-\(UUID())")
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let store = try #require(library.environment?.store)
        let item = try await store.createItem(kind: .notebook, name: "Lasso", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let ink = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .pen,
            color: RGBAColor(red: 0.2, green: 0.4, blue: 0.6), width: 3,
            points: [.init(x: 50, y: 80, widthScale: 0.6, time: 0), .init(x: 100, y: 120, widthScale: 1.4, time: 0.35)])),
            modifiedAt: Date())
        try await store.saveObject(ink)
        _ = try await store.placeText("Lasso words", on: page.id, frame: CGRect(x: 120, y: 160, width: 180, height: 70),
                                      fontSize: 21, color: .black, alignment: .leading)
        let image = try store.assets.store(SyntheticDocuments.image(width: 100, height: 60, type: .png),
                                           kind: .png, originalFilename: nil)
        _ = try await store.placeImage(image, on: page.id, frame: CGRect(x: 300, y: 300, width: 100, height: 60))
        await model.load()
        await model.loadSelectedPageObjects()
        return Fixture(root: root, store: store, model: model, page: try #require(model.selectedPage),
                       objects: try await store.objects(on: page.id))
    }

    private func grouped() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func step(_ undo: UndoManager, _ work: () async throws -> Void) async throws {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        try await work()
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

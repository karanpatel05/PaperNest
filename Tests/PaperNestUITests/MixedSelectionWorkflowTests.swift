import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct MixedSelectionWorkflowTests {
    @Test func mixedMovePreservesPayloadsAndSurvivesOneUndoRedoAndReopen() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await fixture.model.moveSelection(fixture.objects, on: fixture.page,
                                              by: CGPoint(x: 35, y: -20), undoManager: undo)
        undo.endUndoGrouping()
        let moved = try await fixture.store.objects(on: fixture.page.id)
        #expect(moved.map(\.id) == fixture.objects.map(\.id))
        #expect(moved.map(\.zKey) == fixture.objects.map(\.zKey))
        guard case .ink(let ink) = moved[0].payload,
              case .text(let text) = moved[1].payload,
              case .image(let image) = moved[2].payload,
              case .image(let originalImage) = fixture.objects[2].payload else {
            Issue.record("Mixed selection must keep every object kind"); return
        }
        #expect(ink.points == [.init(x: 85, y: 60, widthScale: 0.6, time: 0),
                               .init(x: 135, y: 100, widthScale: 1.8, time: 0.35)])
        #expect(ink.width == 4 && ink.tool == .highlighter)
        #expect(ink.color == RGBAColor(red: 0.2, green: 0.4, blue: 0.6))
        #expect(text == TextBox(frame: CGRect(x: 155, y: 140, width: 180, height: 70),
                               text: "  Styled text\n", fontSize: 21,
                               color: RGBAColor(red: 0.7, green: 0.1, blue: 0.3),
                               alignment: .trailing, fontFamily: .serif, isBold: true, isItalic: true))
        #expect(image.frame == CGRect(x: 335, y: 280, width: 100, height: 60))
        #expect(image.assetID == originalImage.assetID)
        #expect(fixture.model.selectedPage?.revision == fixture.page.revision + 1)
        #expect(undo.canUndo && undo.undoActionName == L10n.moveObject)
        undo.undo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        #expect(!undo.canUndo && undo.canRedo)
        undo.redo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == moved)
        let reopened = try LibraryStore(directory: fixture.root)
        #expect(try await reopened.objects(on: fixture.page.id) == moved)
        #expect(fixture.model.presentedError == nil)
    }

    @Test func staleObjectRefusesWholeMoveEvenWithCurrentPageSnapshot() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let (page, _) = try await fixture.store.updateText(fixture.objects[1], text: "Other window",
            frame: CGRect(x: 120, y: 160, width: 180, height: 70), fontSize: 21,
            color: .black, alignment: .leading)
        let before = try await fixture.store.objects(on: page.id)
        // Refreshing model state must never substitute newer objects for the
        // exact selection the gesture started with.
        await fixture.model.loadSelectedPageObjects()
        let undo = UndoManager()
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.moveSelection(fixture.objects, on: page,
                                                   by: CGPoint(x: 30, y: 20), undoManager: undo)
        }
        #expect(try await fixture.store.objects(on: page.id) == before)
        #expect(try await fixture.store.page(page.id) == page)
        #expect(!undo.canUndo)
    }

    @Test(arguments: [false, true]) func stalePageGeometryRefusesWholeMove(rotated: Bool) async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var transform = fixture.page.transform
        if rotated { transform.rotation = .clockwise90 }
        else { transform.crop = NormalizedRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7) }
        let changed = try await fixture.store.updateTransform(fixture.page.id, to: transform)
        let undo = UndoManager()
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.moveSelection(fixture.objects, on: fixture.page,
                                                   by: CGPoint(x: 30, y: 20), undoManager: undo)
        }
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        #expect(try await fixture.store.page(fixture.page.id) == changed)
        #expect(!undo.canUndo)
    }

    @Test func nonfiniteDeltaAndUnsupportedObjectsNeverPartiallyMove() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await #expect(throws: StoreError.invalidPlacement) {
            try await fixture.model.moveSelection(fixture.objects, on: fixture.page,
                                                   by: CGPoint(x: Double.nan, y: 1), undoManager: nil)
        }
        let comment = PageObject(pageID: fixture.page.id, zKey: "z", payload: .comment("Private"), modifiedAt: Date())
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await fixture.model.moveSelection(fixture.objects + [comment], on: fixture.page,
                                                   by: CGPoint(x: 10, y: 10), undoManager: nil)
        }
        #expect(try await fixture.store.objects(on: fixture.page.id) == fixture.objects)
        #expect(try await fixture.store.page(fixture.page.id) == fixture.page)
    }

    private struct Fixture {
        let root: URL
        let store: LibraryStore
        let model: DocumentModel
        let page: Page
        let objects: [PageObject]
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MixedSelection-\(UUID())")
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let store = try #require(library.environment?.store)
        let item = try await store.createItem(kind: .notebook, name: "Mixed selection", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let ink = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .highlighter,
            color: RGBAColor(red: 0.2, green: 0.4, blue: 0.6), width: 4,
            points: [.init(x: 50, y: 80, widthScale: 0.6, time: 0),
                     .init(x: 100, y: 120, widthScale: 1.8, time: 0.35)])), modifiedAt: Date())
        try await store.saveObject(ink)
        _ = try await store.placeText("  Styled text\n", on: page.id,
            frame: CGRect(x: 120, y: 160, width: 180, height: 70), fontSize: 21,
            color: RGBAColor(red: 0.7, green: 0.1, blue: 0.3), alignment: .trailing,
            fontFamily: .serif, isBold: true, isItalic: true, preserveWhitespace: true)
        let image = try store.assets.store(SyntheticDocuments.image(width: 100, height: 60, type: .png),
                                           kind: .png, originalFilename: nil)
        _ = try await store.placeImage(image, on: page.id, frame: CGRect(x: 300, y: 300, width: 100, height: 60))
        await model.load()
        return Fixture(root: root, store: store, model: model, page: try #require(model.selectedPage),
                       objects: try await store.objects(on: page.id))
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

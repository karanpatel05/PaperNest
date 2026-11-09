import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

struct InkEraserTests {
    @Test func circularCutSplitsSparseStrokeAndPreservesStyle() {
        let ink = InkStroke(tool: .highlighter, color: .black, width: 4,
            points: [.init(x: 0, y: 100, time: 0), .init(x: 200, y: 100, time: 2)])
        let pieces = InkEraser.fragments(of: ink, path: [CGPoint(x: 100, y: 100)], diameter: 20)
        #expect(pieces.count == 2)
        #expect(abs((pieces.first?.points.last?.x ?? 0) - 88) < 0.001)
        #expect(abs((pieces.last?.points.first?.x ?? 0) - 112) < 0.001)
        #expect(pieces.allSatisfy { $0.tool == ink.tool && $0.color == ink.color && $0.width == ink.width })
        #expect(abs((pieces.first?.points.last?.time ?? 0) - 0.88) < 0.001)
    }

    @Test func fastSweepCutsBetweenSamplesAndLargerSizeErasesMore() {
        let ink = InkStroke(tool: .pen, color: .black, width: 2,
                            points: [.init(x: 0, y: 100), .init(x: 200, y: 100)])
        let path = [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 200)]
        let small = InkEraser.fragments(of: ink, path: path, diameter: 8)
        let large = InkEraser.fragments(of: ink, path: path, diameter: 48)
        #expect(small.count == 2 && large.count == 2)
        #expect((small.first?.points.last?.x ?? 0) > (large.first?.points.last?.x ?? 0))
        #expect(InkEraser.fragments(of: ink, path: [CGPoint(x: 100, y: 180)], diameter: 48) == [ink])
    }

    @Test func roundBoundaryDoesNotEraseSquareCornersAndKeepsPressure() {
        let dot = InkStroke(tool: .pen, color: .black, width: 2, points: [.init(x: 9, y: 9)])
        #expect(InkEraser.fragments(of: dot, path: [.zero], diameter: 20) == [dot])
        #expect(InkEraser.fragments(of: dot, path: [.zero], diameter: 30).isEmpty)
        let ink = InkStroke(tool: .pen, color: .black, width: 4,
            points: [.init(x: 0, y: 0, widthScale: 0.5), .init(x: 100, y: 0, widthScale: 1.5)])
        let pieces = InkEraser.fragments(of: ink, path: [CGPoint(x: 50, y: 0)], diameter: 20)
        #expect(pieces.count == 2)
        #expect(pieces.first?.points.first?.widthScale == 0.5)
        #expect(pieces.last?.points.last?.widthScale == 1.5)
        #expect(InkEraser.fragments(of: ink, path: [], diameter: 20) == [ink])
    }
}

@MainActor struct InkEraserWorkflowTests {
    @Test func partialEraseSurvivesUndoRedoAndReopeningAndRejectsStaleObjects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Eraser-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let item = try await store.createItem(kind: .notebook, name: "Erase", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let page = try #require(model.selectedPage)
        let original = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .pen,
            color: .black, width: 4, points: [.init(x: 100, y: 200), .init(x: 500, y: 200)])), modifiedAt: Date())
        try await store.saveObject(original)
        await model.load()
        let current = try #require(model.selectedPage)
        let undo = UndoManager(); undo.groupsByEvent = false; undo.beginUndoGrouping()
        try await model.eraseInk([original], on: current, path: [CGPoint(x: 300, y: 200)], diameter: 24,
                                 mode: .precision, undoManager: undo)
        undo.endUndoGrouping()
        let erased = try await store.objects(on: page.id)
        #expect(erased.count == 2)
        #expect(erased.first?.id == original.id)
        undo.undo(); for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try await store.objects(on: page.id) == [original])
        undo.redo(); for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try await store.objects(on: page.id) == erased)
        let reopened = try PaperNestStore.LibraryStore(directory: root)
        #expect(try await reopened.objects(on: page.id) == erased)
        await #expect(throws: (any Error).self) {
            try await model.eraseInk([original], on: current, path: [CGPoint(x: 200, y: 200)], diameter: 48,
                                     mode: .stroke, undoManager: undo)
        }
        #expect(try await store.objects(on: page.id) == erased)
    }
}

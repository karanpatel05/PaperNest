import CoreGraphics
import Foundation
import Testing
import SQLite3
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct SignatureWorkflowTests {
    @Test func reusableSignaturePlacesAsOneUndoStepAndSurvivesReopenAndExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "Signatures", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let draft = SignatureDraft(model: model, page: page)
        draft.name = "Everyday"
        draft.strokes = drawnStrokes
        #expect(await draft.saveReusable())
        let signature = try #require(draft.selected)
        #expect(signature.name == "Everyday")
        #expect(try await env.store.signatures() == [signature])
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(await draft.place(undoManager: undo))
        undo.endUndoGrouping()
        let objects = try await env.store.objects(on: page.id)
        #expect(objects.count == 2)
        undo.undo()
        try await settled(model)
        #expect(try await env.store.objects(on: page.id).isEmpty)
        undo.redo()
        try await settled(model)
        #expect(try await env.store.objects(on: page.id) == objects)
        let reopened = try LibraryStore(directory: root)
        #expect(try await reopened.signatures() == [signature])
        #expect(try await reopened.objects(on: page.id) == objects)
        let output = try await env.exporter.export(itemName: "Signatures", pages: model.pages, options: .init(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(CGPDFDocument(output.files[0] as CFURL))
        let pdfPage = try #require(pdf.page(at: 1))
        var pixels = [UInt8](repeating: 255, count: 600 * 850 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 600, height: 850,
                bitsPerComponent: 8, bytesPerRow: 600 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.drawPDFPage(pdfPage)
        }
        #expect(stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 100 }.count > 20)
        #expect(await draft.remove(signature))
        #expect(try await env.store.signatures().isEmpty)
        #expect(try await env.store.objects(on: page.id) == objects, "deleting a saved signature never erases placed ink")
    }

    @Test func stalePlacementRetainsSelectedSignatureAndCaptureForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "Conflict", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let draft = SignatureDraft(model: model, page: page)
        draft.name = "Keep this drawing"
        draft.strokes = drawnStrokes
        #expect(await draft.saveReusable())
        let selected = try #require(draft.selected)
        _ = try await env.store.placeText("Other window", on: page.id,
            frame: CGRect(x: 20, y: 20, width: 200, height: 80), fontSize: 14, color: .black, alignment: .leading)
        let undo = UndoManager()
        #expect(!(await draft.place(undoManager: undo)))
        #expect(draft.selected == selected && draft.name == "Keep this drawing")
        #expect(draft.strokes == drawnStrokes && draft.failed)
        #expect(try await env.store.objects(on: page.id).count == 1)
        #expect(!undo.canUndo)
        await draft.refreshPreview()
        #expect(!draft.pageChanged && !draft.failed)
        #expect(await draft.place(undoManager: undo))
        #expect(try await env.store.objects(on: page.id).count == 3)
        #expect(draft.selected == selected)
    }

    @Test func lockedDatabaseRetainsUnsavedDrawingAndRetrySavesItOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "Save retry", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let draft = SignatureDraft(model: model, page: try #require(model.selectedPage))
        draft.name = "Keep my drawing"
        draft.strokes = drawnStrokes
        var database: OpaquePointer?
        try #require(sqlite3_open_v2(root.appendingPathComponent(LibraryStore.databaseFilename).path,
            &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil); sqlite3_close(database) }
        try #require(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        #expect(!(await draft.saveReusable()))
        #expect(draft.name == "Keep my drawing" && draft.strokes == drawnStrokes)
        #expect(draft.failed && draft.selected == nil && draft.signatures.isEmpty)
        #expect(try await env.store.signatures().isEmpty)
        try #require(sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK)
        #expect(await draft.saveReusable())
        #expect(!draft.failed && draft.selected?.name == "Keep my drawing")
        #expect(try await env.store.signatures().count == 1)
    }

    @Test func visibleInkCanSaveWhenGestureEndsWithoutReleaseCallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "Interrupted signature", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let draft = SignatureDraft(model: model, page: try #require(model.selectedPage))
        draft.name = "Interrupted drawing"
        draft.capturePoints = [.init(x: 20, y: 60), .init(x: 160, y: 25)]
        // The canvas shows these points even when DragGesture never sends onEnded.
        let visibleInk = draft.capturedStroke
        #expect(!visibleInk.isEmpty)
        #expect(draft.canSave, "Visible named ink must not leave Save disabled")
        #expect(await draft.saveReusable())
        let saved = try #require(try await env.store.signatures().first)
        let expected = try #require(SavedSignature(name: draft.name, capturing: visibleInk))
        #expect(saved.strokes == expected.strokes)
        draft.finishCapture() // A late release must not append the same stroke twice.
        #expect(draft.strokes.count == 1)
        #expect(draft.capturePoints.isEmpty)
    }

    private var drawnStrokes: [InkStroke] {
        [InkStroke(tool: .pen, color: .black, width: 2,
                   points: [.init(x: 10, y: 20), .init(x: 70, y: 60), .init(x: 200, y: 15)]),
         InkStroke(tool: .pen, color: .black, width: 2,
                   points: [.init(x: 30, y: 70), .init(x: 210, y: 65)])]
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

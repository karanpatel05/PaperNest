import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct TextMarkupWorkflowTests {
    @Test(arguments: ["recolor", "remove", "restore"])
    func conflictingUndoNeverOverwritesAnotherWindowsInk(action: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InkConflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let item = try await store.createItem(kind: .document, name: "Two windows", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        let stroke = InkStroke(tool: .pen, color: .black, width: 3, points: [.init(x: 10, y: 10), .init(x: 100, y: 10)])
        try await store.saveObject(.init(pageID: page.id, zKey: "A", payload: .ink(stroke), modifiedAt: Date()))
        let original = try await store.objects(on: page.id)
        let first = DocumentModel(itemID: item.id, session: session)
        let second = DocumentModel(itemID: item.id, session: session)
        await first.load()
        let undo = UndoManager()
        let blue = RGBAColor(red: 0, green: 0, blue: 1), red = RGBAColor(red: 1, green: 0, blue: 0)
        try await first.editInk(on: try #require(first.selectedPage), objects: original,
                                edit: action == "recolor" ? .recolor(blue) : .remove, undoManager: undo)
        if action == "remove" {
            undo.undo()
            try await waitFor(first, objects: original)
        } else if action == "restore" {
            // A restore must not replace an ID that another window has reused.
            try await store.saveObject(original[0])
        }
        await second.load()
        let current = try await store.objects(on: page.id)
        try await second.editInk(on: try #require(second.selectedPage), objects: current, edit: .recolor(red), undoManager: nil)
        let otherWindowsMarks = second.selectedPageObjects
        let revision = second.selectedPage?.revision
        if action == "remove" { undo.redo() } else { undo.undo() }
        for _ in 0..<100 where first.presentedError == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(first.presentedError?.message == L10n.markupChanged)
        #expect(try await store.objects(on: page.id) == otherWindowsMarks)
        #expect(try await store.page(page.id)?.revision == revision)
        #expect(first.selectedPageObjects == otherWindowsMarks)
        #expect(!undo.canUndo && !undo.canRedo)
    }

    @Test func savedInkCanBeRecoloredRemovedAndUndoneWithoutLosingExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InkManager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let item = try await env.store.createItem(kind: .document, name: "Synthetic marks", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let page = try await env.store.pages(of: item.id)[0]
        let recognition = PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test", status: .completed,
            languages: ["en"], lines: [.init(text: "Retained text", box: .exact(x: 0.1, y: 0.2, width: 0.5, height: 0.04), confidence: 1)])
        try await env.store.saveRecognition(recognition)
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let undo = UndoManager(), green = RGBAColor(red: 0, green: 0.8, blue: 0), blue = RGBAColor(red: 0, green: 0, blue: 1)
        try await model.addTextMarkup(recognition, lineIndices: [0], style: .highlight, color: green, undoManager: undo)
        let originalMarks = model.selectedPageObjects
        try await model.editInk(on: try #require(model.selectedPage), objects: originalMarks, edit: .recolor(blue), undoManager: undo)
        let blueMarks = model.selectedPageObjects
        #expect(blueMarks[0].id == originalMarks[0].id)
        let result = try await env.exporter.export(itemName: "Blue", pages: [try #require(model.selectedPage)], options: .init(format: .pdf))
        defer { result.removeTemporaryFiles() }
        let rendered = try #require(PixelProbe.renderPDFPage(Data(contentsOf: result.files[0]), index: 0))
        let pixel = PixelProbe.pixel(rendered, x: 0.35, y: 0.22)
        #expect(pixel.b > 240 && pixel.r < 210 && pixel.g < 210, "Recolored mark missing: \(pixel)")
        try await model.editInk(on: try #require(model.selectedPage), objects: blueMarks, edit: .remove, undoManager: undo)
        #expect(model.selectedPageObjects.isEmpty)
        undo.undo()
        try await waitFor(model, objects: blueMarks)
        undo.undo()
        try await waitFor(model, objects: originalMarks)
        undo.redo()
        try await waitFor(model, objects: blueMarks)
        undo.redo()
        try await waitFor(model, objects: [])
        undo.undo()
        try await waitFor(model, objects: blueMarks)
        let reopened = LibrarySession(libraryURL: root)
        await reopened.bootstrap()
        let newStore = try #require(reopened.environment?.store)
        #expect(try await newStore.objects(on: page.id) == blueMarks)
        #expect(try await newStore.search("Retained") == [item.id])
    }

    private func waitFor(_ model: DocumentModel, objects: [PageObject]) async throws {
        for _ in 0..<100 where model.selectedPageObjects != objects { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.selectedPageObjects == objects)
    }

    @Test func markupUndoRedoReopenAndExportKeepSourceGeometry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TextMarkup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let item = try await env.store.createItem(kind: .document, name: "Marked", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let original = try await env.store.pages(of: item.id)[0]
        let page = try await env.store.updateTransform(original.id, to: .init(
            crop: .init(x: 0, y: 0.1, width: 0.8, height: 0.6), rotation: .clockwise90))
        let line = RecognizedLine(text: "Synthetic quarterly", box: .exact(x: 0.1, y: 0.2, width: 0.5, height: 0.04), confidence: 1)
        let recognition = PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
                                         status: .completed, languages: ["en"], lines: [line])
        try await env.store.saveRecognition(recognition)
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let undo = UndoManager()
        try await model.addTextMarkup(recognition, lineIndices: [0], style: .highlight, undoManager: undo)
        #expect(model.selectedPageObjects.count == 1)
        let objects = model.selectedPageObjects
        undo.undo()
        for _ in 0..<100 where !model.selectedPageObjects.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.selectedPageObjects.isEmpty)
        undo.redo()
        for _ in 0..<100 where model.selectedPageObjects.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.selectedPageObjects == objects)
        let reopenedSession = LibrarySession(libraryURL: root)
        await reopenedSession.bootstrap()
        let reopenedEnv = try #require(reopenedSession.environment)
        let reopened = try #require(try await reopenedEnv.store.page(page.id))
        #expect(try await reopenedEnv.store.objects(on: page.id) == objects)
        let result = try await reopenedEnv.exporter.export(itemName: "Marked", pages: [reopened], options: .init(format: .pdf))
        defer { result.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: result.files[0]))
        #expect(pdf.page(at: 0)?.string?.contains("Synthetic quarterly") == true)
        let rendered = try #require(PixelProbe.renderPDFPage(Data(contentsOf: result.files[0]), index: 0))
        let box = reopened.geometry.pageRect(forNormalizedSourceRect: line.box)
        let size = reopened.geometry.pageSize
        let pixel = PixelProbe.pixel(rendered, x: box.midX / size.width, y: box.midY / size.height)
        #expect(pixel.r > 240 && pixel.g > 210 && pixel.b < 210, "yellow mark missing at transformed OCR box: \(pixel)")
        #expect(PixelProbe.pixel(rendered, x: 0.05, y: 0.05).isWhite)
    }
}

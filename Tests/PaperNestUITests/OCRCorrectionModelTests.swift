import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// What the screens rely on when text is corrected: find reading the page
/// again, the OCR panel's account of a page, and the document's undo.
@MainActor @Suite(.serialized) struct OCRCorrectionModelTests {
    private func line(_ text: String, row: Int) -> RecognizedLine {
        RecognizedLine(text: text, box: .exact(x: 0.1, y: 0.1 + Double(row) * 0.05, width: 0.5, height: 0.02),
                       confidence: 0.5)
    }

    /// A template page carrying a recognition result: automatic recognition
    /// never reads a template page, so nothing in the background can replace
    /// the result while a test works with it.
    private func seededPage(_ store: LibraryStore, _ lines: [String]) async throws -> (ItemID, Page) {
        let item = try await store.createItem(kind: .notebook, name: "Receipt", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: TextRecognizer.engineVersion,
            status: .completed, languages: ["en-US"],
            lines: lines.enumerated().map { line($1, row: $0) }))
        return (item.id, page)
    }

    /// Find keeps each page's text until the page's revision moves, for as
    /// long as the document is open. The same `DocumentFind` reads the page
    /// before and after the correction here, so this fails if a correction
    /// ever stops moving the revision.
    @Test func findReadsACorrectedPageAgain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestOCRFix-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LibraryStore(directory: url)
        let (itemID, page) = try await seededPage(store, ["Invocie total 42"])
        let renderer = PageRenderer(store: store)
        let find = DocumentFind()

        await find.index(try await store.pages(of: itemID), with: renderer)
        find.query = "Invocie"
        #expect(find.hits.count == 1)

        let read = try #require(try await store.recognition(for: page.id))
        try await store.correctRecognition(on: page.id, expected: read, texts: ["Invoice total 42"])
        await find.index(try await store.pages(of: itemID), with: renderer)

        #expect(find.hits.isEmpty, "find went on answering the misread word from its cache")
        find.query = "Invoice"
        #expect(find.hits.count == 1)
    }

    /// The panel's account of the page on screen, and its warning before
    /// recognizing corrected pages again.
    @Test func thePanelSaysWhatThePageHoldsAndCountsCorrectedPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "States", pages: (0..<2).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let first = model.pages[0], second = model.pages[1]
        #expect(await model.recognitionState(of: first.id) == .none)

        try await env.store.saveRecognition(PageRecognition(
            pageID: first.id, sourceRevision: first.revision, engineVersion: TextRecognizer.engineVersion,
            status: .failed, languages: ["en-US"], lines: []))
        #expect(await model.recognitionState(of: first.id) == .failed)

        try await env.store.saveRecognition(PageRecognition(
            pageID: first.id, sourceRevision: first.revision, engineVersion: TextRecognizer.engineVersion,
            status: .completed, languages: ["en-US"], lines: [line("Teh total", row: 0)]))
        guard case .recognized(let read) = await model.recognitionState(of: first.id) else {
            Issue.record("a finished result was not reported as recognized"); return
        }
        #expect(read.correctedAt == nil)
        #expect(await model.correctedPageCount(among: [first.id, second.id]) == 0)

        let changed = try await model.correctRecognition(on: first.id, expected: read, texts: ["The total"],
                                                         undoManager: nil)
        #expect(changed)
        guard case .recognized(let corrected) = await model.recognitionState(of: first.id) else {
            Issue.record("a corrected result was not reported as recognized"); return
        }
        #expect(corrected.correctedAt != nil)
        #expect(await model.correctedPageCount(among: [first.id, second.id]) == 1)
        #expect(await model.correctedPageCount(among: [second.id]) == 0)

        // A page with text of its own is found by that text, so it is not
        // offered for correction.
        _ = try await env.store.indexEmbeddedText("Printed words", for: second.id, expecting: second.content)
        #expect(await model.recognitionState(of: second.id) == .ownText)
    }

    /// A correction is one step of the document's undo history, and the Undo
    /// buttons hear about it: it is registered from a Task, which the undo
    /// manager's own notifications do not cover.
    @Test func undoAndRedoGoThroughTheDocumentsHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let (itemID, page) = try await seededPage(env.store, ["Recieved"])
        let model = DocumentModel(itemID: itemID, session: session)
        await model.load()
        let read = try #require(try await env.store.recognition(for: page.id))
        let undo = UndoManager()
        undo.groupsByEvent = false
        let history = model.historyRevision

        undo.beginUndoGrouping()
        try await model.correctRecognition(on: page.id, expected: read, texts: ["Received"], undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.historyRevision != history, "the Undo buttons were not told")
        #expect(undo.canUndo)

        undo.undo()
        try await settled(model)
        #expect(try await env.store.recognition(for: page.id)?.lines.map(\.text) == ["Recieved"])
        #expect(try await env.store.recognition(for: page.id)?.correctedAt == nil)

        undo.redo()
        try await settled(model)
        #expect(try await env.store.recognition(for: page.id)?.lines.map(\.text) == ["Received"])
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}

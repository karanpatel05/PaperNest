import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Handwriting to text from the document: read on this device, the reviewed
/// words put on the page as one undo step, the ink kept or taken away, and
/// where the words go. The writing is synthetic single-stroke print
/// (`SyntheticHandwriting`), not anyone's real hand.
@MainActor @Suite(.serialized) struct HandwritingModelTests {
    private func notebook(writing: String = "hello") async throws -> (DocumentModel, LibraryStore, Page, [PageObject]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session)
        let id = try await library.createNotebook(named: "Journal", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let store = try #require(session.environment?.store)
        let page = try #require(model.selectedPage)
        var strokes: [PageObject] = []
        for (index, path) in try SyntheticHandwriting.strokes(writing, origin: CGPoint(x: 80, y: 200)).enumerated() {
            let object = PageObject(pageID: page.id, zKey: String(format: "K%03d", index), payload: .ink(InkStroke(
                tool: .pen, color: RGBAColor(red: 0.1, green: 0.15, blue: 0.55), width: 2.2,
                points: path.map { InkPoint(x: $0.x, y: $0.y) })), modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
            try await store.saveObject(object)
            strokes.append(object)
        }
        await model.load()
        await model.loadSelectedPageObjects()
        return (model, store, try #require(model.selectedPage), strokes)
    }

    /// Waits for an undo or redo, which the model commits in order, behind the call.
    private func until(_ model: DocumentModel, _ condition: ([PageObject]) -> Bool) async throws {
        for _ in 0..<200 where !condition(model.selectedPageObjects) {
            try await Task.sleep(for: .milliseconds(20))
            await model.loadSelectedPageObjects()
        }
        #expect(condition(model.selectedPageObjects), "objects now: \(model.selectedPageObjects.map(\.payload.kind))")
    }

    private func texts(_ objects: [PageObject]) -> [String] {
        objects.compactMap { if case .text(let box) = $0.payload { return box.text } else { return nil } }
    }

    private func inkCount(_ objects: [PageObject]) -> Int {
        objects.filter { $0.payload.kind == "ink" }.count
    }

    @Test func theSelectionIsReadAndNothingIsWritten() async throws {
        let (model, _, _, strokes) = try await notebook()
        let reading = try await model.readHandwriting(strokes)
        #expect(reading.strokes == strokes)
        #expect(reading.text.lowercased().filter(\.isLetter) == "hello", "read \(reading.text)")
        #expect(model.selectedPageObjects == strokes, "reading writes nothing")
    }

    /// Only pen ink is handwriting: a highlighter stroke or a text box in the
    /// selection is left out of the reading and left on the page.
    @Test func onlyPenInkIsRead() async throws {
        let (_, store, page, strokes) = try await notebook()
        let marker = PageObject(pageID: page.id, zKey: "Z1", payload: .ink(InkStroke(
            tool: .highlighter, color: .black, width: 12, points: [InkPoint(x: 80, y: 300), InkPoint(x: 300, y: 300)])),
                                modifiedAt: Date())
        try await store.saveObject(marker)
        let typed = try await store.placeText("Typed", on: page.id, frame: CGRect(x: 80, y: 400, width: 200, height: 40),
                                              fontSize: 14, color: .black, alignment: .leading).object
        #expect(DocumentModel.handwriting(in: strokes + [marker, typed]) == strokes)
        #expect(DocumentModel.handwriting(in: [marker, typed]).isEmpty)
    }

    @Test func keptHandwritingGetsTheWordsBelowItAndOneUndoTakesThemAway() async throws {
        let (model, _, _, strokes) = try await notebook()
        let undo = UndoManager()
        let reading = try await model.readHandwriting(strokes)

        let box = try await model.convertHandwriting(reading, to: "Hello, Ana", keepingInk: true, undoManager: undo)
        #expect(texts(model.selectedPageObjects) == ["Hello, Ana"], "the reviewed words, not the raw reading")
        #expect(inkCount(model.selectedPageObjects) == strokes.count)
        guard case .text(let text) = box.payload else { Issue.record("not a text box"); return }
        let ink = try #require(HandwritingRecognizer.bounds(of: strokes.compactMap {
            if case .ink(let s) = $0.payload { return s } else { return nil }
        }))
        #expect(text.frame.minY > ink.maxY, "below the handwriting: \(text.frame) under \(ink)")
        #expect(text.color == RGBAColor(red: 0.1, green: 0.15, blue: 0.55), "in the writing's colour")

        undo.undo()
        try await until(model) { texts($0).isEmpty && inkCount($0) == strokes.count }
        undo.redo()
        try await until(model) { texts($0) == ["Hello, Ana"] && inkCount($0) == strokes.count }
    }

    @Test func replacedHandwritingComesBackWithOneUndo() async throws {
        let (model, _, _, strokes) = try await notebook()
        let undo = UndoManager()
        let reading = try await model.readHandwriting(strokes)

        try await model.convertHandwriting(reading, to: "hello", keepingInk: false, undoManager: undo)
        #expect(texts(model.selectedPageObjects) == ["hello"])
        #expect(inkCount(model.selectedPageObjects) == 0)

        undo.undo()
        try await until(model) { texts($0).isEmpty && inkCount($0) == strokes.count }
        #expect(model.selectedPageObjects == strokes, "the strokes come back exactly as they were")
        undo.redo()
        try await until(model) { texts($0) == ["hello"] && inkCount($0) == 0 }
    }

    /// A stroke erased while the sheet was open: the words would describe ink
    /// that is gone, so nothing is written.
    @Test func handwritingChangedAfterReadingIsRefused() async throws {
        let (model, store, _, strokes) = try await notebook()
        let reading = try await model.readHandwriting(strokes)
        try await store.deleteObject(strokes[0].id)

        await #expect(throws: StoreError.pageObjectsChanged) {
            try await model.convertHandwriting(reading, to: "hello", keepingInk: false, undoManager: nil)
        }
        #expect(texts(model.selectedPageObjects).isEmpty)
        #expect(inkCount(model.selectedPageObjects) == strokes.count - 1)
    }

    // MARK: - Where the words go

    private let page = CGSize(width: 600, height: 800)
    private func line(height: Double) -> HandwritingRecognizer.Line {
        HandwritingRecognizer.Line(text: "x", confidence: 0.9, bounds: CGRect(x: 0, y: 0, width: 100, height: height))
    }

    @Test func replacedWordsTakeTheHandwritingsPlaceAtItsSize() {
        let ink = CGRect(x: 100, y: 300, width: 180, height: 40)
        let layout = DocumentModel.handwritingTextLayout(text: "hello", lines: [line(height: 30)], ink: ink,
                                                         keepingInk: false, pageSize: page)
        #expect(layout.frame.minX == 100)
        #expect(layout.frame.minY == 300)
        #expect(abs(layout.fontSize - 24) < 0.001, "from the line Vision read, not a fixed size: \(layout.fontSize)")
        #expect(layout.frame.width >= ink.width)
    }

    @Test func keptWordsGoBelowOrAboveWhenThereIsNoRoomBelow() {
        let low = CGRect(x: 100, y: 740, width: 180, height: 40)
        let kept = DocumentModel.handwritingTextLayout(text: "hello", lines: [line(height: 30)], ink: low,
                                                       keepingInk: true, pageSize: page)
        #expect(kept.frame.maxY <= low.minY, "no room below, so above: \(kept.frame)")
        let high = CGRect(x: 100, y: 100, width: 180, height: 40)
        let below = DocumentModel.handwritingTextLayout(text: "hello", lines: [line(height: 30)], ink: high,
                                                        keepingInk: true, pageSize: page)
        #expect(below.frame.minY > high.maxY)
    }

    @Test func theWordsStayOnThePage() {
        let edge = CGRect(x: 560, y: 790, width: 300, height: 40)
        let long = String(repeating: "word ", count: 40)
        let layout = DocumentModel.handwritingTextLayout(text: long, lines: [], ink: edge, keepingInk: false, pageSize: page)
        #expect(CGRect(origin: .zero, size: page).contains(layout.frame), "\(layout.frame)")
        #expect((9...60).contains(layout.fontSize))
    }
}

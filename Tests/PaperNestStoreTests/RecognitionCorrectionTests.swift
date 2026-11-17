import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Correcting what recognition read, by hand. A correction is only worth
/// making if every reader of the page's text gets it — search above all — and
/// only safe if nothing can silently undo it: not a newer engine, not an
/// editor left open while the page was recognized again.
@Suite struct RecognitionCorrectionTests {
    private let engine = "test.engine.1"

    private func seedScan(_ store: LibraryStore) async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data("scan bytes".utf8), kind: .png, originalFilename: "scan.png")
        let item = try await store.createItem(kind: .document, name: "Receipt", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    private func line(_ text: String, row: Int, words: Bool = false) -> RecognizedLine {
        let y = 0.1 + Double(row) * 0.05
        let parts = text.split(separator: " ").map(String.init)
        let boxes = words ? parts.enumerated().map { index, word in
            RecognizedWord(text: word, box: .exact(x: 0.1 + Double(index) * 0.1, y: y, width: 0.08, height: 0.02))
        } : []
        return RecognizedLine(text: text, box: .exact(x: 0.1, y: y, width: 0.5, height: 0.02),
                              confidence: 0.5, words: boxes)
    }

    /// Saves a finished result for the page as it is, and hands it back as
    /// stored: that is what an editor opens with.
    private func recognized(_ store: LibraryStore, _ page: Page, _ lines: [RecognizedLine],
                            engineVersion: String? = nil) async throws -> PageRecognition {
        try await store.saveRecognition(PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                                        engineVersion: engineVersion ?? engine, status: .completed,
                                                        languages: ["en-US"], lines: lines))
        return try #require(try await store.recognition(for: page.id))
    }

    // MARK: - Every reader gets the corrected words

    @Test func searchFindsTheCorrectedWordAndNoLongerTheMisreadOne() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Invocie total 42", row: 0), line("Paid", row: 1)])
        #expect(try await store.search("Invocie") == [item.id])

        let change = try #require(try await store.correctRecognition(on: page.id, expected: read,
                                                                     texts: ["Invoice total 42", "Paid"]))

        #expect(try await store.search("Invoice") == [item.id])
        #expect(try await store.search("Invocie").isEmpty, "the misread word must stop answering searches")
        let stored = try #require(try await store.recognition(for: page.id))
        #expect(stored.lines.map(\.text) == ["Invoice total 42", "Paid"])
        #expect(stored.correctedAt != nil)
        #expect(change.after.correctedAt != nil && change.before.correctedAt == nil)
    }

    /// Find and text selection re-read a page only when its revision moves,
    /// so a correction moves it — and the corrected result is current for the
    /// new revision, or every reader would treat it as stale and show nothing.
    @Test func theRevisionMovesAndTheCorrectedResultIsCurrentForIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Teh quick fox", row: 0)])

        try await store.correctRecognition(on: page.id, expected: read, texts: ["The quick fox"])

        let moved = try #require(try await store.page(page.id))
        #expect(moved.revision == page.revision + 1)
        let stored = try #require(try await store.recognition(for: page.id))
        #expect(stored.sourceRevision == moved.revision)
        #expect(stored.status == .completed)
    }

    @Test func accentedCorrectionsAreKeptAndFound() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Deja paye", row: 0)])

        try await store.correctRecognition(on: page.id, expected: read, texts: ["Déjà payé — año"])

        #expect(try await store.recognition(for: page.id)?.lines.first?.text == "Déjà payé — año")
        #expect(try await store.search("payé") == [item.id])
        #expect(try await store.search("año") == [item.id])
    }

    // MARK: - What a typed entry becomes

    @Test func anEmptyEntryRemovesTheLineAndEndsAndBreaksAreTidied() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Heading", row: 0), line("~:;'", row: 1),
                                                      line("Body text", row: 2)])

        try await store.correctRecognition(on: page.id, expected: read,
                                           texts: ["  Heading  ", "   ", "Body\ntext here"])

        let stored = try #require(try await store.recognition(for: page.id))
        #expect(stored.lines.map(\.text) == ["Heading", "Body text here"])
        // An unchanged line is left exactly as read; a changed one keeps its
        // place on the page and is certain now.
        #expect(stored.lines[0] == read.lines[0])
        #expect(stored.lines[1].box == read.lines[2].box)
        #expect(stored.lines[1].confidence == 1)
    }

    @Test func aCorrectionThatChangesNothingWritesNothing() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Already right", row: 0)])

        let change = try await store.correctRecognition(on: page.id, expected: read, texts: [" Already right "])

        #expect(change == nil)
        #expect(try await store.page(page.id)?.revision == page.revision, "nothing to undo, nothing moved")
        #expect(try await store.recognition(for: page.id) == read)
    }

    @Test func aTypoFixKeepsWordBoxesAndAChangedWordCountFallsBackToTheLine() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Totl due now", row: 0, words: true),
                                                      line("Thank you", row: 1, words: true)])

        try await store.correctRecognition(on: page.id, expected: read,
                                           texts: ["Total due now", "Thank you very much"])

        let stored = try #require(try await store.recognition(for: page.id))
        #expect(stored.lines[0].words.map(\.text) == ["Total", "due", "now"])
        #expect(stored.lines[0].words.map(\.box) == read.lines[0].words.map(\.box),
                "the same words in the same places, one spelled right")
        #expect(stored.lines[1].words.isEmpty, "four words cannot borrow two words' boxes")
    }

    @Test func entriesThatDoNotMatchTheLinesAreRefused() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("One", row: 0), line("Two", row: 1)])

        await #expect(throws: StoreError.invalidOrder) {
            try await store.correctRecognition(on: page.id, expected: read, texts: ["One"])
        }
        #expect(try await store.recognition(for: page.id) == read)
    }

    // MARK: - Nothing overwritten behind anyone's back

    /// The editor was open while the page was recognized again. Saving must
    /// not put the old lines, corrected, over the new reading.
    @Test func aStaleEditorCannotOverwriteANewerReading() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let opened = try await recognized(store, page, [line("Old reading", row: 0)])
        let newer = try await recognized(store, page, [line("New reading", row: 0)], engineVersion: "test.engine.2")

        await #expect(throws: StoreError.recognitionChanged) {
            try await store.correctRecognition(on: page.id, expected: opened, texts: ["Old reading, fixed"])
        }
        #expect(try await store.recognition(for: page.id) == newer)
        #expect(try await store.page(page.id)?.revision == page.revision)
    }

    @Test func onlyACurrentFinishedResultCanBeCorrected() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let failed = PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: engine,
                                     status: .failed, languages: ["en-US"], lines: [])
        try await store.saveRecognition(failed)

        await #expect(throws: StoreError.recognitionChanged) {
            try await store.correctRecognition(on: page.id, expected: failed, texts: [])
        }

        // New paper: the old result describes nothing on the page now.
        let read = try await recognized(store, page, [line("Before the rescan", row: 0)])
        let fresh = try store.assets.store(Data("rescanned".utf8), kind: .png, originalFilename: "again.png")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize, content: .image(fresh.id),
                                                                    transform: page.transform), assets: [fresh])
        await #expect(throws: StoreError.recognitionChanged) {
            try await store.correctRecognition(on: page.id, expected: read, texts: ["Before the rescan!"])
        }
    }

    // MARK: - Undo

    /// Drawing on the page carries its result forward to the new revision
    /// without changing a word. Undo must still recognize the correction.
    @Test func undoWorksAfterInkWasDrawn() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Recieved", row: 0)])
        let change = try #require(try await store.correctRecognition(on: page.id, expected: read, texts: ["Received"]))
        let stroke = InkStroke(tool: .pen, color: .black, width: 4, points: [InkPoint(x: 10, y: 10), InkPoint(x: 90, y: 90)])
        try await store.saveObject(PageObject(pageID: page.id, zKey: "m", payload: .ink(stroke), modifiedAt: Date()))

        try await store.applyRecognitionCorrection(change.inverse)

        let stored = try #require(try await store.recognition(for: page.id))
        #expect(stored.lines.map(\.text) == ["Recieved"])
        #expect(stored.correctedAt == nil, "undone, the page holds what the engine read again")
        #expect(stored.sourceRevision == (try await store.page(page.id))?.revision)
        #expect(try await store.search("Recieved") == [item.id])
        #expect(try await store.search("Received").isEmpty)

        // And redo.
        try await store.applyRecognitionCorrection(change)
        #expect(try await store.recognition(for: page.id)?.lines.map(\.text) == ["Received"])
    }

    @Test func undoIsRefusedAfterThePageWasRecognizedAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Recieved", row: 0)])
        let change = try #require(try await store.correctRecognition(on: page.id, expected: read, texts: ["Received"]))
        let moved = try #require(try await store.page(page.id))
        let again = try await recognized(store, moved, [line("Received in full", row: 0)])

        await #expect(throws: StoreError.recognitionChanged) {
            try await store.applyRecognitionCorrection(change.inverse)
        }
        #expect(try await store.recognition(for: page.id) == again)
    }

    // MARK: - Automatic recognition leaves corrections alone

    @Test func aNewerEngineDoesNotReadACorrectedPageAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, corrected) = try await seedScan(store)
        let (_, untouched) = try await seedScan(store)
        let read = try await recognized(store, corrected, [line("Teh", row: 0)])
        _ = try await recognized(store, untouched, [line("Plain", row: 0)])
        try await store.correctRecognition(on: corrected.id, expected: read, texts: ["The"])

        let needing = try await store.pagesNeedingRecognition(engineVersion: "test.engine.2").map(\.id)

        #expect(needing == [untouched.id], "the untouched page is read by the new engine; the corrected one is not")
        #expect(try await store.pagesNeedingRecognition(engineVersion: engine).isEmpty)
    }

    @Test func aCorrectedPageWithNewPaperIsReadAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        let read = try await recognized(store, page, [line("Teh", row: 0)])
        try await store.correctRecognition(on: page.id, expected: read, texts: ["The"])
        let current = try #require(try await store.page(page.id))
        let fresh = try store.assets.store(Data("rescanned".utf8), kind: .png, originalFilename: "again.png")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: current.sourceSize, content: .image(fresh.id),
                                                                    transform: current.transform), assets: [fresh])

        #expect(try await store.pagesNeedingRecognition(engineVersion: engine).map(\.id) == [page.id])
    }

    /// Every result stored before corrections existed has no `correctedAt`.
    @Test func aResultStoredBeforeCorrectionsExistedDecodesAsUntouched() throws {
        let stored = """
            {"engineVersion":"vision.accurate.1","languages":["en-US"],"lines":[{"box":{"height":0.02,"width":0.5,"x":0.1,"y":0.1},\
            "confidence":0.5,"text":"Old"}],"pageID":"p1","sourceRevision":3,"status":"completed"}
            """
        let decoded = try JSONDecoder().decode(PageRecognition.self, from: Data(stored.utf8))
        #expect(decoded.correctedAt == nil)
        #expect(decoded.lines.map(\.text) == ["Old"])
        let written = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(!written.contains("correctedAt"), "an untouched result writes no marker the query could mistake")
    }
}

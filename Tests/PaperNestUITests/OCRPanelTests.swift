import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestTestSupport
@testable import PaperNestUI

@Suite struct OCRPageSelectionTests {
    @Test func mixedRangesAreDeduplicatedAndOrdered() {
        #expect(OCRPageSelection.indices(in: " 5, 1–3, 2 ", pageCount: 6) == [0, 1, 2, 4])
        #expect(OCRPageSelection.indices(in: "2—4", pageCount: 4) == [1, 2, 3])
    }
    @Test(arguments: ["", "0", "7", "3-1", "1,", "1--3", "-1", "a", "1-999999999999999999999"])
    func invalidInputNeverSelectsPages(_ input: String) {
        #expect(OCRPageSelection.indices(in: input, pageCount: 6) == nil)
    }
    @Test func emptyDocumentHasNoValidRange() {
        #expect(OCRPageSelection.indices(in: "1", pageCount: 0) == nil)
    }
}

@MainActor @Suite(.serialized) struct OCRPanelWorkflowTests {
    @Test func explicitSelectionOnlyRecognizesRequestedPagesAndRecordsLanguages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OCRPanel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scan = root.appendingPathComponent("Selection.png")
        try SyntheticDocuments.textImage(lines: ["Selected page example"]).write(to: scan)
        let session = LibrarySession(libraryURL: root.appendingPathComponent("Library"))
        await session.bootstrap()
        let env = try #require(session.environment)
        let library = LibraryModel(session: session)
        await library.importFiles([scan]); await library.reload()
        let item = try #require(library.items.first)
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        let first = try #require(model.selectedPage)
        try await model.duplicateSelectedPage(undoManager: nil)
        let second = try #require(model.selectedPage)
        #expect(first.id != second.id)
        // Import's existing background OCR may already have indexed page one.
        // A panel run must leave that result unchanged, not erase it.
        while let work = session.backgroundTextWork { await work.value }
        let firstBefore = try await env.store.recognition(for: first.id)
        let languages = TextRecognizer.supportedLanguages(from: ["en-US"])
        #expect(!languages.isEmpty)
        let completed = await model.recognizeText(pageIDs: [second.id], languages: languages)
        #expect(completed == 1)
        #expect(try await env.store.recognition(for: first.id) == firstBefore)
        let result = try #require(try await env.store.recognition(for: second.id))
        #expect(result.languages == languages)
        #expect(result.status == .completed)
        #expect(result.lines.contains { $0.text.contains("Selected") })
        #expect(model.recognitionProgress == nil)
        #expect(await model.recognizeText(pageIDs: [first.id], languages: []) == 0)
        #expect(try await env.store.recognition(for: first.id) == firstBefore)
        #expect(await model.recognizeText(pageIDs: [], languages: languages) == 0)
    }
}

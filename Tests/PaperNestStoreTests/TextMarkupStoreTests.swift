import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct TextMarkupStoreTests {
    private func seed(_ store: LibraryStore) async throws -> (Page, PageRecognition) {
        let item = try await store.createItem(kind: .document, name: "Synthetic", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        let recognition = PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
            status: .completed, languages: ["en"], lines: [
                RecognizedLine(text: "Quarterly", box: .exact(x: 0.1, y: 0.2, width: 0.5, height: 0.02), confidence: 1),
                RecognizedLine(text: "Résumé", box: .exact(x: 0.1, y: 0.3, width: 0.5, height: 0.02), confidence: 1)
            ])
        try await store.saveRecognition(recognition)
        return (page, recognition)
    }

    @Test func selectedLinesPersistInReadingOrderWithOneRevisionBump() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (page, recognition) = try await seed(store)
        let result = try await store.addTextMarkup(recognition, lineIndices: [1, 0], style: .highlight)
        #expect(result.page.revision == page.revision + 1)
        #expect(result.page.content == page.content)
        #expect(result.objects.count == 2)
        #expect(result.objects[0].zKey < result.objects[1].zKey)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.objects(on: page.id) == result.objects)
        #expect(try await reopened.search("quarterly") == [page.itemID])
        #expect(try await reopened.recognition(for: page.id)?.sourceRevision == result.page.revision)
    }

    @Test func aReplacedOrStaleRecognitionSnapshotCannotMarkDifferentPaper() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (page, recognition) = try await seed(store)
        var revised = recognition
        revised.lines[0].text = "Changed OCR"
        try await store.saveRecognition(revised)
        await #expect(throws: StoreError.recognitionChanged) {
            try await store.addTextMarkup(recognition, lineIndices: [0], style: .underline)
        }
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize, content: .template(.lined), transform: .identity), assets: [])
        await #expect(throws: StoreError.recognitionChanged) {
            try await store.addTextMarkup(revised, lineIndices: [0], style: .strikethrough)
        }
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    @Test func anInvalidLaterLineRollsBackTheWholeSelection() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (page, recognition) = try await seed(store)
        var invalid = recognition
        invalid.lines[1].box = .exact(x: 0, y: 0, width: -1, height: 0.01)
        try await store.saveRecognition(invalid)
        await #expect(throws: TextMarkupError.invalidBounds) {
            try await store.addTextMarkup(invalid, lineIndices: [0, 1], style: .highlight)
        }
        await #expect(throws: StoreError.invalidOrder) {
            try await store.addTextMarkup(invalid, lineIndices: [0, 9], style: .highlight)
        }
        #expect(try await store.objects(on: page.id).isEmpty)
        #expect(try await store.page(page.id)?.revision == page.revision)
    }

    @Test func objectEditsNeverMakeOldRecognitionCurrent() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (page, recognition) = try await seed(store)
        var stale = recognition
        stale.sourceRevision -= 1
        try await store.saveRecognition(stale)
        let object = PageObject(pageID: page.id, zKey: "V", payload: .ink(try TextMarkupStyle.underline.stroke(
            for: recognition.lines[0], in: page.sourceSize)), modifiedAt: Date())
        _ = try await store.applyObjectChanges(on: page.id, saving: [object], deleting: [])
        #expect(try await store.recognition(for: page.id) == stale)
        #expect(try await store.search("quarterly").isEmpty)
    }
}

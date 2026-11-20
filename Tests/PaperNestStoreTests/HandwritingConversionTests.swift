import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Handwriting turned into a text box: the reviewed words saved as typed
/// text, the strokes kept or taken away in the same write, and nothing
/// written when the strokes changed after they were read.
@Suite struct HandwritingConversionTests {
    private func notebook(_ store: LibraryStore) async throws -> (LibraryItem, Page, [PageObject]) {
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try #require(try await store.pages(of: item.id).first)
        let strokes = ["T", "U", "V"].enumerated().map { index, key in
            PageObject(pageID: page.id, zKey: key, payload: .ink(InkStroke(
                tool: .pen, color: RGBAColor(red: 0.1, green: 0.2, blue: 0.6), width: 2,
                points: [InkPoint(x: 100 + Double(index) * 20, y: 120), InkPoint(x: 110 + Double(index) * 20, y: 150)])),
                       modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        }
        for stroke in strokes { try await store.saveObject(stroke) }
        return (item, try #require(try await store.page(page.id)), strokes)
    }

    private let frame = CGRect(x: 100, y: 170, width: 200, height: 40)
    private let blue = RGBAColor(red: 0.1, green: 0.2, blue: 0.6)

    @Test func theReviewedWordsAreSavedAndTheInkKept() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page, strokes) = try await notebook(store)

        let result = try await store.convertHandwriting(on: page.id, strokes: strokes, text: "  Call Ana at noon \n",
                                                        frame: frame, fontSize: 18, color: blue, keepingInk: true)
        #expect(result.removed.isEmpty)
        #expect(result.page.revision == page.revision + 1)
        guard case .text(let box) = result.text.payload else { Issue.record("not a text box"); return }
        #expect(box.text == "Call Ana at noon")
        #expect(box.frame == frame)
        #expect(box.fontSize == 18)
        #expect(box.color == blue)
        let objects = try await store.objects(on: page.id)
        #expect(objects.map(\.id) == strokes.map(\.id) + [result.text.id], "the box is laid over the ink, which stays")
    }

    @Test func theInkCanBeTakenAwayInTheSameWrite() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page, strokes) = try await notebook(store)

        let result = try await store.convertHandwriting(on: page.id, strokes: Array(strokes.prefix(2)), text: "Plan",
                                                        frame: frame, fontSize: 16, color: .black, keepingInk: false)
        #expect(result.removed == Array(strokes.prefix(2)))
        #expect(result.page.revision == page.revision + 1, "one write, one revision")
        #expect(try await store.objects(on: page.id).map(\.id) == [strokes[2].id, result.text.id])
    }

    /// On disk when the call returns, and found by search like typed text.
    @Test func theTextIsKeptAndFoundBySearch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, strokes) = try await notebook(store)
        _ = try await store.convertHandwriting(on: page.id, strokes: strokes, text: "quarterlyzebra",
                                               frame: frame, fontSize: 16, color: .black, keepingInk: false)

        let reopened = try LibraryStore(directory: dir.url)
        let objects = try await reopened.objects(on: page.id)
        #expect(objects.count == 1)
        #expect(try await reopened.search("quarterlyzebra") == [item.id])
    }

    @Test func aStrokeChangedSinceItWasReadRefusesTheWholeChange() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page, strokes) = try await notebook(store)
        var moved = strokes[1]
        if case .ink(var stroke) = moved.payload {
            stroke.points = stroke.points.map { InkPoint(x: $0.x + 40, y: $0.y) }
            moved.payload = .ink(stroke)
        }
        try await store.saveObject(moved)
        let before = try await store.objects(on: page.id)

        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.convertHandwriting(on: page.id, strokes: strokes, text: "Plan", frame: frame,
                                               fontSize: 16, color: .black, keepingInk: false)
        }
        try await store.deleteObject(strokes[0].id)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.convertHandwriting(on: page.id, strokes: [strokes[0]], text: "Plan", frame: frame,
                                               fontSize: 16, color: .black, keepingInk: true)
        }
        #expect(try await store.objects(on: page.id) == before.filter { $0.id != strokes[0].id }, "nothing written")
    }

    @Test func onlyInkAndRealWordsAreAccepted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page, strokes) = try await notebook(store)
        let typed = try await store.placeText("Typed", on: page.id, frame: frame, fontSize: 14, color: .black,
                                              alignment: .leading).object

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.convertHandwriting(on: page.id, strokes: strokes, text: " \n ", frame: frame,
                                               fontSize: 16, color: .black, keepingInk: true)
        }
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.convertHandwriting(on: page.id, strokes: [typed], text: "Plan", frame: frame,
                                               fontSize: 16, color: .black, keepingInk: false)
        }
        await #expect(throws: StoreError.invalidOrder) {
            try await store.convertHandwriting(on: page.id, strokes: [], text: "Plan", frame: frame,
                                               fontSize: 16, color: .black, keepingInk: true)
        }
        await #expect(throws: StoreError.invalidPlacement) {
            try await store.convertHandwriting(on: page.id, strokes: strokes, text: "Plan", frame: .zero,
                                               fontSize: 16, color: .black, keepingInk: true)
        }
        #expect(try await store.objects(on: page.id).count == strokes.count + 1, "nothing written")
    }
}

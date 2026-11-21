import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestRender
#if canImport(PaperNestTestSupport)
import PaperNestTestSupport
#endif

/// The background pass that makes handwriting findable: synthetic
/// single-stroke writing (`SyntheticHandwriting`, nobody's real hand) is
/// read off a page's ink and answers a search as handwriting.
@Suite struct AutomaticHandwritingRecognizerTests {
    /// A throwaway library folder, removed with the system's temporary files.
    private static func libraryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("papernest-handwriting-\(UUID().uuidString)")
    }

    private func journal(_ store: LibraryStore, writing: String?) async throws -> (LibraryItem, Page) {
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try #require(try await store.pages(of: item.id).first)
        if let writing {
            for (index, path) in try SyntheticHandwriting.strokes(writing, origin: CGPoint(x: 80, y: 200)).enumerated() {
                try await store.saveObject(PageObject(pageID: page.id, zKey: String(format: "K%03d", index), payload: .ink(InkStroke(
                    tool: .pen, color: .black, width: 2.2, points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
            }
        }
        return (item, page)
    }

    @Test func writtenWordsBecomeFindableAsHandwriting() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let (item, page) = try await journal(store, writing: "plan lunch")
        #expect(try await store.search("lunch").isEmpty, "not findable before it is read")

        #expect(try await AutomaticHandwritingRecognizer(store: store).readMissing() == 1)
        #expect(try await store.search("lunch") == [item.id])
        let hit = try #require(try await store.searchHits("lunch").first)
        #expect(hit.source == .handwritten)
        #expect(hit.pageID == page.id)
        #expect(try await store.currentHandwriting(on: page.id)?.engineVersion == HandwritingRecognizer.engineVersion)

        #expect(try await AutomaticHandwritingRecognizer(store: store).readMissing() == 0, "nothing left to read")
    }

    /// Changed ink is read again: the old words stop answering, the new ones do.
    @Test func changedInkIsReadAgain() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let (item, page) = try await journal(store, writing: "plan lunch")
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        for object in try await store.objects(on: page.id) { try await store.deleteObject(object.id) }
        for (index, path) in try SyntheticHandwriting.strokes("send notes", origin: CGPoint(x: 80, y: 200)).enumerated() {
            try await store.saveObject(PageObject(pageID: page.id, zKey: String(format: "N%03d", index), payload: .ink(InkStroke(
                tool: .pen, color: .black, width: 2.2, points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)))
        }
        #expect(try await store.search("lunch").isEmpty, "the erased words stopped answering at once")

        #expect(try await AutomaticHandwritingRecognizer(store: store).readMissing() == 1)
        #expect(try await store.search("notes") == [item.id])
        #expect(try await store.search("lunch").isEmpty)
    }

    /// A scribble is read once and kept as read with nothing in it: nothing
    /// becomes findable, and it is not read again on every pass.
    @Test func aScribbleIsReadOnceAndFindsNothing() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let (_, page) = try await journal(store, writing: nil)
        var wobble = SyntheticHandwriting.Wobble(seed: 7)
        for index in 0..<6 {
            try await store.saveObject(PageObject(pageID: page.id, zKey: "S\(index)", payload: .ink(InkStroke(
                tool: .pen, color: .black, width: 2.5, points: (0..<40).map { i in
                    InkPoint(x: 200 + Double(i) * 3 + wobble.next(30), y: 300 + wobble.next(40))
                })), modifiedAt: Date()))
        }
        #expect(try await AutomaticHandwritingRecognizer(store: store).readMissing() == 1)
        let result = try #require(try await store.currentHandwriting(on: page.id))
        #expect(result.status == .completed)
        #expect(result.searchableText.isEmpty, "read \(result.lines.map(\.text))")
        #expect(try await AutomaticHandwritingRecognizer(store: store).readMissing() == 0)
    }
}

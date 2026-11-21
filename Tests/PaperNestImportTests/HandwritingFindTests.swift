import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
@testable import PaperNestRender
#if canImport(PaperNestTestSupport)
import PaperNestTestSupport
#endif

/// Find in a document over handwriting: the words read off a page's ink are
/// in the text find matches (and only in find's: the plain layout that
/// selection, reading aloud, cleanup and comparison use has none), each with
/// a box over its own writing. The writing is synthetic single-stroke print.
@Suite struct HandwritingFindTests {
    private static func libraryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("papernest-handwriting-find-\(UUID().uuidString)")
    }

    private func write(_ text: String, on page: Page, in store: LibraryStore, at origin: CGPoint = CGPoint(x: 80, y: 200),
                       prefix: String = "K") async throws {
        for (index, path) in try SyntheticHandwriting.strokes(text, origin: origin).enumerated() {
            try await store.saveObject(PageObject(pageID: page.id, zKey: String(format: "\(prefix)%03d", index), payload: .ink(InkStroke(
                tool: .pen, color: .black, width: 2.2, points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        }
    }

    private func journal(_ store: LibraryStore, writing: String? = "plan lunch") async throws -> Page {
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try #require(try await store.pages(of: item.id).first)
        if let writing { try await write(writing, on: page, in: store) }
        return page
    }

    private func texts(_ renderer: PageRenderer, _ pages: [Page], handwriting: Bool) async throws -> [PageID: PageSearchText] {
        let collected = Collected()
        try await renderer.searchTexts(for: pages, includingHandwriting: handwriting) { id, text in await collected.put(id, text) }
        return await collected.all
    }

    private actor Collected {
        var all: [PageID: PageSearchText] = [:]
        func put(_ id: PageID, _ text: PageSearchText) { all[id] = text }
    }

    private func finds(_ word: String, in text: PageSearchText?) -> Bool {
        guard let text, let query = PageSearchQuery(word) else { return false }
        return !text.ranges(of: query).isEmpty
    }

    @Test func handwritingIsInFindsTextAndNowhereElse() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let page = try await journal(store)
        let renderer = PageRenderer(store: store)
        #expect(!finds("lunch", in: try await texts(renderer, [page], handwriting: true)[page.id]), "not before it is read")

        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        let layout = try await renderer.textLayout(for: page, includingHandwriting: true)
        #expect(layout.lines.allSatisfy { $0.origin == .handwritten })
        #expect(layout.text.lowercased().contains("plan lunch"), "find's layout: \(layout.text)")
        #expect(finds("lunch", in: try await texts(renderer, [page], handwriting: true)[page.id]))

        // What selection, reading aloud, cleanup and comparison read: no handwriting.
        #expect(try await renderer.textLayout(for: page).lines.isEmpty)
        #expect(!finds("lunch", in: try await texts(renderer, [page], handwriting: false)[page.id]))
    }

    /// A match's box covers the word it matched, not the whole line: "lunch"
    /// is the second word, so its box is on the right of the writing.
    @Test func aWordsBoxLiesOverItsOwnWriting() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let page = try await journal(store)
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        let layout = try await PageRenderer(store: store).textLayout(for: page, includingHandwriting: true)
        let query = try #require(PageSearchQuery("lunch"))
        let range = try #require(layout.searchText.ranges(of: query).first)
        let box = try #require(layout.boxes(for: range).first)

        let ink = try await store.objects(on: page.id).compactMap { object -> InkStroke? in
            if case .ink(let stroke) = object.payload { return stroke } else { return nil }
        }
        let writing = try #require(HandwritingRecognizer.bounds(of: ink))
        let share = CGRect(x: writing.minX / 600, y: writing.minY / 800, width: writing.width / 600, height: writing.height / 800)
        let found = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        #expect(share.insetBy(dx: -0.02, dy: -0.02).contains(found), "\(found) is not over the writing \(share)")
        #expect(found.width < share.width * 0.7, "a word's box, not the line's: \(found) in \(share)")
        #expect(found.midX > share.midX, "the second word is on the right: \(found) in \(share)")
    }

    /// Ink changed after it was read: find no longer has the old words, even
    /// before the page is read again, and has the new ones after.
    @Test func changedInkLeavesFindWithoutTheOldWords() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let page = try await journal(store)
        let renderer = PageRenderer(store: store)
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        for object in try await store.objects(on: page.id) { try await store.deleteObject(object.id) }
        try await write("send notes", on: page, in: store, prefix: "N")

        #expect(try await renderer.textLayout(for: page, includingHandwriting: true).lines.isEmpty, "a stale reading is left out")
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        let text = try await texts(renderer, [page], handwriting: true)[page.id]
        #expect(finds("notes", in: text))
        #expect(!finds("lunch", in: text))
    }

    /// Writing the page's crop hides is not found, as with any other text.
    @Test func aCropHidesTheWritingOutsideIt() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let page = try await journal(store)
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        var transform = page.transform
        transform.crop = .exact(x: 0, y: 0.5, width: 1, height: 0.5)   // the bottom half; the writing is at the top
        let cropped = try await store.updateTransform(page.id, to: transform)
        let renderer = PageRenderer(store: store)
        #expect(try await renderer.textLayout(for: cropped, includingHandwriting: true).lines.isEmpty)
        #expect(!finds("lunch", in: try await texts(renderer, [cropped], handwriting: true)[page.id]))
    }

    /// Only what library search would find: an unsure line is in, noise below
    /// Vision's unsure step is not.
    @Test func onlyConfidentLinesAreFound() async throws {
        let store = try LibraryStore(directory: Self.libraryDirectory())
        let page = try await journal(store)
        let generation = try await store.inkGeneration(of: page.id)
        let line = { (text: String, confidence: Double, y: Double) in
            HandwritingRecognitionResult.Line(text: text, confidence: confidence, bounds: CGRect(x: 80, y: y, width: 200, height: 30))
        }
        #expect(try await store.saveHandwriting(HandwritingRecognitionResult(
            pageID: page.id, inkGeneration: generation, engineVersion: HandwritingRecognizer.engineVersion, status: .completed,
            languages: ["en-US"], lines: [line("quokka", 0.5, 100), line("wombat", 0.3, 200)])))
        let text = try await texts(PageRenderer(store: store), [page], handwriting: true)[page.id]
        #expect(finds("quokka", in: text))
        #expect(!finds("wombat", in: text))
    }

    /// A reading from before word boxes were kept (`vision.handwriting.1`):
    /// it still decodes, and its line is found with the line's box.
    @Test func aReadingFromBeforeWordBoxesUsesItsLineBox() async throws {
        let v1 = """
        {"pageID":"p1","inkGeneration":3,"engineVersion":"vision.handwriting.1","status":"completed","languages":["en-US"],
         "lines":[{"text":"plan lunch","confidence":1,"bounds":[[60,180],[240,40]]}]}
        """
        let reading = try JSONDecoder().decode(HandwritingRecognitionResult.self, from: Data(v1.utf8))
        #expect(reading.lines.first?.words == [])
        let lines = PageRenderer.handwritingLines(of: reading, sourceSize: CGSize(width: 600, height: 800))
        #expect(lines.count == 1)
        #expect(lines.first?.fragments.count == 1, "one fragment, the whole line")
        let box = try #require(lines.first?.fragments.first?.box)
        #expect(abs(box.x - 0.1) < 0.001 && abs(box.width - 0.4) < 0.001, "the line's box in shares of the page: \(box)")
    }

    /// Ink on a digital PDF page: the file's own words and the handwriting are
    /// both found (the file-only shortcut is not taken when there is a reading).
    @Test func handwritingOnAPDFPageIsFoundWithTheFilesOwnText() async throws {
        let directory = Self.libraryDirectory()
        let store = try LibraryStore(directory: directory)
        let item = try await DocumentImporter(store: store).importItem(.data(SyntheticDocuments.textPDF(pages: ["Statement"]),
                                                                             name: "Statement"))
        let page = try #require(try await store.pages(of: item.id).first)
        try await write("plan lunch", on: page, in: store, at: CGPoint(x: 80, y: page.sourceSize.height * 0.7))
        try await AutomaticHandwritingRecognizer(store: store).readMissing()
        let text = try await texts(PageRenderer(store: store), [page], handwriting: true)[page.id]
        #expect(finds("statement", in: text))
        #expect(finds("lunch", in: text))
    }
}

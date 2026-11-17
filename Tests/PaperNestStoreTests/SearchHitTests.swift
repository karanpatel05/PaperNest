import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Search results that say where the match is: the page, and the words around
/// it. A hit is only useful if it is right about the page, and only safe if it
/// never points at a page that is in the trash.
@Suite struct SearchHitTests {
    private let engine = "test.engine.1"

    /// A scan of `pages` image pages, each recognized with the given text
    /// (nil leaves a page unread).
    private func scan(_ store: LibraryStore, name: String = "Scan", _ texts: [String?]) async throws
        -> (LibraryItem, [Page]) {
        let asset = try store.assets.store(Data("scan \(name)".utf8), kind: .png, originalFilename: "scan.png")
        let item = try await store.createItem(kind: .document, name: name, pages: texts.map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id))
        }, assets: [asset])
        let pages = try await store.pages(of: item.id)
        for (page, text) in zip(pages, texts) {
            guard let text else { continue }
            try await recognize(store, page, text)
        }
        return (item, try await store.pages(of: item.id))
    }

    private func recognize(_ store: LibraryStore, _ page: Page, _ text: String) async throws {
        let lines = text.split(separator: "\n").enumerated().map { index, line in
            RecognizedLine(text: String(line), box: .exact(x: 0.1, y: 0.1 + Double(index) * 0.05, width: 0.6, height: 0.03),
                           confidence: 0.9)
        }
        try await store.saveRecognition(PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                                        engineVersion: engine, status: .completed,
                                                        languages: ["en-US"], lines: lines))
    }

    private func pageHits(_ hits: [SearchHit]) -> [SearchHit] { hits.filter { $0.pageID != nil } }
    private func matches(_ hit: SearchHit) -> [String] { hit.snippet.runs.filter(\.isMatch).map(\.text) }

    // MARK: - The page and the words

    @Test func aHitSaysWhichPageAndShowsTheWordsAroundTheMatch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, pages) = try await scan(store, [nil, "Invoice total 42 for October", "Nothing relevant"])

        let hits = pageHits(try await store.searchHits("invoice"))

        try #require(hits.count == 1)
        #expect(hits[0].itemID == item.id)
        #expect(hits[0].pageID == pages[1].id)
        #expect(hits[0].pageNumber == 2)
        #expect(hits[0].source == .recognized)
        #expect(matches(hits[0]) == ["Invoice"], "the word as it is on the page, not as it was typed")
        #expect(hits[0].snippet.text.contains("total 42 for October"))
    }

    @Test func aPrefixMarksTheWholeWord() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, ["Quarterly invoices attached"])

        let hit = try #require(pageHits(try await store.searchHits("invo")).first)
        #expect(matches(hit) == ["invoices"])
    }

    @Test func anAccentBlindMatchShowsTheWordWithItsAccents() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, ["Facture déjà payée en août"])

        let hit = try #require(pageHits(try await store.searchHits("deja")).first)
        #expect(matches(hit) == ["déjà"])
        let august = try #require(pageHits(try await store.searchHits("aout")).first)
        #expect(matches(august) == ["août"])
    }

    @Test func everyWordOfAQueryIsMarked() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, ["Invoice total 42 for October"])

        let hit = try #require(pageHits(try await store.searchHits("october invoice")).first)
        #expect(matches(hit) == ["Invoice", "October"])
    }

    /// A page's lines are the layout of paper; a result is one line.
    @Test func lineBreaksBecomeSpaces() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, ["Statement of\naccount\n\n   for March"])

        let hit = try #require(pageHits(try await store.searchHits("account")).first)
        #expect(!hit.snippet.text.contains("\n"))
        #expect(hit.snippet.text == "Statement of account for March")
    }

    // MARK: - Never a page in the trash

    /// A deleted page keeps its index rows until the next launch's purge so
    /// undo can restore it. Its words must stop answering searches at once —
    /// for `search(_:)` too, which used to keep the document in the results.
    @Test func aDeletedPagesWordsStopAnsweringAtOnce() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, pages) = try await scan(store, ["Cover page", "Invoice total 42"])
        #expect(try await store.search("invoice") == [item.id])

        let deleted = try await store.deletePages([pages[1].id])

        #expect(try await store.search("invoice").isEmpty, "a document matched words only on a deleted page")
        #expect(try await store.searchHits("invoice").isEmpty)
        #expect(try await store.search("cover") == [item.id], "the page still in the document still answers")

        // Undo brings the words back with the page.
        try await store.restorePages(deleted)
        #expect(try await store.search("invoice") == [item.id])
        #expect(pageHits(try await store.searchHits("invoice")).first?.pageNumber == 2)
    }

    @Test func aDocumentInRecentlyDeletedHasNoHits() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, _) = try await scan(store, name: "Invoice archive", ["Invoice total 42"])

        try await store.moveToRecentlyDeleted([item.id])

        #expect(try await store.searchHits("invoice").isEmpty)
    }

    @Test func pageNumbersFollowTheOrderAndSkipDeletedPages() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages) = try await scan(store, ["First", "Second", "Third has the invoice"])
        #expect(pageHits(try await store.searchHits("invoice")).first?.pageNumber == 3)

        _ = try await store.movePage(pages[2].id, toIndex: 0)
        #expect(pageHits(try await store.searchHits("invoice")).first?.pageNumber == 1)

        _ = try await store.movePage(pages[2].id, toIndex: 2)
        try await store.deletePages([pages[0].id])
        #expect(pageHits(try await store.searchHits("invoice")).first?.pageNumber == 2,
                "a deleted page before it is not counted")
    }

    // MARK: - Which hits

    /// A digital page that was also recognized holds its words twice. One hit,
    /// from the page's own text, which is what find lights when it opens.
    @Test func onePageIsOneHitAndItsOwnTextWins() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages) = try await scan(store, ["Invoice from the scan"])
        _ = try await store.indexEmbeddedText("Invoice from the file", for: pages[0].id, expecting: pages[0].content)

        let hits = pageHits(try await store.searchHits("invoice"))

        #expect(hits.count == 1)
        #expect(hits.first?.source == .pageText)
        #expect(hits.first?.snippet.text == "Invoice from the file")
    }

    @Test func typedTextIsFoundAndSaysSo() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages) = try await scan(store, [nil])
        let box = TextBox(frame: CGRect(x: 10, y: 10, width: 200, height: 40), text: "Reimburse by Friday")
        try await store.saveObject(PageObject(pageID: pages[0].id, zKey: "m", payload: .text(box), modifiedAt: Date()))

        let hit = try #require(pageHits(try await store.searchHits("reimburse")).first)
        #expect(hit.source == .typed)
        #expect(hit.pageNumber == 1)
    }

    /// The document list already shows a title match; the hit is in the API so
    /// the type is honest about it, with no page.
    @Test func aTitleMatchHasNoPageAndComesFirst() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, _) = try await scan(store, name: "Invoice archive", [nil, "Invoice total 42"])

        let hits = try await store.searchHits("invoice")

        #expect(hits.map(\.source) == [.title, .recognized])
        #expect(hits.first?.itemID == item.id && hits.first?.pageID == nil && hits.first?.pageNumber == nil)
    }

    @Test func oneLongDocumentCannotFillTheList() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, (1...6).map { "Invoice page \($0)" })

        #expect(pageHits(try await store.searchHits("invoice")).map(\.pageNumber) == [1, 2, 3], "three per document")
        #expect(pageHits(try await store.searchHits("invoice", perItem: 10, limit: 4)).count == 4)
    }

    @Test func documentsComeInTheOrderSearchReturnsThem() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (older, _) = try await scan(store, name: "Older", ["Invoice one"])
        let (newer, _) = try await scan(store, name: "Newer", ["Invoice two"])

        let hits = try await store.searchHits("invoice")
        let itemsInOrder = hits.map(\.itemID).reduce(into: [ItemID]()) { if !$0.contains($1) { $0.append($1) } }

        #expect(itemsInOrder == (try await store.search("invoice")))
        #expect(Set(itemsInOrder) == [older.id, newer.id])
    }

    /// The screen asks only for the documents it shows. They are narrowed to
    /// before the caps, or newer documents elsewhere would use them up.
    @Test func hitsAreNarrowedToTheGivenDocumentsBeforeAnyCap() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (wanted, _) = try await scan(store, name: "Wanted", ["Invoice in the folder"])
        for index in 0..<2 { _ = try await scan(store, name: "Other \(index)", ["Invoice A", "Invoice B", "Invoice C"]) }

        let narrowed = pageHits(try await store.searchHits("invoice", among: [wanted.id], limit: 3))

        #expect(narrowed.map(\.itemID) == [wanted.id])
        #expect(try await store.searchHits("invoice", among: []).isEmpty)
    }

    // MARK: - Only current words

    @Test func wordsReadOffPaperThatIsGoneAreNotHitsButCorrectionsAre() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, pages) = try await scan(store, ["Invocie total 42"])

        let read = try #require(try await store.recognition(for: pages[0].id))
        try await store.correctRecognition(on: pages[0].id, expected: read, texts: ["Invoice total 42"])
        #expect(pageHits(try await store.searchHits("invoice")).first?.itemID == item.id)
        #expect(try await store.searchHits("invocie").isEmpty)

        let current = try #require(try await store.page(pages[0].id))
        let fresh = try store.assets.store(Data("rescanned".utf8), kind: .png, originalFilename: "again.png")
        _ = try await store.replacePageContent(pages[0].id, with: .init(sourceSize: current.sourceSize,
                                                                        content: .image(fresh.id),
                                                                        transform: current.transform), assets: [fresh])
        #expect(try await store.searchHits("invoice").isEmpty, "the words describe paper that is no longer there")
    }

    /// Whatever is typed is words to find, never an FTS command: punctuation
    /// is dropped, and `OR` or `NEAR` are words that must be on the page.
    @Test func searchSyntaxInTheQueryIsJustText() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await scan(store, ["Invoice total 42"])

        for query in ["\"invoice", "invoice*", "-invoice", "^invoice:", "(invoice)"] {
            #expect(pageHits(try await store.searchHits(query)).count == 1, "\(query)")
        }
        // As operators these would match the page, or fail to parse. As words
        // they are not on it.
        for query in ["invoice OR", "NEAR(invoice", "invoice AND NOT total"] {
            #expect(try await store.searchHits(query).isEmpty, "\(query)")
        }
        #expect(try await store.searchHits("   ").isEmpty)
        #expect(try await store.searchHits("*").isEmpty)
    }

    // MARK: - Reading the marks

    @Test func marksThatDoNotPairUpGiveThePlainText() {
        let open = SearchSnippet.openMark, close = SearchSnippet.closeMark
        let good = SearchSnippet(marked: "Total \(open)due\(close) now")
        #expect(good.runs == [.init(text: "Total ", isMatch: false), .init(text: "due", isMatch: true),
                              .init(text: " now", isMatch: false)])

        let unclosed = SearchSnippet(marked: "Total \(open)due now")
        #expect(unclosed.runs == [.init(text: "Total due now", isMatch: false)])
        let stray = SearchSnippet(marked: "Total \(close)due now")
        #expect(stray.runs == [.init(text: "Total due now", isMatch: false)])
        #expect(!stray.hasMatch)
    }

    @Test func spaceIsTidiedAcrossRuns() {
        let open = SearchSnippet.openMark, close = SearchSnippet.closeMark
        let snippet = SearchSnippet(marked: "\n  Total  \n \(open)due\(close)\(open)now\(close)   \n")
        #expect(snippet.runs == [.init(text: "Total ", isMatch: false), .init(text: "duenow", isMatch: true)])
        #expect(snippet.text == "Total duenow")
    }
}

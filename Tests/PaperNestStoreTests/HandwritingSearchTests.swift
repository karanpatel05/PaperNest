import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Handwriting made findable (schema v17): a reading kept against the page's
/// ink count, its confident words in the search index only while it is of
/// the ink as it now is, and every kind of ink change taking them out.
@Suite struct HandwritingSearchTests {
    private static let engine = "vision.handwriting.test"

    private func notebook(_ store: LibraryStore, name: String = "Journal") async throws -> (LibraryItem, Page) {
        let item = try await store.createItem(kind: .notebook, name: name, pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        return (item, try #require(try await store.pages(of: item.id).first))
    }

    private func stroke(on page: Page, _ key: String, tool: InkStroke.Tool = .pen) -> PageObject {
        PageObject(pageID: page.id, zKey: key, payload: .ink(InkStroke(
            tool: tool, color: .black, width: 2, points: [InkPoint(x: 100, y: 100), InkPoint(x: 140, y: 130)])),
                   modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func reading(_ page: Page, generation: Int, _ lines: [(String, Double)], status: HandwritingRecognitionResult.Status = .completed,
                         engine: String = HandwritingSearchTests.engine) -> HandwritingRecognitionResult {
        HandwritingRecognitionResult(pageID: page.id, inkGeneration: generation, engineVersion: engine, status: status,
                                     languages: ["en-US"], lines: lines.map {
                                         .init(text: $0.0, confidence: $0.1, bounds: CGRect(x: 100, y: 100, width: 80, height: 30))
                                     })
    }

    @Test func aPageWithInkNeedsReadingAndAReadingMakesItFindable() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await notebook(store)
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).isEmpty, "no ink, nothing to read")

        try await store.saveObject(stroke(on: page, "T"))
        let needing = try await store.pagesNeedingHandwriting(engineVersion: Self.engine)
        #expect(needing.map(\.page.id) == [page.id])
        let generation = try #require(needing.first?.inkGeneration)
        #expect(generation == (try await store.inkGeneration(of: page.id)))

        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("plan quokka lunch", 1)])))
        #expect(try await store.search("quokka") == [item.id])
        let hit = try #require(try await store.searchHits("quokka").first { $0.pageID == page.id })
        #expect(hit.source == .handwritten)
        #expect(!hit.mayBeMisread)
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).isEmpty, "read, and current")
        #expect(try await store.currentHandwriting(on: page.id)?.searchableText == "plan quokka lunch")
    }

    /// Ink written while the reading ran: the reading describes ink that is
    /// gone, so nothing is kept and nothing becomes findable.
    @Test func aReadingOfInkThatHasSinceChangedIsNotKept() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        let generation = try await store.inkGeneration(of: page.id)
        try await store.saveObject(stroke(on: page, "U"))

        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)])) == false)
        #expect(try await store.search("quokka").isEmpty)
        #expect(try await store.handwriting(on: page.id) == nil)
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).map(\.page.id) == [page.id])
    }

    /// Adding, moving and erasing a stroke each take the page's handwriting
    /// out of search at once, and leave it to be read again. Every one goes
    /// through a different write: a plain save, the guarded edit path, a
    /// delete, and a stroke recoloured through `editInk`.
    @Test func everyInkChangeTakesTheWordsOutAtOnce() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        let first = stroke(on: page, "T")
        try await store.saveObject(first)

        func readNow() async throws {
            let generation = try await store.inkGeneration(of: page.id)
            #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)])))
            #expect(try await store.search("quokka").count == 1)
        }
        func expectGone(_ what: String) async throws {
            #expect(try await store.search("quokka").isEmpty, "\(what) left the old words findable")
            #expect(try await store.currentHandwriting(on: page.id) == nil, "\(what) left the reading current")
        }

        try await readNow()
        try await store.saveObject(stroke(on: page, "U"))
        try await expectGone("a new stroke")

        try await readNow()
        var moved = first
        if case .ink(var ink) = moved.payload {
            ink.points = ink.points.map { InkPoint(x: $0.x + 30, y: $0.y) }
            moved.payload = .ink(ink)
        }
        _ = try await store.applyInkChanges(on: page.id, saving: [moved], replacing: [first], deleting: [])
        try await expectGone("a moved stroke")

        try await readNow()
        let current = try await store.objects(on: page.id)
        let page2 = try #require(try await store.page(page.id))
        _ = try await store.editInk(on: page.id, expectedRevision: page2.revision, objects: [current[0]],
                                    edit: .recolor(RGBAColor(red: 0.8, green: 0.1, blue: 0.1)))
        try await expectGone("a recoloured stroke")

        try await readNow()
        try await store.deleteObject(current[1].id)
        try await expectGone("an erased stroke")
    }

    /// A text box, an image or a comment is not ink: the reading stays
    /// current and findable.
    @Test func aTextBoxLeavesTheReadingAlone() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        let generation = try await store.inkGeneration(of: page.id)
        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)])))

        _ = try await store.placeText("Typed", on: page.id, frame: CGRect(x: 10, y: 10, width: 100, height: 30),
                                  fontSize: 14, color: .black, alignment: .leading)
        #expect(try await store.inkGeneration(of: page.id) == generation)
        #expect(try await store.search("quokka").count == 1)
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).isEmpty)
    }

    @Test func aNewEngineReadsThePageAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        let generation = try await store.inkGeneration(of: page.id)
        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)], engine: "old")))
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).map(\.page.id) == [page.id])
        #expect(try await store.pagesNeedingHandwriting(engineVersion: "old").isEmpty)
    }

    /// Unsure lines are findable and say so; noise below Vision's unsure step
    /// is not findable at all, and a failed reading makes nothing findable but
    /// stops the page being read on every pass.
    @Test func confidenceDecidesWhatIsFindableAndWhatIsMarkedUnsure() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        let generation = try await store.inkGeneration(of: page.id)

        #expect(try await store.saveHandwriting(reading(page, generation: generation,
                                                        [("quokka", 0.5), ("wombat", 0.3)])))
        #expect(try await store.search("quokka").count == 1)
        #expect(try await store.search("wombat").isEmpty, "below the unsure step is noise")
        #expect(try await store.searchHits("quokka").first { $0.pageID == page.id }?.mayBeMisread == true)

        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)], status: .failed)))
        #expect(try await store.search("quokka").isEmpty)
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).isEmpty, "a failure is not retried every pass")
    }

    /// A page in the trash, or a document in Recently Deleted, is neither read
    /// nor found.
    @Test func deletedPagesAndDocumentsAreNeitherReadNorFound() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await notebook(store)
        let (other, otherPage) = try await notebook(store, name: "Diary")
        for p in [page, otherPage] {
            try await store.saveObject(stroke(on: p, "T"))
            let generation = try await store.inkGeneration(of: p.id)
            #expect(try await store.saveHandwriting(reading(p, generation: generation, [("quokka", 1)])))
        }
        #expect(Set(try await store.search("quokka")) == [item.id, other.id])

        try await store.deletePages([page.id])
        try await store.moveToRecentlyDeleted([other.id])
        #expect(try await store.search("quokka").isEmpty)
        #expect(try await store.searchHits("quokka").isEmpty)
        try await store.saveObject(stroke(on: otherPage, "U"))
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).isEmpty)
    }

    /// Erased for good, a page takes its reading and ink count with it.
    @Test func aPurgedPageTakesItsReadingWithIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        let generation = try await store.inkGeneration(of: page.id)
        #expect(try await store.saveHandwriting(reading(page, generation: generation, [("quokka", 1)])))
        try await store.deletePages([page.id])
        #expect(try await store.purgeDeletedPages() == 1)
        #expect(try await store.handwriting(on: page.id) == nil)
        #expect(try await store.testRowCount("page_ink_generation") == 0)
        #expect(try await store.integrityCheck().isEmpty)
    }

    /// A library from v16 opens at v17: its ink is read for the first time,
    /// and v17 adds exactly the three handwriting triggers to the ones it had.
    @Test func aLibraryFromSchemaSixteenOpensAndItsInkIsRead() async throws {
        let dir = TempDirectory()
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 16 { try raw.execute(migration.sql) }
        try raw.setUserVersion(16)
        let before = Set(try raw.query("SELECT name FROM sqlite_master WHERE type = 'trigger'") { $0.text(0) })
        raw.close()

        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.schemaVersion() == 17)
        let after = try await store.testAllTriggerNames()
        #expect(before.isSubset(of: after), "every earlier trigger, sync's included, is still there")
        #expect(after.subtracting(before) == Self.handwritingTriggers)
        let (_, page) = try await notebook(store)
        try await store.saveObject(stroke(on: page, "T"))
        #expect(try await store.pagesNeedingHandwriting(engineVersion: Self.engine).map(\.page.id) == [page.id])
    }

    static let handwritingTriggers: Set<String> = ["handwriting_ink_inserted", "handwriting_ink_updated", "handwriting_ink_deleted"]
}

extension LibraryStore {
    func testRowCount(_ table: String) throws -> Int {
        try db.query("SELECT COUNT(*) FROM \(table)") { $0.int(0) }.first ?? 0
    }
}

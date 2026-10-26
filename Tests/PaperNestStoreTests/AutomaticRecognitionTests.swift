import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F4: recognition should happen without being asked. The store decides which
/// pages still need it, from what is already stored rather than from a queue,
/// so a pass can be interrupted and resumed and nothing is read twice.
@Suite struct AutomaticRecognitionTests {
    private let engine = "test.engine.1"

    private func seedScan(_ store: LibraryStore, name: String = "Scan") async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data("scan bytes".utf8), kind: .png, originalFilename: "scan.png")
        let item = try await store.createItem(kind: .document, name: name, pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    private func result(_ page: Page, _ status: PageRecognition.Status,
                        engineVersion: String? = nil, text: String = "Some words") -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision,
                        engineVersion: engineVersion ?? engine, status: status, languages: ["en-US"],
                        lines: status == .completed ? [RecognizedLine(text: text, box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.02), confidence: 0.9)] : [])
    }

    private func needing(_ store: LibraryStore) async throws -> [PageID] {
        try await store.pagesNeedingRecognition(engineVersion: engine).map(\.id)
    }

    @Test func aPageNobodyHasReadYetNeedsRecognition() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)

        #expect(try await needing(store) == [page.id])
    }

    @Test func aFinishedResultForThePageAsItIsNeedsNothingMore() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        try await store.saveRecognition(result(page, .completed))

        #expect(try await needing(store).isEmpty)
    }

    @Test func aRescannedPageIsReadAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        try await store.saveRecognition(result(page, .completed, text: "Original words"))
        #expect(try await needing(store).isEmpty)

        let fresh = try store.assets.store(Data("rescanned bytes".utf8), kind: .png, originalFilename: "again.png")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize,
                                                                    content: .image(fresh.id),
                                                                    transform: page.transform),
                                               assets: [fresh])

        // The page shows different paper, so its text describes nothing now.
        #expect(try await needing(store) == [page.id])
    }

    @Test func anUnfinishedResultIsPickedUpAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        try await store.saveRecognition(result(page, .pending))

        #expect(try await needing(store) == [page.id], "a request that never finished is not a result")
    }

    @Test func aResultFromAnotherEngineIsRedone() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        try await store.saveRecognition(result(page, .completed, engineVersion: "old.engine.0"))

        #expect(try await needing(store) == [page.id])
    }

    @Test func aPageThatCouldNotBeReadIsNotRetriedForever() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        try await store.saveRecognition(result(page, .failed))

        // Same paper, same engine: reading it again would fail again. A rescan
        // or a new engine is what earns another attempt.
        #expect(try await needing(store).isEmpty)
    }

    @Test func aPDFThatAlreadyCarriesItsOwnTextIsNotRead() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("%PDF-1.7 synthetic".utf8), kind: .pdf, originalFilename: "statement.pdf")
        let item = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let page = try await store.pages(of: item.id)[0]

        try await store.indexEmbeddedText("Monthly rent 1200 EUR", for: page.id, expecting: page.content)

        #expect(try await needing(store).isEmpty,
                "the PDF's own words beat a reading of a raster of those words")
    }

    @Test func aScanInsideAPDFWithNoTextLayerStillNeedsReading() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("%PDF-1.7 scanned".utf8), kind: .pdf, originalFilename: "scanned.pdf")
        let item = try await store.createItem(kind: .document, name: "Scanned", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let page = try await store.pages(of: item.id)[0]

        // An empty marker means "looked, no text layer" — the OCR case.
        try await store.indexEmbeddedText(nil, for: page.id, expecting: page.content)

        #expect(try await needing(store) == [page.id])
    }

    @Test func thereIsNothingToReadOnABlankNotebookPage() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Notes", pages: [
            .init(sourceSize: CGSize(width: 595, height: 842), content: .template(.blank)),
        ], assets: [])
        _ = item

        #expect(try await needing(store).isEmpty)
    }

    @Test func deletedPagesAndDeletedDocumentsAreLeftAlone() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (keptItem, keptPage) = try await seedScan(store, name: "Kept")
        let (goneItem, _) = try await seedScan(store, name: "Gone")

        try await store.moveToRecentlyDeleted([goneItem.id])
        #expect(try await needing(store) == [keptPage.id])

        try await store.deletePages([keptPage.id])
        #expect(try await needing(store).isEmpty)
        _ = keptItem
    }

    @Test func aPageWhoseOriginalIsNotOnThisDeviceIsLeftAlone() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedScan(store)
        #expect(try await needing(store) == [page.id])

        // Sync has not arrived yet, but the column it will use exists.
        try await store.markAssetsRemoteOnlyForTesting()

        #expect(try await needing(store).isEmpty, "reading a page whose paper is not here would fail every pass")
    }
}

extension LibraryStore {
    /// Test-only: there is no code path that creates a remote-only asset until
    /// sync lands, but the query has to behave when one exists.
    func markAssetsRemoteOnlyForTesting() throws {
        try db.run("UPDATE assets SET availability = 'remoteOnly'")
    }
}

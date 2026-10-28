import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Row 36's navigation half, for one explicitly named format: a PDF's own
/// outline. The interesting part is that the outline belongs to the *file* and
/// a PaperNest document is not that file — pages get reordered, cropped and
/// deleted, and entries have to be resolved against what the document shows
/// now rather than trusted as indices.
@Suite struct DocumentOutlineTests {
    private func library() -> (URL, LibraryStore)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestOutline-\(UUID().uuidString)", isDirectory: true)
        return (try? LibraryStore(directory: url)).map { (url, $0) }
    }

    private let chaptered = SyntheticDocuments.outlinedPDF(
        pages: ["One", "Two", "Three", "Four"],
        entries: [("Beginning", 0, [("A note", 1)]), ("Middle", 2, []), ("End", 3, [])])

    @Test func anOutlineComesBackInTheAuthorsOrderWithItsPages() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store).importItem(.data(chaptered, name: "Book"))
        let pages = try await store.pages(of: item.id)

        let outline = try await PageRenderer(store: store).outline(for: pages)

        #expect(outline.map(\.title) == ["Beginning", "A note", "Middle", "End"])
        #expect(outline.map(\.depth) == [0, 1, 0, 0], "nesting was flattened")
        #expect(outline[0].pageID == pages[0].id)
        #expect(outline[1].pageID == pages[1].id)
        #expect(outline[2].pageID == pages[2].id)
        #expect(outline[3].pageID == pages[3].id)
    }

    @Test func aPDFWithoutAnOutlineYieldsNoneRatherThanFailing() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: ["Just one"]), name: "Plain"))
        let pages = try await store.pages(of: item.id)

        #expect(try await PageRenderer(store: store).outline(for: pages).isEmpty)
    }

    /// An outline that leads somewhere the document no longer has is worse
    /// than no outline.
    @Test func anEntryWhosePageWasDeletedIsDropped() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store).importItem(.data(chaptered, name: "Book"))
        var pages = try await store.pages(of: item.id)
        // The reader deleted the middle chapter's page.
        _ = try await store.deletePages([pages[2].id])
        pages = try await store.pages(of: item.id)

        let outline = try await PageRenderer(store: store).outline(for: pages)

        #expect(outline.map(\.title) == ["Beginning", "A note", "End"])
        #expect(outline.allSatisfy { entry in pages.contains { $0.id == entry.pageID } },
                "an entry points at a page the document does not have")
    }

    /// Two files merged into one document each keep their own contents page.
    @Test func aDocumentBuiltFromTwoPDFsGetsBothOutlines() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let importer = DocumentImporter(store: store)
        let first = try await importer.importItem(.data(chaptered, name: "Book"))
        let second = try await importer.importItem(
            .data(SyntheticDocuments.outlinedPDF(pages: ["Appendix page"],
                                                 entries: [("Appendix", 0, [])]), name: "Extra"))
        let pages = try await store.pages(of: first.id) + store.pages(of: second.id)

        let outline = try await PageRenderer(store: store).outline(for: pages)

        #expect(outline.map(\.title) == ["Beginning", "A note", "Middle", "End", "Appendix"])
        #expect(outline.last?.pageID == pages.last?.id)
    }

    /// Image and template pages carry no outline, and saying so is not an error.
    @Test func aScanContributesNothing() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store).importItem(
            .data(SyntheticDocuments.textImage(lines: ["A scan"]), name: "Scan"))
        let pages = try await store.pages(of: item.id)

        #expect(try await PageRenderer(store: store).outline(for: pages).isEmpty)
    }
}

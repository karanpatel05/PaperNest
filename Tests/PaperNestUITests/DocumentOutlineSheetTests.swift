import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Row 36's contents sheet. The engine that reads a PDF's outline is covered in
/// `DocumentOutlineTests`; what is new here is the one decision the sheet makes
/// for itself — which page an entry should open.
@Suite struct DocumentOutlineSheetTests {
    private func seededDocument() async throws -> (URL, [Page], [DocumentOutlineEntry]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestOutlineSheet-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.outlinedPDF(
            pages: ["Cover", "Terms", "Schedule"],
            entries: [("Terms", 1, [("Rent", 1)]), ("Schedule", 2, [])])
        let item = try await DocumentImporter(store: store).importItem(.data(data, name: "Lease"))
        let pages = try await store.pages(of: item.id)
        let entries = try await PageRenderer(store: store).outline(for: pages)
        return (directory, pages, entries)
    }

    @Test func anEntryOpensThePageItPointsAt() async throws {
        let (directory, pages, entries) = try await seededDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try #require(entries.first)

        #expect(DocumentOutlineSheet.pageToSelect(entry, in: pages) == entry.pageID)
    }

    /// The sheet holds the outline it read when it opened. A page deleted while
    /// it is open would otherwise select an id the document no longer has,
    /// leaving the editor showing nothing — so an entry whose page is gone
    /// opens nothing instead.
    @Test func anEntryWhosePageHasGoneOpensNothing() async throws {
        let (directory, pages, entries) = try await seededDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try #require(entries.first)
        let remaining = pages.filter { $0.id != entry.pageID }

        #expect(DocumentOutlineSheet.pageToSelect(entry, in: remaining) == nil)
        // The other entries are unaffected: one page going does not break the rest.
        if let other = entries.first(where: { $0.pageID != entry.pageID }) {
            #expect(DocumentOutlineSheet.pageToSelect(other, in: remaining) == other.pageID)
        }
    }
}

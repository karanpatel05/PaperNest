import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// What the editor shows side by side, worked out from real pages.
@MainActor @Suite struct TwoPageViewTests {
    private func pages(_ sizes: [CGSize]) async throws -> (URL, [Page]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestTwoPage-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        let importer = DocumentImporter(store: store)
        var all: [Page] = []
        // One document whose pages have these sizes, page by page.
        let item = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["1"], size: sizes[0]), name: "Book"))
        all = try await store.pages(of: item.id)
        for size in sizes.dropFirst() {
            let more = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["n"], size: size), name: "More"))
            all += try await store.pages(of: more.id)
        }
        return (url, all)
    }

    private static let portrait = CGSize(width: 612, height: 792)
    private static let landscape = CGSize(width: 792, height: 612)

    @Test func theSpreadOfThePageBeingRead() async throws {
        let (url, all) = try await pages(Array(repeating: Self.portrait, count: 4))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TwoPageView.spread(for: all[1], in: all, coverAlone: false).map(\.id) == [all[0].id, all[1].id])
        #expect(TwoPageView.spread(for: all[2], in: all, coverAlone: false).map(\.id) == [all[2].id, all[3].id])
        #expect(TwoPageView.spread(for: all[2], in: all, coverAlone: true).map(\.id) == [all[1].id, all[2].id])
        #expect(TwoPageView.spread(for: all[0], in: all, coverAlone: true).map(\.id) == [all[0].id])
        #expect(TwoPageView.spread(for: nil, in: all, coverAlone: false).isEmpty)
    }

    /// A landscape page stands alone, and so does the page before it.
    @Test func aLandscapePageStandsAlone() async throws {
        let (url, all) = try await pages([Self.portrait, Self.landscape, Self.portrait, Self.portrait])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TwoPageView.spread(for: all[0], in: all, coverAlone: false).map(\.id) == [all[0].id])
        #expect(TwoPageView.spread(for: all[1], in: all, coverAlone: false).map(\.id) == [all[1].id])
        #expect(TwoPageView.spread(for: all[3], in: all, coverAlone: false).map(\.id) == [all[2].id, all[3].id])
    }

    /// Previous and next step a spread at a time, from either page of it.
    @Test func previousAndNextStepASpread() async throws {
        let (url, all) = try await pages(Array(repeating: Self.portrait, count: 5))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TwoPageView.step(from: all[0].id, by: 1, in: all, coverAlone: false) == all[2].id)
        #expect(TwoPageView.step(from: all[1].id, by: 1, in: all, coverAlone: false) == all[2].id,
                "next from the right page of a spread stayed in it")
        #expect(TwoPageView.step(from: all[3].id, by: -1, in: all, coverAlone: false) == all[0].id)
        #expect(TwoPageView.step(from: all[4].id, by: 1, in: all, coverAlone: false) == nil)
        #expect(TwoPageView.step(from: all[0].id, by: -1, in: all, coverAlone: false) == nil)
        // With the cover alone: 1 | 2-3 | 4-5.
        #expect(TwoPageView.step(from: all[0].id, by: 1, in: all, coverAlone: true) == all[1].id)
        #expect(TwoPageView.step(from: all[2].id, by: 1, in: all, coverAlone: true) == all[3].id)
    }

    @Test func eachPageOfASpreadGetsItsShareOfTheWidth() {
        let viewport = CGSize(width: 1012, height: 700)
        #expect(TwoPageView.room(for: 1, in: viewport) == viewport)
        let half = TwoPageView.room(for: 2, in: viewport)
        #expect(half.width == (1012 - TwoPageView.gap) / 2)
        #expect(half.height == 700)
        #expect(TwoPageView.room(for: 2, in: CGSize(width: 4, height: 10)).width >= 1)
    }

    @Test func aThrowawayLibraryStartsWithOnePageAtATime() {
        let defaults = UserDefaults(suiteName: "TwoPageViewTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: TwoPageView.storageKey)
        defaults.set(true, forKey: TwoPageView.coverKey)
        TwoPageView.resetForThrowawayLibrary(defaults)
        #expect(defaults.object(forKey: TwoPageView.storageKey) == nil)
        #expect(defaults.object(forKey: TwoPageView.coverKey) == nil)
    }
}

import PaperNestCore
import SwiftUI

/// Two-page view: a document shown a spread at a time, two pages side by side,
/// where the window is wide enough for it (an iPad, a Mac — not a phone).
///
/// A preference, like night mode: nothing about the document changes. The
/// pairing is `PageSpreads`'. Only documents use it; a notebook scrolls its
/// pages in one column.
enum TwoPageView {
    static let storageKey = "reader.twoPages"
    static let coverKey = "reader.twoPages.coverAlone"
    /// Between the two pages of a spread, in points.
    static let gap: CGFloat = 12

    /// Every UI test and development run starts with a throwaway library and
    /// one page at a time, so a test does not inherit the last run's layout.
    @MainActor static func resetForThrowawayLibrary(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: coverKey)
    }

    /// The pages to show side by side with `selected`: its spread, or just it
    /// when two-page view is off or it is in no spread.
    static func spread(for selected: Page?, in pages: [Page], coverAlone: Bool) -> [Page] {
        guard let selected else { return [] }
        let spreads = PageSpreads.spreads(of: pages.map { ($0.id, $0.geometry.pageSize) }, coverAlone: coverAlone)
        guard let ids = PageSpreads.spread(containing: selected.id, in: spreads) else { return [selected] }
        return ids.compactMap { id in pages.first { $0.id == id } }
    }

    /// Where the editor's previous/next buttons go from `selected` in two-page
    /// view: the first page of the spread before or after its own, as
    /// Acrobat steps — not the other page of the same spread. Nil past either
    /// end.
    static func step(from selected: PageID, by delta: Int, in pages: [Page], coverAlone: Bool) -> PageID? {
        let spreads = PageSpreads.spreads(of: pages.map { ($0.id, $0.geometry.pageSize) }, coverAlone: coverAlone)
        guard let here = spreads.firstIndex(where: { $0.contains(selected) }) else { return nil }
        let there = here + delta
        guard spreads.indices.contains(there) else { return nil }
        return spreads[there].first
    }

    /// The room each page of a spread of `count` gets in a viewport of `size`.
    static func room(for count: Int, in size: CGSize) -> CGSize {
        guard count > 1 else { return size }
        return CGSize(width: max((size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1), height: size.height)
    }
}

/// Display settings' Reading section: night mode, and two-page view where
/// there is room for it.
struct ReadingSection: View {
    var nightMode: Binding<Bool>?
    var twoPages: Binding<Bool>?
    var coverAlone: Binding<Bool>?

    var body: some View {
        PanelSection(title: L10n.displayReading) {
            if let nightMode {
                PanelToggleRow(title: L10n.nightMode, systemImage: "moon", isOn: nightMode,
                               id: "display-night-mode", detail: L10n.nightModeDetail)
            }
            if let twoPages {
                PanelToggleRow(title: L10n.twoPages, systemImage: "book", isOn: twoPages,
                               id: "display-two-pages", detail: L10n.twoPagesDetail)
                if twoPages.wrappedValue, let coverAlone {
                    PanelToggleRow(title: L10n.twoPagesCover, systemImage: "book.closed", isOn: coverAlone,
                                   id: "display-two-pages-cover", detail: L10n.twoPagesCoverDetail)
                }
            }
        }
    }
}

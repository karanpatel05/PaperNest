import CoreGraphics
import Foundation

/// How pages pair up side by side in two-page view.
///
/// Pages go in pairs, left then right, in document order — the way Acrobat
/// and Preview show "two pages". Two things stand alone:
///
/// - **A wide page.** A landscape page next to a portrait one would shrink
///   both to fit; shown alone, it gets the width it needs. A page counts as
///   wide when it is wider than it is tall.
/// - **The cover**, when asked for: a book's first page is its right-hand
///   page, so with the cover alone page 2 faces page 3, as the printed book
///   does.
///
/// The page before a wide page stands alone too, rather than being paired
/// across it out of order.
public enum PageSpreads {
    /// Each spread's pages, left to right: one or two page IDs.
    public static func spreads(of pages: [(id: PageID, size: CGSize)], coverAlone: Bool) -> [[PageID]] {
        var result: [[PageID]] = []
        var waiting: PageID?
        for (index, page) in pages.enumerated() {
            if isWide(page.size) || (coverAlone && index == 0) {
                if let left = waiting { result.append([left]); waiting = nil }
                result.append([page.id])
            } else if let left = waiting {
                result.append([left, page.id])
                waiting = nil
            } else {
                waiting = page.id
            }
        }
        if let left = waiting { result.append([left]) }
        return result
    }

    /// The spread `id` is in, or nil when it is in none.
    public static func spread(containing id: PageID, in spreads: [[PageID]]) -> [PageID]? {
        spreads.first { $0.contains(id) }
    }

    static func isWide(_ size: CGSize) -> Bool {
        size.width > size.height
    }
}

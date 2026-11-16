/// Edits to several pages of the scanner's draft queue at once.
///
/// Each takes the queue and the index of the page being shown, and gives
/// back both, so the page on screen stays the same page whenever it survives.
public enum ScanPageBatch {
    public enum Direction: Sendable { case earlier, later }

    public struct Result<Page: Identifiable> {
        public var pages: [Page]
        /// Index of the page to show. 0 when the queue is empty.
        public var focus: Int
    }

    public struct Duplication<Page: Identifiable> {
        public var pages: [Page]
        public var focus: Int
        public var copies: Set<Page.ID>
    }

    /// Removes the chosen pages. When the page being shown goes, the next
    /// page left takes its place, or the last one when none follows.
    public static func delete<Page: Identifiable>(_ ids: Set<Page.ID>, from pages: [Page], focus: Int) -> Result<Page> {
        let kept = pages.filter { !ids.contains($0.id) }
        // The pages kept from before the shown one all stay ahead of it, so
        // their count is where it lands, or where the page after it lands.
        let before = pages.prefix(max(0, focus)).filter { !ids.contains($0.id) }.count
        return Result(pages: kept, focus: max(0, min(before, kept.count - 1)))
    }

    /// Puts a copy of each chosen page straight after it.
    public static func duplicate<Page: Identifiable>(
        _ ids: Set<Page.ID>, in pages: [Page], focus: Int, copy: (Page) -> Page
    ) -> Duplication<Page> {
        var result: [Page] = []
        result.reserveCapacity(pages.count + ids.count)
        var copies = Set<Page.ID>()
        var shownAt = focus
        for (index, page) in pages.enumerated() {
            if index == focus { shownAt = result.count }
            result.append(page)
            guard ids.contains(page.id) else { continue }
            let duplicate = copy(page)
            copies.insert(duplicate.id)
            result.append(duplicate)
        }
        return Duplication(pages: result, focus: shownAt, copies: copies)
    }

    /// Moves the chosen pages one place as a block, keeping their order.
    /// Pages chosen from different places are gathered into one block first.
    public static func move<Page: Identifiable>(
        _ ids: Set<Page.ID>, _ direction: Direction, in pages: [Page], focus: Int
    ) -> Result<Page> {
        let moving = pages.filter { ids.contains($0.id) }
        let staying = pages.filter { !ids.contains($0.id) }
        guard !moving.isEmpty, !staying.isEmpty,
              let first = pages.firstIndex(where: { ids.contains($0.id) }),
              let last = pages.lastIndex(where: { ids.contains($0.id) }) else {
            return Result(pages: pages, focus: focus)
        }
        // Where the block goes among the pages that stay: one before the
        // pages ahead of its first page, or one after those ahead of its last.
        let slot: Int
        switch direction {
        case .earlier: slot = max(0, pages[..<first].count - 1)
        case .later: slot = min(staying.count, pages[..<last].filter { !ids.contains($0.id) }.count + 1)
        }
        var result = staying
        result.insert(contentsOf: moving, at: slot)
        let shown = pages.indices.contains(focus) ? result.firstIndex { $0.id == pages[focus].id } : nil
        return Result(pages: result, focus: shown ?? focus)
    }

    /// Whether `move` would change the order.
    public static func canMove<Page: Identifiable>(_ ids: Set<Page.ID>, _ direction: Direction, in pages: [Page]) -> Bool {
        let moved = move(ids, direction, in: pages, focus: 0).pages
        return zip(moved, pages).contains { $0.id != $1.id }
    }

    /// Applies one edit to each chosen page.
    public static func update<Page: Identifiable>(_ ids: Set<Page.ID>, in pages: inout [Page], _ edit: (inout Page) -> Void) {
        for index in pages.indices where ids.contains(pages[index].id) { edit(&pages[index]) }
    }
}

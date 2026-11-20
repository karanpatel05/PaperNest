import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// Puts the words read from handwriting on its page as a text box, and
    /// takes the handwriting away unless `keepingInk`, in one transaction.
    ///
    /// The words are the ones the person reviewed, not the raw reading. The
    /// box is typed text like any other: it is drawn, exported and found by
    /// search the way a box typed by hand is, through the same write. The
    /// strokes it came from are checked first: if any one is no longer
    /// exactly as it was read (moved, recoloured, erased), nothing is written,
    /// because the words would describe ink that is not there.
    ///
    /// Returns the page as it now is, the box, and the strokes taken away
    /// (none when kept), which is what an undo needs to put back.
    public func convertHandwriting(on pageID: PageID, strokes expected: [PageObject], text: String, frame: CGRect,
                                   fontSize: Double, color: RGBAColor, keepingInk: Bool) throws
        -> (page: Page, text: PageObject, removed: [PageObject]) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, fontSize > 0, fontSize.isFinite,
              frame.width > 0, frame.height > 0, frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { throw StoreError.invalidPlacement }
        guard !expected.isEmpty, Set(expected.map(\.id)).count == expected.count else { throw StoreError.invalidOrder }
        guard expected.allSatisfy({ object in
            guard object.pageID == pageID, case .ink = object.payload else { return false }
            return true
        }) else { throw StoreError.pageObjectsChanged }

        return try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            let objects = try objects(on: pageID)
            let current = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
            guard expected.allSatisfy({ current[$0.id] == $0 }) else { throw StoreError.pageObjectsChanged }
            let box = PageObject(
                pageID: pageID, zKey: try SortKey.between(objects.last?.zKey, nil),
                payload: .text(TextBox(frame: frame, text: words, fontSize: fontSize, color: color,
                                       alignment: .leading)),
                modifiedAt: Date())
            let removed = keepingInk ? [] : expected
            let updated = try applyObjectChanges(on: pageID, saving: [box], deleting: removed.map(\.id))
            return (updated, box, removed)
        }
    }
}

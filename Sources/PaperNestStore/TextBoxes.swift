import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// Puts typed text on a page.
    ///
    /// The guarded way in, as `placeImage` is for pictures: `saveObject` would
    /// take anything, and a box the renderer cannot draw is worse than a
    /// refusal — the page would simply be missing what someone typed, with
    /// nothing to say so.
    ///
    /// The text lands **on top of** whatever the page already holds, and its
    /// place in the order is worked out inside the write, so two in a row
    /// cannot claim the same one.
    ///
    /// `frame` is in upright, uncropped source points — the same space as ink.
    /// Text longer than it is **clipped** when drawn, so a caller that cannot
    /// predict the length should give it room.
    ///
    /// Returns the page as it now is along with the object, because writing an
    /// object bumps the revision and a caller holding its old `Page` would be
    /// refused by the next guarded edit.
    ///
    /// Writing it also makes the words findable: the same write rebuilds the
    /// page's `text` index row.
    @discardableResult
    public func placeText(_ text: String, on pageID: PageID, frame: CGRect,
                          fontSize: Double, color: RGBAColor,
                          alignment: TextBox.Alignment) throws -> (page: Page, object: PageObject) {
        // Trimmed here rather than at the edges of the app, so what is stored
        // is what the index and the renderer will both see.
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw StoreError.invalidPlacement }
        guard fontSize > 0, fontSize.isFinite else { throw StoreError.invalidPlacement }
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite
        else { throw StoreError.invalidPlacement }

        let timestamp = Date()
        return try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            let key = try SortKey.between(try objects(on: pageID).last?.zKey, nil)
            let object = PageObject(
                pageID: pageID, zKey: key,
                payload: .text(TextBox(frame: frame, text: words, fontSize: fontSize,
                                       color: color, alignment: alignment)),
                modifiedAt: timestamp)
            return (try applyObjectChanges(on: pageID, saving: [object], deleting: []), object)
        }
    }
}

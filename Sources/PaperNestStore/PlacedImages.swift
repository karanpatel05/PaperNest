import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// Puts an image on a page: the bytes and the row that points at them, in
    /// one write.
    ///
    /// `staged` comes from `assets.store(…)`, which writes the file durably
    /// before anything references it. Until a row does, that file is rubbish
    /// as far as housekeeping is concerned and `sweepOrphanAssets` is entitled
    /// to take it, so the asset row and the page object are written inside one
    /// transaction. Staging and then calling `saveObject` separately leaves a
    /// window in which a sweep orphans the page — which is the reason this
    /// exists rather than being left to callers.
    ///
    /// The image lands **on top of** whatever the page already holds, and its
    /// place in the order is worked out inside the write, so two placements in
    /// a row cannot both claim the same one.
    ///
    /// `frame` is in upright, uncropped source points — the same space as ink
    /// and recognized text. It may extend past the page's edge; drawing clips
    /// to the page. The image is **stretched** to fill it, so a caller that
    /// wants the picture's own proportions kept has to work the frame out
    /// itself.
    ///
    /// Returns the page as it now is along with the object, the way `addShape`
    /// does, because writing an object bumps the page's revision: a caller
    /// holding the `Page` it started with would be refused by the next guarded
    /// edit — `addShape` compares the whole page — and must carry this one
    /// forward instead.
    @discardableResult
    public func placeImage(_ staged: AssetFileStore.StagedAsset, on pageID: PageID,
                           frame: CGRect) throws -> (page: Page, object: PageObject) {
        // Refused here rather than at drawing time. The renderer would only
        // find out when someone opened the page, and by then the object is
        // saved and the page cannot be drawn at all.
        guard staged.kind.isDrawableImage else { throw StoreError.invalidPlacement }
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite
        else { throw StoreError.invalidPlacement }

        let timestamp = Date()
        return try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            try insertAssetRows([staged], at: timestamp)
            let key = try SortKey.between(try objects(on: pageID).last?.zKey, nil)
            let object = PageObject(pageID: pageID, zKey: key,
                                    payload: .image(PlacedImage(assetID: staged.id, frame: frame)),
                                    modifiedAt: timestamp)
            return (try applyObjectChanges(on: pageID, saving: [object], deleting: []), object)
        }
    }
}

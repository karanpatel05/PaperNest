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
                          alignment: TextBox.Alignment, fontFamily: TextBox.FontFamily = .sans,
                          isBold: Bool = false, isItalic: Bool = false,
                          preserveWhitespace: Bool = false) throws -> (page: Page, object: PageObject) {
        // Inline typing retains indentation and trailing newlines; older callers
        // retain the established trimmed behavior. Invisible boxes are refused.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidPlacement }
        let words = preserveWhitespace ? text : trimmed
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
                                       color: color, alignment: alignment, fontFamily: fontFamily,
                                       isBold: isBold, isItalic: isItalic)),
                modifiedAt: timestamp)
            return (try applyObjectChanges(on: pageID, saving: [object], deleting: []), object)
        }
    }

    /// Changes a text box already on a page.
    ///
    /// A box used to be **write-once**: its words, size, colour and alignment
    /// were fixed the moment it was added, so a typo meant deleting it and
    /// typing it again. The same refusals apply as when placing one, because
    /// an empty box or one with no area is just as unusable the second time.
    ///
    /// It keeps its **id** and its place in the paint order, so undo sees one
    /// box changed rather than one deleted and another added, and so a mark
    /// does not jump above its neighbours when it is edited.
    ///
    /// The write is the guarded one: a box someone else changed first is
    /// refused rather than written over. `frame` comes from the caller, as it
    /// does for `placeText`, because how much room a box needs is a layout
    /// decision and this is not where layout lives.
    ///
    /// The same write rebuilds the page's `text` index row, so the old words
    /// stop being findable as the new ones start.
    @discardableResult
    public func updateText(_ object: PageObject, text: String, frame: CGRect, fontSize: Double,
                           color: RGBAColor, alignment: TextBox.Alignment,
                           fontFamily: TextBox.FontFamily? = nil, isBold: Bool? = nil, isItalic: Bool? = nil,
                           preserveWhitespace: Bool = false) throws -> (page: Page, object: PageObject) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidPlacement }
        let words = preserveWhitespace ? text : trimmed
        guard fontSize > 0, fontSize.isFinite else { throw StoreError.invalidPlacement }
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite
        else { throw StoreError.invalidPlacement }
        // Only a text box: anything else handed in here would be quietly
        // turned into one, losing whatever it was.
        guard case .text(let previous) = object.payload else { throw StoreError.invalidPlacement }

        var updated = object
        updated.payload = .text(TextBox(frame: frame, text: words, fontSize: fontSize,
                                        color: color, alignment: alignment,
                                        fontFamily: fontFamily ?? previous.fontFamily,
                                        isBold: isBold ?? previous.isBold, isItalic: isItalic ?? previous.isItalic))
        updated.modifiedAt = Date()
        return (try applyInkChanges(on: object.pageID, saving: [updated],
                                    replacing: [object], deleting: []), updated)
    }
}

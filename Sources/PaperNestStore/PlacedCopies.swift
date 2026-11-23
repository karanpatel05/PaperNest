import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// The most marks one paste may carry. A page with more is not something
    /// a person lassoed; refusing it keeps one paste from stalling the page.
    public static let maximumCopiedObjects = 5_000
    /// The most ink points one paste may carry, for the same reason.
    public static let maximumCopiedPoints = 1_000_000

    /// Puts copies of marks on a page, above everything it already holds, in
    /// one write — the lasso's Duplicate and Paste.
    ///
    /// Each copy must be a new mark with an id no object in the library has,
    /// so a copy can never move or overwrite an existing one, and its paint
    /// order is given here, inside the write, keeping the order the copies
    /// came in: two pastes in a row cannot both claim the same place.
    ///
    /// The copies are checked as if they came from outside the app, because
    /// they may outlive the page they were taken from: points and frames must
    /// be finite, ink visible, text not blank, and a picture's bytes still in
    /// the library (`assetMissing` otherwise). A copy of a picture shares its
    /// original's bytes, which stay as long as either is on a page. One bad
    /// copy refuses the whole paste.
    ///
    /// `expectedPage`, when given, is the page the copies were laid out for:
    /// copies placed through a crop or a turn that has since changed would
    /// land somewhere else, so the write is refused instead.
    ///
    /// Returns the page as it now is and the copies as saved, which is what an
    /// undo needs to take them away again.
    public func placeCopies(_ copies: [PageObject], on pageID: PageID,
                            expectedPage: Page? = nil) throws -> (page: Page, objects: [PageObject]) {
        guard !copies.isEmpty, copies.count <= Self.maximumCopiedObjects else { throw StoreError.invalidPlacement }
        guard Set(copies.map(\.id)).count == copies.count else { throw StoreError.invalidOrder }
        var points = 0
        for copy in copies {
            guard copy.pageID == pageID else { throw StoreError.invalidPlacement }
            switch copy.payload {
            case .ink(let stroke):
                points += stroke.points.count
                guard !stroke.points.isEmpty,
                      stroke.points.allSatisfy({ [$0.x, $0.y, $0.widthScale, $0.time].allSatisfy(\.isFinite) }),
                      stroke.width.isFinite, stroke.width > 0, stroke.color.isVisibleInkColor
                else { throw StoreError.invalidPlacement }
            case .text(let box):
                guard !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      box.fontSize.isFinite, box.fontSize > 0, Self.isUsableFrame(box.frame),
                      box.color.isVisibleInkColor
                else { throw StoreError.invalidPlacement }
            case .image(let image):
                guard Self.isUsableFrame(image.frame) else { throw StoreError.invalidPlacement }
            case .comment:
                // Private, and never painted: not something a lasso carries.
                throw StoreError.invalidPlacement
            }
        }
        guard points <= Self.maximumCopiedPoints else { throw StoreError.invalidPlacement }

        return try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            if let expectedPage, page != expectedPage { throw StoreError.pageObjectsChanged }
            for copy in copies {
                guard try db.query("SELECT id FROM page_objects WHERE id = ?", [.text(copy.id.rawValue)],
                                   map: { $0.text(0) }).isEmpty else { throw StoreError.pageObjectsChanged }
                if case .image(let image) = copy.payload {
                    let present = try db.query("SELECT count(*) FROM assets WHERE id = ?",
                                               [.text(image.assetID.sha256)]) { $0.int(0) }.first ?? 0
                    guard present == 1 else { throw StoreError.assetMissing(image.assetID.sha256) }
                }
            }
            var key = try objects(on: pageID).last?.zKey
            let placed = try copies.map { copy -> PageObject in
                let next = try SortKey.between(key, nil)
                key = next
                var placed = copy
                placed.zKey = next
                return placed
            }
            return (try applyObjectChanges(on: pageID, saving: placed, deleting: []), placed)
        }
    }

    private static func isUsableFrame(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
    }
}

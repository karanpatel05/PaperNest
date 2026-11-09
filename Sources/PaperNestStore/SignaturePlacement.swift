import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    /// Places every stroke in one transaction, against the exact previewed page.
    /// `target` is normalized to the displayed crop/rotation, not the source.
    public func placeSignature(_ signature: SavedSignature, on expected: Page,
                               target: NormalizedRect) throws -> (page: Page, objects: [PageObject]) {
        guard [target.x, target.y, target.width, target.height].allSatisfy(\.isFinite),
              target.x >= 0, target.y >= 0, target.width > 0, target.height > 0,
              target.x + target.width <= 1, target.y + target.height <= 1,
              !signature.strokes.isEmpty,
              signature.strokes.allSatisfy({ stroke in
                  stroke.width.isFinite && stroke.width > 0 && stroke.color.isVisibleInkColor &&
                  !stroke.points.isEmpty && stroke.points.allSatisfy {
                      $0.x.isFinite && $0.y.isFinite && $0.widthScale.isFinite && $0.widthScale > 0
                  }
              }) else { throw StoreError.invalidPlacement }
        return try db.transaction {
            guard let page = try page(expected.id), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            guard page == expected else { throw StoreError.pageObjectsChanged }
            var key = try objects(on: page.id).last?.zKey
            let timestamp = Date()
            let objects = try signature.placed(in: target, on: page.geometry.pageSize).map { stroke in
                var sourceStroke = stroke
                sourceStroke.points = stroke.points.map { point in
                    let source = CGPoint(x: point.x, y: point.y).applying(page.geometry.pageToSource)
                    var converted = point
                    converted.x = source.x
                    converted.y = source.y
                    return converted
                }
                let nextKey = try SortKey.between(key, nil)
                key = nextKey
                return PageObject(pageID: page.id, zKey: nextKey, payload: .ink(sourceStroke), modifiedAt: timestamp)
            }
            return (try applyObjectChanges(on: page.id, saving: objects, deleting: []), objects)
        }
    }
}

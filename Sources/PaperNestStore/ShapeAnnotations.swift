import CoreGraphics
import Foundation
import PaperNestCore

extension LibraryStore {
    public func addShape(to expected: Page, kind: ShapeAnnotation, start: CGPoint, end: CGPoint,
                         color: RGBAColor, width: Double) throws -> (page: Page, objects: [PageObject]) {
        try db.transaction {
            guard let page = try page(expected.id), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            guard page == expected else { throw StoreError.pageObjectsChanged }
            let stroke = try kind.stroke(from: start, to: end, geometry: page.geometry, color: color, width: width)
            let key = try SortKey.between(try objects(on: page.id).last?.zKey, nil)
            let object = PageObject(pageID: page.id, zKey: key, payload: .ink(stroke), modifiedAt: Date())
            return (try applyObjectChanges(on: page.id, saving: [object], deleting: []), [object])
        }
    }
}

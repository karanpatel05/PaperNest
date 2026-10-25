import Foundation
import PaperNestCore

extension LibraryStore {
    /// The exact OCR snapshot is the selection's identity. Comparing inside
    /// the transaction rejects rescan/re-recognition races before any mark is
    /// saved. The new strokes are one durable edit and one undo step.
    public func addTextMarkup(_ snapshot: PageRecognition, lineIndices: Set<Int>, style: TextMarkupStyle, color: RGBAColor? = nil)
        throws -> (page: Page, objects: [PageObject]) {
        try db.transaction {
            guard let page = try page(snapshot.pageID),
                  let item = try item(page.itemID), item.deletedAt == nil else { throw StoreError.pageNotFound }
            guard snapshot.status == .completed, snapshot.sourceRevision == page.revision,
                  try recognition(for: page.id) == snapshot else { throw StoreError.recognitionChanged }
            guard !lineIndices.isEmpty, lineIndices.allSatisfy(snapshot.lines.indices.contains) else { throw StoreError.invalidOrder }
            var lastKey = try objects(on: page.id).last?.zKey
            let date = Date()
            let additions = try lineIndices.sorted().map { index in
                let stroke = try style.stroke(for: snapshot.lines[index], in: page.sourceSize, color: color)
                let key = try SortKey.between(lastKey, nil)
                lastKey = key
                return PageObject(pageID: page.id, zKey: key, payload: .ink(stroke), modifiedAt: date)
            }
            return (try applyObjectChanges(on: page.id, saving: additions, deleting: []), additions)
        }
    }
}

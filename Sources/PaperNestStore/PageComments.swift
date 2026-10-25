import Foundation
import PaperNestCore

extension LibraryStore {
    /// In-session compare-and-swap token. Only this store can create one.
    public struct PageCommentChange: Sendable {
        public let pageID: PageID
        public let before: PageObject?
        public let after: PageObject?
        public var inverse: Self { .init(pageID: pageID, before: after, after: before) }
        fileprivate init(pageID: PageID, before: PageObject?, after: PageObject?) {
            self.pageID = pageID
            self.before = before
            self.after = after
        }
    }

    /// Nil text deletes an existing comment. Nil expected creates a new one.
    public func setPageComment(on pageID: PageID, replacing expected: PageObject?, text: String?) throws -> PageCommentChange {
        try db.transaction {
            let saved: PageObject?
            if let text {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, clean.count <= 10_000 else { throw StoreError.invalidComment }
                if var object = expected {
                    object.payload = .comment(clean)
                    object.modifiedAt = Date()
                    saved = object
                } else {
                    let key = try SortKey.between(try objects(on: pageID).last?.zKey, nil)
                    saved = PageObject(pageID: pageID, zKey: key, payload: .comment(clean), modifiedAt: Date())
                }
            } else {
                guard expected != nil else { throw StoreError.invalidComment }
                saved = nil
            }
            let change = PageCommentChange(pageID: pageID, before: expected, after: saved)
            _ = try applyPageCommentChange(change)
            return change
        }
    }

    @discardableResult
    public func applyPageCommentChange(_ change: PageCommentChange) throws -> Page {
        try db.transaction {
            guard let page = try page(change.pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            let all = [change.before, change.after].compactMap { $0 }
            guard !all.isEmpty, all.allSatisfy({ $0.pageID == change.pageID && $0.commentText != nil }),
                  Set(all.map(\.id)).count == 1 else { throw StoreError.pageObjectsChanged }
            let id = all[0].id
            let existing = try objects(on: change.pageID).first { $0.id == id }
            guard existing == change.before else { throw StoreError.pageObjectsChanged }
            if change.before == nil {
                guard try db.query("SELECT id FROM page_objects WHERE id = ?", [.text(id.rawValue)], map: { $0.text(0) }).isEmpty else {
                    throw StoreError.pageObjectsChanged
                }
            }
            try persistCommentChange(on: page, saving: change.after, deleting: id)
            return page
        }
    }
}

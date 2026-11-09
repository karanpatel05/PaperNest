import Foundation
import PaperNestCore

extension LibraryStore {
    /// Applies a markup gesture or its inverse only while every affected
    /// object still matches.
    ///
    /// Named for ink because that is what it carried first; it takes any mark
    /// a page shows — ink, a text box, a placed image — because the editor's
    /// undo history goes through it for all of them. A page comment does not:
    /// it is private and has its own path. Unrelated edits may coexist; a restored ID must be absent
    /// throughout the library so INSERT OR REPLACE cannot move another object.
    /// A gesture may additionally require its displayed page snapshot, so a
    /// concurrent crop or rotation cannot change the meaning of its delta.
    public func applyInkChanges(on pageID: PageID, saving: [PageObject], replacing: [PageObject],
                                deleting: [PageObject], expectedPage: Page? = nil) throws -> Page {
        try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), parent.deletedAt == nil else {
                throw StoreError.pageNotFound
            }
            if let expectedPage, page != expectedPage { throw StoreError.pageObjectsChanged }
            let savedIDs = Set(saving.map(\.id)), replacedIDs = Set(replacing.map(\.id))
            let expected = replacing + deleting
            guard savedIDs.count == saving.count, Set(expected.map(\.id)).count == expected.count,
                  replacedIDs.isSubset(of: savedIDs), savedIDs.isDisjoint(with: deleting.map(\.id)) else {
                throw StoreError.invalidOrder
            }
            // Marks a page carries, not ink alone. The editor's undo history
            // runs everything through here, so a kind missing from this list
            // gets an Undo button that lights up and then only shows an error
            // — which is what a text box did until this was widened.
            //
            // A page comment is deliberately **not** one: it is private, it has
            // its own guarded path that leaves the page revision alone, and it
            // must not travel through the markup history.
            guard (saving + expected).allSatisfy({ object in
                guard object.pageID == pageID else { return false }
                switch object.payload {
                case .ink, .text, .image: return true
                case .comment: return false
                }
            }) else { throw StoreError.pageObjectsChanged }
            let current = Dictionary(uniqueKeysWithValues: try objects(on: pageID).map { ($0.id, $0) })
            guard expected.allSatisfy({ current[$0.id] == $0 }) else { throw StoreError.pageObjectsChanged }
            for id in savedIDs.subtracting(replacedIDs) {
                guard try db.query("SELECT id FROM page_objects WHERE id = ?", [.text(id.rawValue)], map: { $0.text(0) }).isEmpty else {
                    throw StoreError.pageObjectsChanged
                }
            }
            return try applyObjectChanges(on: pageID, saving: saving, deleting: deleting.map(\.id))
        }
    }

    /// Checks the displayed page and exact selected objects before any write,
    /// so a stale manager cannot silently replace or erase another edit.
    public func editInk(on pageID: PageID, expectedRevision: Int, objects expected: [PageObject], edit: InkEdit)
        throws -> (page: Page, previous: [PageObject], saved: [PageObject]) {
        try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), parent.deletedAt == nil else {
                throw StoreError.pageNotFound
            }
            guard !expected.isEmpty, Set(expected.map(\.id)).count == expected.count else { throw StoreError.invalidOrder }
            guard page.revision == expectedRevision else { throw StoreError.pageObjectsChanged }
            let current = Dictionary(uniqueKeysWithValues: try objects(on: pageID).map { ($0.id, $0) })
            for object in expected {
                guard object.pageID == pageID, current[object.id] == object else {
                    throw StoreError.pageObjectsChanged
                }
                switch (edit, object.payload) {
                // Removing is for anything painted on the page. The markup
                // manager is the only place a mark can be taken off once undo
                // has moved on, and while this accepted ink alone **a text
                // box or a placed image could never be removed at all**.
                case (.remove, .ink), (.remove, .text), (.remove, .image): break
                // A comment is not painted on the page and has its own place
                // to live; sweeping one away from here would delete something
                // the user cannot see from there.
                case (.remove, .comment): throw StoreError.pageObjectsChanged
                case (.recolor, .ink): break
                // An image has no colour, and a text box's colour is not what
                // that picker means. Refused, not skipped.
                case (.recolor, _): throw StoreError.cannotRecolor
                }
            }
            let saved: [PageObject]
            let deleted: [PageObjectID]
            switch edit {
            case .recolor(let color):
                guard color.isVisibleInkColor else { throw TextMarkupError.invalidColor }
                let timestamp = Date()
                saved = expected.map { object in
                    var updated = object
                    if case .ink(var stroke) = object.payload {
                        stroke.color = color
                        updated.payload = .ink(stroke)
                    }
                    updated.modifiedAt = timestamp
                    return updated
                }
                deleted = []
            case .remove:
                saved = []
                deleted = expected.map(\.id)
            }
            return (try applyObjectChanges(on: pageID, saving: saved, deleting: deleted), expected, saved)
        }
    }
}

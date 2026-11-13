import Foundation

/// A place a reader marked to come back to: one page of one document.
///
/// A bookmark belongs to the **page**, not to a page number. Move the page
/// and the bookmark goes with it; delete the page and the bookmark goes too.
/// A page has at most one.
///
/// It is the reader's own note about where they were, like a ribbon in a
/// book. It is not part of the document: it is not drawn on the page, not
/// exported, not printed, and marking a page does not count as editing it.
public struct Bookmark: Hashable, Codable, Sendable, Identifiable {
    public var id: BookmarkID
    /// The document the page is in now. Read from the page, never stored.
    public var itemID: ItemID
    public var pageID: PageID
    /// What the reader called it. Empty until they name it; an unnamed
    /// bookmark is shown by its page's number, which is worked out when it is
    /// shown so it is never out of date.
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: BookmarkID = .make(), itemID: ItemID, pageID: PageID, name: String = "",
                createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.itemID = itemID
        self.pageID = pageID
        self.name = Self.cleanName(name)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public static let maximumNameLength = 120

    /// A name as it is kept: one line, no space at either end, no longer
    /// than a list row can sensibly show.
    public static func cleanName(_ name: String) -> String {
        let oneLine = name.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(oneLine.prefix(maximumNameLength)).trimmingCharacters(in: .whitespaces)
    }
}

public typealias BookmarkID = Identifier<Bookmark>

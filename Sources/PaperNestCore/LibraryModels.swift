import Foundation

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// A file kept as it was given to us, with no pages of its own.
    case file
    /// Scanned or imported pages.
    case document
    /// Pages created for writing; may also hold scans and PDF pages.
    case notebook
}

/// Stable library labels; their display names and colors belong to the UI.
public enum ItemColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray
}

/// A document or notebook in the library. Pages are stored separately so a
/// large notebook never has to be loaded whole.
public struct LibraryItem: Identifiable, Hashable, Codable, Sendable {
    /// Version of the item-level data layout, bumped with schema migrations
    /// that change how an item's content is interpreted.
    public static let currentSchemaVersion = 1

    public var id: ItemID
    public var kind: ItemKind
    public var name: String
    public var folderID: FolderID?
    public var isFavorite: Bool
    public var colorLabel: ItemColor?
    public var createdAt: Date
    public var modifiedAt: Date
    /// Set when the item is moved to Recently Deleted. The item is kept,
    /// restorable, until purged after `RetentionPolicy.recentlyDeletedDays`.
    public var deletedAt: Date?
    public var schemaVersion: Int

    public init(
        id: ItemID = .make(),
        kind: ItemKind,
        name: String,
        folderID: FolderID? = nil,
        isFavorite: Bool = false,
        colorLabel: ItemColor? = nil,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil,
        schemaVersion: Int = LibraryItem.currentSchemaVersion
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.folderID = folderID
        self.isFavorite = isFavorite
        self.colorLabel = colorLabel
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.schemaVersion = schemaVersion
    }

    public var isDeleted: Bool { deletedAt != nil }
}

public struct Folder: Identifiable, Hashable, Codable, Sendable {
    public var id: FolderID
    public var name: String
    public var parentID: FolderID?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: FolderID = .make(),
        name: String,
        parentID: FolderID? = nil,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

public enum RetentionPolicy {
    /// Items in Recently Deleted are purged after this many days. This matches
    /// the convention users know from Photos and Files; it is a product
    /// decision recorded in docs/PRODUCT_SPEC.md.
    public static let recentlyDeletedDays = 30

    public static func purgeCutoff(now: Date) -> Date {
        now.addingTimeInterval(-Double(recentlyDeletedDays) * 24 * 60 * 60)
    }
}

/// Library-level names never collide inside one folder: a second "Receipt"
/// becomes "Receipt 2". Comparison ignores case and diacritics so "Resume"
/// and "Résumé" are treated as the same visible name.
public enum NameDeduplicator {
    public static func uniqueName(_ proposed: String, existing: some Sequence<String>) -> String {
        let base = normalizedDisplayName(proposed)
        let taken = Set(existing.map(foldKey))
        guard taken.contains(foldKey(base)) else { return base }
        var n = 2
        while taken.contains(foldKey("\(base) \(n)")) {
            n += 1
        }
        return "\(base) \(n)"
    }

    /// Trims whitespace and control characters; empty names are not allowed.
    public static func normalizedDisplayName(_ name: String, fallback: String = "Untitled") -> String {
        let cleaned = name.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(200))
    }

    private static func foldKey(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

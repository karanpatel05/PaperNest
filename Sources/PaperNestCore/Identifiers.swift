import Foundation

/// A stable, typed identifier. The phantom `Entity` parameter keeps page,
/// item and folder IDs from being mixed up. IDs are UUID strings so they stay
/// stable across devices and can double as CloudKit record names.
public struct Identifier<Entity>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> Identifier {
        Identifier(rawValue: UUID().uuidString)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public typealias ItemID = Identifier<LibraryItem>
public typealias FolderID = Identifier<Folder>
public typealias PageID = Identifier<Page>
public typealias PageObjectID = Identifier<PageObject>

/// Content address of an immutable original: the lowercase hex SHA-256 of
/// its bytes. Identical imports share one stored file.
public struct AssetID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let sha256: String

    public init(sha256: String) {
        self.sha256 = sha256.lowercased()
    }

    public init(from decoder: Decoder) throws {
        self.init(sha256: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    public var description: String { sha256 }
}

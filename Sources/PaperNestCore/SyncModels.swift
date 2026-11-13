import Foundation

/// The kinds of library row that travel between devices as one record each.
///
/// Original files (the bytes behind a page, a file item or a placed image)
/// are not in this list on purpose: they are immutable, named by their
/// SHA-256, and move on their own track so a device can know a document
/// exists long before it has downloaded what the document shows.
public enum SyncRecordType: String, Codable, Sendable, CaseIterable {
    case folder, item, page, object, signature

    /// Parents before children, so a batch applied in this order defers as
    /// little as possible.
    public var applyOrder: Int {
        switch self {
        case .folder: 0
        case .item: 1
        case .page: 2
        case .object: 3
        case .signature: 4
        }
    }
}

public struct SyncRecordKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public var type: SyncRecordType
    public var id: String

    public init(_ type: SyncRecordType, _ id: String) {
        self.type = type
        self.id = id
    }

    public var description: String { "\(type.rawValue):\(id)" }
}

/// One field of a synced record. Dates travel as `double` — Date's own
/// `timeIntervalSinceReferenceDate` — so they compare bit for bit after a
/// round trip, which the three-way merge depends on.
public enum SyncValue: Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
}

extension SyncValue: Codable {
    private enum CodingKeys: String, CodingKey { case s, i, d }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try c.decodeIfPresent(String.self, forKey: .s) {
            self = .string(s)
        } else if let i = try c.decodeIfPresent(Int64.self, forKey: .i) {
            self = .int(i)
        } else {
            // Stored as its bit pattern: JSON numbers do not promise to carry
            // every Double exactly, and "equal to the last synced value" has
            // to mean equal.
            self = .double(Double(bitPattern: try c.decode(UInt64.self, forKey: .d)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s): try c.encode(s, forKey: .s)
        case .int(let i): try c.encode(i, forKey: .i)
        case .double(let d): try c.encode(d.bitPattern, forKey: .d)
        }
    }
}

public typealias SyncFields = [String: SyncValue]

/// A library row as it is sent and received. A field that is absent is null.
public struct SyncRecord: Hashable, Codable, Sendable {
    /// The record layout this build writes and understands. A record carrying
    /// a higher number came from a newer app; it is set aside untouched
    /// rather than applied half-understood.
    public static let layoutVersion: Int64 = 1
    public static let layoutVersionField = "v"

    public var key: SyncRecordKey
    public var fields: SyncFields

    public init(key: SyncRecordKey, fields: SyncFields) {
        self.key = key
        self.fields = fields
    }

    public var layoutVersion: Int64 {
        if case .int(let v)? = fields[Self.layoutVersionField] { return v }
        return 1
    }

    public func string(_ name: String) -> String? {
        if case .string(let s)? = fields[name] { return s }
        return nil
    }

    public func int(_ name: String) -> Int64? {
        if case .int(let i)? = fields[name] { return i }
        return nil
    }

    public func double(_ name: String) -> Double? {
        if case .double(let d)? = fields[name] { return d }
        return nil
    }
}

/// A record as the server holds it, with the opaque token the server needs
/// back before it will accept a change to it.
public struct SyncIncoming: Hashable, Sendable {
    public var record: SyncRecord
    public var systemFields: Data?

    public init(record: SyncRecord, systemFields: Data?) {
        self.record = record
        self.systemFields = systemFields
    }
}

public enum SyncOutgoing: Hashable, Sendable {
    case save(SyncRecord, systemFields: Data?)
    case delete(SyncRecordKey)

    public var key: SyncRecordKey {
        switch self {
        case .save(let record, _): record.key
        case .delete(let key): key
        }
    }
}

/// Two devices changed the same thing in ways that cannot both be the one
/// answer. Both versions are kept; this is the note that says where.
public struct SyncConflict: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// A page's paper or its crop/rotation/filter changed on both sides.
        /// The other device's version stayed in place; this device's became
        /// a page of its own right after it.
        case pageVersion
        /// One mark (a stroke, a text box, a picture, a comment) changed on
        /// both sides. Both are on the page now.
        case objectVersion
    }

    public var id: String
    public var kind: Kind
    public var itemID: ItemID?
    public var itemName: String?
    public var pageID: PageID?
    /// The page or object that holds this device's version.
    public var copyID: String
    public var createdAt: Date

    public init(id: String, kind: Kind, itemID: ItemID?, itemName: String?, pageID: PageID?,
                copyID: String, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.itemName = itemName
        self.pageID = pageID
        self.copyID = copyID
        self.createdAt = createdAt
    }
}

/// What applying a batch from the server did, for whoever has to react.
public struct SyncApplyReport: Sendable, Equatable {
    /// Rows written or removed. Zero means nothing on screen can have moved.
    public var changed = 0
    /// Records set aside because something they need has not arrived yet, or
    /// because a newer app wrote them.
    public var deferred = 0
    public var newConflicts = 0
    /// This device cancelled a deletion because the other side had edited the
    /// thing, and no longer holds its contents: everything must be fetched
    /// again from the start.
    public var needsFullRefetch = false
    public var affectedItems: Set<ItemID> = []

    public init() {}
}

/// What the person is told. One of these at a time, chosen by
/// `SyncStatus.resolve`.
public enum SyncStatus: String, Hashable, Sendable, CaseIterable {
    case savedLocally
    case waiting
    case syncing
    case upToDate
    case offline
    case cloudUnavailable
    case conflict
    case needsAttention
}

/// Everything the status is worked out from. Kept as plain data so the rule
/// can be tested without a network, an account or a screen.
public struct SyncSnapshot: Hashable, Sendable {
    public var isEnabled = false
    public var accountAvailable = true
    public var isOnline = true
    public var isTransferring = false
    public var pendingChanges = 0
    public var pendingUploads = 0
    public var unresolvedConflicts = 0
    public var hasError = false
    /// A fetch has finished since sync last started and the server reported
    /// nothing further waiting.
    public var remoteChangesProcessed = false

    public init() {}
}

extension SyncStatus {
    /// "Up to date" is the only claim here that can be false in a way that
    /// costs someone their work, so it is the last thing reached: every local
    /// change acknowledged, every upload done, and what the server had to say
    /// taken in.
    public static func resolve(_ s: SyncSnapshot) -> SyncStatus {
        guard s.isEnabled else { return .savedLocally }
        guard s.accountAvailable else { return .cloudUnavailable }
        guard s.isOnline else { return .offline }
        if s.isTransferring { return .syncing }
        if s.hasError { return .needsAttention }
        if s.unresolvedConflicts > 0 { return .conflict }
        if s.pendingChanges > 0 || s.pendingUploads > 0 || !s.remoteChangesProcessed { return .waiting }
        return .upToDate
    }
}

extension RetentionPolicy {
    /// With sync on, a deleted page is kept this long before it is removed
    /// for good, and an original nothing uses any more stays in iCloud this
    /// long. A device that was offline while something was deleted has that
    /// window to come back and say "I was still using that".
    public static let syncTombstoneDays = 30

    public static func syncTombstoneCutoff(now: Date) -> Date {
        now.addingTimeInterval(-Double(syncTombstoneDays) * 24 * 60 * 60)
    }
}

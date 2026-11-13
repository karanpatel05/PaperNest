import CloudKit
import Foundation
import PaperNestCore

/// Names in the iCloud container. These are a contract with every copy of
/// the app already installed: once the schema is deployed to production,
/// none of them can be renamed.
public enum CloudSchema {
    /// Records: folders, documents, pages, marks, signatures. Kept in step
    /// by `CKSyncEngine`.
    public static let libraryZone = CKRecordZone.ID(zoneName: "PaperNestLibrary", ownerName: CKCurrentUserDefaultName)
    /// Original files, one record each holding a `CKAsset`. Deliberately a
    /// separate zone that the sync engine never fetches, so learning that a
    /// document exists does not mean downloading every scan inside it.
    public static let originalsZone = CKRecordZone.ID(zoneName: "PaperNestOriginals", ownerName: CKCurrentUserDefaultName)

    public static let originalType = "Original"
    public static let originalFileField = "file"
    public static let originalBytesField = "bytes"

    public static func recordType(_ type: SyncRecordType) -> String {
        switch type {
        case .folder: "Folder"
        case .item: "Item"
        case .page: "Page"
        case .object: "PageObject"
        case .signature: "Signature"
        }
    }

    static func syncType(_ recordType: String) -> SyncRecordType? {
        SyncRecordType.allCases.first { CloudSchema.recordType($0) == recordType }
    }

    /// Every field each record type can carry. A field absent from a record
    /// being sent is written as nil, which is how "moved out of its folder"
    /// reaches the server.
    static func fields(_ type: SyncRecordType) -> [String] {
        let own: [String] = switch type {
        case .folder: ["name", "parentID", "createdAt", "modifiedAt", "deletedAt"]
        case .item: ["kind", "name", "folderID", "isFavorite", "createdAt", "modifiedAt", "deletedAt", "schemaVersion",
                     "colorLabel", "fileAssetID", "fileUTI", "fileName", "fileBytes", "assetKind"]
        case .page: ["itemID", "sortKey", "width", "height", "contentKind", "assetID", "pdfIndex", "template", "transform",
                     "createdAt", "deletedAt", "assetKind", "assetBytes", "assetName"]
        case .object: ["pageID", "zKey", "kind", "payload", "modifiedAt", "assetID", "assetKind", "assetBytes", "assetName"]
        case .signature: ["name", "strokes", "createdAt"]
        }
        return own + [SyncRecord.layoutVersionField]
    }

    static let doubleFields: Set<String> = ["createdAt", "modifiedAt", "deletedAt", "width", "height"]

    /// What a person wrote or named. Stored through `encryptedValues`, so
    /// CloudKit encrypts it on the device before it leaves. (Original files
    /// are `CKAsset`s, which CloudKit always encrypts.) Identifiers, order
    /// keys and timestamps stay readable to the server; it needs none of the
    /// content to do its job.
    static let encryptedFields: Set<String> = ["name", "payload", "strokes", "fileName", "assetName"]

    /// Text that can outgrow a record's size limit — a long stroke, a pasted
    /// page of typing. Past this size it travels as a file on the record.
    static let spillingFields: Set<String> = ["payload", "strokes"]
    static let spillThreshold = 200_000
    static func spillField(_ name: String) -> String { name + "File" }

    public static func recordID(_ key: SyncRecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(key.type.rawValue).\(key.id)", zoneID: libraryZone)
    }

    public static func key(_ recordID: CKRecord.ID) -> SyncRecordKey? {
        guard recordID.zoneID == libraryZone else { return nil }
        let parts = recordID.recordName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let type = SyncRecordType(rawValue: String(parts[0])) else { return nil }
        return SyncRecordKey(type, String(parts[1]))
    }

    public static func originalID(_ sha256: String) -> CKRecord.ID {
        CKRecord.ID(recordName: sha256, zoneID: originalsZone)
    }
}

enum CloudRecordMapper {
    /// The part of a `CKRecord` the server needs back to accept a change:
    /// its identity and change tag, without any of its fields.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func bareRecord(from systemFields: Data?) -> CKRecord? {
        guard let systemFields, let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// Builds the record to send. `temporaryDirectory` receives the files
    /// for any text too large to send inline; the caller removes it once the
    /// send has finished.
    static func cloudRecord(for record: SyncRecord, systemFields: Data?, temporaryDirectory: URL) throws -> CKRecord {
        let id = CloudSchema.recordID(record.key)
        var ck = bareRecord(from: systemFields)
        if ck?.recordID != id || ck?.recordType != CloudSchema.recordType(record.key.type) { ck = nil }
        let out = ck ?? CKRecord(recordType: CloudSchema.recordType(record.key.type), recordID: id)

        for name in CloudSchema.fields(record.key.type) {
            let value = record.fields[name]
            if CloudSchema.spillingFields.contains(name) {
                let spill = CloudSchema.spillField(name)
                if case .string(let text)? = value, text.utf8.count > CloudSchema.spillThreshold {
                    let fileURL = temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try Data(text.utf8).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    out[spill] = CKAsset(fileURL: fileURL)
                    out.encryptedValues[name] = nil as String?
                    continue
                }
                out[spill] = nil
            }
            if CloudSchema.encryptedFields.contains(name) {
                switch value {
                case .string(let s)?: out.encryptedValues[name] = s
                case .int(let i)?: out.encryptedValues[name] = i
                case .double(let d)?: out.encryptedValues[name] = d
                case nil: out.encryptedValues[name] = nil as String?
                }
            } else {
                switch value {
                case .string(let s)?: out[name] = s
                case .int(let i)?: out[name] = i
                case .double(let d)?: out[name] = d
                case nil: out[name] = nil
                }
            }
        }
        return out
    }

    /// Reads a record from the server. Nil for anything that is not one of
    /// ours, which is skipped rather than guessed at.
    static func incoming(from ck: CKRecord) -> SyncIncoming? {
        guard let key = CloudSchema.key(ck.recordID), CloudSchema.syncType(ck.recordType) == key.type else { return nil }
        var fields: SyncFields = [:]
        // Every key the record has, not just the ones this build writes: a
        // layout version from a newer app must be seen to be refused.
        let names = Set(CloudSchema.fields(key.type))
        for name in names {
            let raw: (any CKRecordValueProtocol)?
            if CloudSchema.spillingFields.contains(name), let asset = ck[CloudSchema.spillField(name)] as? CKAsset,
               let fileURL = asset.fileURL, let data = try? Data(contentsOf: fileURL) {
                fields[name] = .string(String(decoding: data, as: UTF8.self))
                continue
            }
            if CloudSchema.encryptedFields.contains(name) {
                raw = ck.encryptedValues[name]
            } else {
                raw = ck[name] as? any CKRecordValueProtocol
            }
            switch raw {
            case let s as String: fields[name] = .string(s)
            case let n as NSNumber:
                // Typed by the field, not by how the number happens to come
                // back: a page 612 points wide must still be a double.
                fields[name] = CloudSchema.doubleFields.contains(name) ? .double(n.doubleValue) : .int(n.int64Value)
            default: break
            }
        }
        return SyncIncoming(record: SyncRecord(key: key, fields: fields), systemFields: systemFields(of: ck))
    }
}

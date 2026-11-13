import CloudKit
import Foundation

/// Original files in the private database, one `Original` record per
/// SHA-256 with the bytes as a `CKAsset`. CloudKit streams the asset from and
/// to disk, so a large scan is never held in memory here.
struct CloudKitBlobTransport: BlobTransport {
    let database: CKDatabase

    private static func translate(_ error: any Error) -> BlobTransportError {
        guard let ck = error as? CKError else { return .other("error") }
        switch ck.code {
        case .quotaExceeded: return .quotaExceeded
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled:
            return .unavailable
        default: return .other("cloudkit-\(ck.code.rawValue)")
        }
    }

    private static func isMissing(_ error: any Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        return ck.code == .unknownItem || ck.code == .zoneNotFound || ck.code == .userDeletedZone
    }

    func exists(_ sha256: String) async throws -> Bool {
        let id = CloudSchema.originalID(sha256)
        do {
            // No keys asked for: this must not pull the file down.
            let results = try await database.records(for: [id], desiredKeys: [])
            switch results[id] {
            case .success: return true
            case .failure(let error): if Self.isMissing(error) { return false } else { throw Self.translate(error) }
            case nil: return false
            }
        } catch let error as BlobTransportError {
            throw error
        } catch {
            if Self.isMissing(error) { return false }
            throw Self.translate(error)
        }
    }

    func upload(_ sha256: String, from fileURL: URL, byteCount: Int64) async throws {
        do {
            try await save(sha256, from: fileURL, byteCount: byteCount)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            do {
                _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudSchema.originalsZone)], deleting: [])
                try await save(sha256, from: fileURL, byteCount: byteCount)
            } catch {
                throw Self.translate(error)
            }
        } catch {
            throw Self.translate(error)
        }
    }

    private func save(_ sha256: String, from fileURL: URL, byteCount: Int64) async throws {
        let id = CloudSchema.originalID(sha256)
        let record = CKRecord(recordType: CloudSchema.originalType, recordID: id)
        record[CloudSchema.originalFileField] = CKAsset(fileURL: fileURL)
        record[CloudSchema.originalBytesField] = byteCount
        // The name is the content's hash, so whatever is already under it is
        // these same bytes; overwriting is harmless and saves a round trip.
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
        if case .failure(let error)? = saved[id] { throw error }
    }

    func download(_ sha256: String) async throws -> URL? {
        let id = CloudSchema.originalID(sha256)
        do {
            let results = try await database.records(for: [id])
            switch results[id] {
            case .success(let record):
                guard let asset = record[CloudSchema.originalFileField] as? CKAsset, let cached = asset.fileURL else { return nil }
                // CloudKit's cached file can be cleared at any time; take a
                // copy that is ours until the library has taken it in.
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("papernest-original-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: cached, to: copy)
                return copy
            case .failure(let error):
                if Self.isMissing(error) { return nil }
                throw Self.translate(error)
            case nil:
                return nil
            }
        } catch let error as BlobTransportError {
            throw error
        } catch let error as CKError {
            if Self.isMissing(error) { return nil }
            throw Self.translate(error)
        } catch {
            throw BlobTransportError.other("storage")
        }
    }

    func delete(_ sha256: String) async throws {
        let id = CloudSchema.originalID(sha256)
        do {
            let (_, deleted) = try await database.modifyRecords(saving: [], deleting: [id], atomically: false)
            if case .failure(let error)? = deleted[id], !Self.isMissing(error) { throw Self.translate(error) }
        } catch let error as BlobTransportError {
            throw error
        } catch {
            if Self.isMissing(error) { return }
            throw Self.translate(error)
        }
    }
}

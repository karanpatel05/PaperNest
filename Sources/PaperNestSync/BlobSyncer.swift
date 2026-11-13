import Foundation
import PaperNestCore
import PaperNestStore

/// Works through the originals that need to move: up to iCloud, down from
/// it, and — after the tombstone period — out of it.
///
/// One file at a time, straight from and to disk; nothing here holds a
/// document in memory. Every step is recorded in the library before the next
/// begins, so being killed mid-transfer costs that one transfer.
public actor BlobSyncer {
    public struct Pass: Sendable, Equatable {
        public var completed = 0
        public var failed = 0
        /// The pass was cut short by something that will not fix itself in
        /// the next second (no network, full iCloud).
        public var stopped: BlobTransportError?

        public init() {}
    }

    private let store: LibraryStore
    private let transport: any BlobTransport
    private var isUploading = false

    public init(store: LibraryStore, transport: any BlobTransport) {
        self.store = store
        self.transport = transport
    }

    /// Uploads every original iCloud does not have yet. Records that point
    /// at them are held back until this confirms each one.
    public func uploadPending(progress: (@Sendable (Pass) async -> Void)? = nil) async -> Pass {
        var pass = Pass()
        guard !isUploading else { return pass }
        isUploading = true
        defer { isUploading = false }
        var attempted = Set<AssetID>()
        while pass.stopped == nil, !Task.isCancelled {
            guard let uploads = try? await store.syncAssetsPendingUpload(limit: 4) else { break }
            let fresh = uploads.filter { !attempted.contains($0.record.id) }
            guard !fresh.isEmpty else { break }
            for upload in fresh {
                attempted.insert(upload.record.id)
                let id = upload.record.id
                do {
                    if try await transport.exists(id.sha256) {
                        // Another device uploaded the same bytes, or an
                        // earlier attempt finished without our hearing so.
                    } else if let fileURL = upload.fileURL {
                        try await transport.upload(id.sha256, from: fileURL, byteCount: upload.record.byteCount)
                    } else {
                        try? await store.syncAssetFailed(id, message: "missing")
                        pass.failed += 1
                        continue
                    }
                    try await store.syncAssetDidUpload(id)
                    pass.completed += 1
                    await progress?(pass)
                } catch let error as BlobTransportError {
                    try? await store.syncAssetFailed(id, message: Self.describe(error))
                    pass.failed += 1
                    // A problem with this one file; the next may be fine.
                    if case .other = error { continue }
                    pass.stopped = error
                    break
                } catch {
                    try? await store.syncAssetFailed(id, message: "error")
                    pass.failed += 1
                }
            }
        }
        return pass
    }

    /// Downloads what is only in iCloud — everything, or one document's
    /// originals. Each file is checked against its SHA-256 as it is taken in;
    /// one that does not match is refused and stays marked as not here.
    public func downloadMissing(for item: ItemID? = nil, limit: Int = 500,
                                progress: (@Sendable (Pass) async -> Void)? = nil) async -> Pass {
        var pass = Pass()
        guard let wanted = try? await store.syncAssetsNeedingDownload(for: item, limit: limit) else { return pass }
        for record in wanted {
            if Task.isCancelled { break }
            do {
                guard let fileURL = try await transport.download(record.id.sha256) else {
                    try? await store.syncAssetFailed(record.id, message: "notInCloud")
                    pass.failed += 1
                    continue
                }
                defer { try? FileManager.default.removeItem(at: fileURL) }
                try await store.syncInstallDownloadedAsset(record.id, from: fileURL)
                pass.completed += 1
                await progress?(pass)
            } catch let error as BlobTransportError {
                try? await store.syncAssetFailed(record.id, message: Self.describe(error))
                pass.failed += 1
                if case .other = error { continue }
                pass.stopped = error
                break
            } catch StoreError.assetChecksumMismatch {
                try? await store.syncAssetFailed(record.id, message: "corrupt")
                pass.failed += 1
            } catch {
                // Out of space is the likely one; trying the next file would
                // only fail the same way.
                try? await store.syncAssetFailed(record.id, message: "storage")
                pass.failed += 1
                pass.stopped = .other("storage")
                break
            }
        }
        return pass
    }

    /// Removes from iCloud the originals nothing has used for the whole
    /// tombstone period.
    public func deleteExpired() async {
        guard let due = try? await store.syncAssetsDueForRemoteDelete() else { return }
        for id in due {
            guard (try? await transport.delete(id.sha256)) != nil else { return }
            try? await store.syncAssetDidRemoteDelete(id)
        }
    }

    /// Frees this device's copy of one document's originals. Each is
    /// confirmed to be in iCloud *now*, not merely remembered as uploaded,
    /// before its local file goes. Returns how many were freed.
    public func removeDownloads(of item: ItemID) async -> Int {
        guard let candidates = try? await store.syncEvictableAssets(of: item) else { return 0 }
        var freed = 0
        for record in candidates {
            guard (try? await transport.exists(record.id.sha256)) == true else { continue }
            if (try? await store.syncEvictLocalCopy(record.id)) != nil { freed += 1 }
        }
        return freed
    }

    private static func describe(_ error: BlobTransportError) -> String {
        switch error {
        case .quotaExceeded: "quota"
        case .unavailable: "unavailable"
        case .other(let detail): detail
        }
    }
}

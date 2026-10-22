import CryptoKit
import Foundation
import PaperNestCore

/// Content-addressed storage for immutable originals.
///
/// Write protocol: bytes go to a staging file, are fsynced, then renamed to
/// `Assets/<2 hex>/<sha256>.<ext>` and the directory is fsynced. Only after
/// that may a database row reference the asset. A crash in between leaves at
/// most an unreferenced file, which `LibraryStore.sweepOrphanAssets` removes;
/// it never leaves a row pointing at a missing or partial file.
public struct AssetFileStore: Sendable {
    public let rootURL: URL
    var stagingURL: URL { rootURL.appendingPathComponent(".staging", isDirectory: true) }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    }

    public static func assetID(for data: Data) -> AssetID {
        let digest = SHA256.hash(data: data)
        return AssetID(sha256: digest.map { String(format: "%02x", $0) }.joined())
    }

    public func url(for id: AssetID, kind: AssetKind) -> URL {
        rootURL
            .appendingPathComponent(String(id.sha256.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(id.sha256).\(kind.fileExtension)")
    }

    /// A durably written asset that a database row may now reference.
    public struct StagedAsset: Sendable, Hashable {
        public let id: AssetID
        public let kind: AssetKind
        public let byteCount: Int64
        public let originalFilename: String?
    }

    /// Writes `data` durably. Identical bytes already present are reused.
    public func store(_ data: Data, kind: AssetKind, originalFilename: String?) throws -> StagedAsset {
        let id = Self.assetID(for: data)
        let finalURL = url(for: id, kind: kind)
        let staged = StagedAsset(id: id, kind: kind, byteCount: Int64(data.count), originalFilename: originalFilename)
        let fm = FileManager.default

        if fm.fileExists(atPath: finalURL.path) {
            // Content addressing makes an existing file with this name the
            // same bytes, unless it was damaged; verify before reusing it.
            if let existing = try? Data(contentsOf: finalURL, options: .mappedIfSafe), Self.assetID(for: existing) == id {
                return staged
            }
            try fm.removeItem(at: finalURL)
        }

        let dir = finalURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = stagingURL.appendingPathComponent(UUID().uuidString)
        do {
            try Self.writeSynchronously(data, to: temp)
            try fm.moveItem(at: temp, to: finalURL)
            try Self.fsyncDirectory(dir)
        } catch {
            try? fm.removeItem(at: temp)
            // Another writer may have won the race with identical bytes.
            if fm.fileExists(atPath: finalURL.path) { return staged }
            throw StoreError.io("Could not store asset: \(error.localizedDescription)")
        }
        return staged
    }

    /// Writes the file at `source` durably without ever holding it whole in
    /// memory: the bytes are hashed as they are copied, so a large video costs
    /// one buffer rather than its own size. Identical bytes already present
    /// are reused, as with `store(_:kind:originalFilename:)`.
    public func store(contentsOf source: URL, kind: AssetKind, originalFilename: String?) throws -> StagedAsset {
        let fm = FileManager.default
        let temp = stagingURL.appendingPathComponent(UUID().uuidString)
        guard fm.createFile(atPath: temp.path, contents: nil) else {
            throw StoreError.io("Could not create a staging file")
        }

        var digest = SHA256()
        var byteCount: Int64 = 0
        do {
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            let writer = try FileHandle(forWritingTo: temp)
            defer { try? writer.close() }
            while let chunk = try reader.read(upToCount: Self.copyBufferSize), !chunk.isEmpty {
                digest.update(data: chunk)
                try writer.write(contentsOf: chunk)
                byteCount += Int64(chunk.count)
            }
            try writer.synchronize()
        } catch {
            try? fm.removeItem(at: temp)
            throw StoreError.io("Could not read \(source.lastPathComponent): \(error.localizedDescription)")
        }

        let id = AssetID(sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
        let staged = StagedAsset(id: id, kind: kind, byteCount: byteCount, originalFilename: originalFilename)
        let finalURL = url(for: id, kind: kind)

        if fm.fileExists(atPath: finalURL.path) {
            // Same name means the same bytes unless the file was damaged.
            // Checking the size first avoids rehashing a large healthy file
            // only to confirm what it already told us.
            let existingSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            if existingSize == byteCount, (try? verify(id, kind: kind)) != nil {
                try? fm.removeItem(at: temp)
                return staged
            }
            try fm.removeItem(at: finalURL)
        }

        let dir = finalURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: temp, to: finalURL)
            try Self.fsyncDirectory(dir)
        } catch {
            try? fm.removeItem(at: temp)
            if fm.fileExists(atPath: finalURL.path) { return staged }
            throw StoreError.io("Could not store asset: \(error.localizedDescription)")
        }
        return staged
    }

    static let copyBufferSize = 1 << 20

    public func read(_ id: AssetID, kind: AssetKind) throws -> Data {
        let fileURL = url(for: id, kind: kind)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw StoreError.assetMissing(id.sha256)
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    /// Recomputes the checksum; used by integrity checks and before upload.
    public func verify(_ id: AssetID, kind: AssetKind) throws {
        let data = try read(id, kind: kind)
        guard Self.assetID(for: data) == id else { throw StoreError.assetChecksumMismatch(id.sha256) }
    }

    func remove(_ id: AssetID, kind: AssetKind) throws {
        let fileURL = url(for: id, kind: kind)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Every stored asset file with its modification date.
    func allFiles() throws -> [(url: URL, id: AssetID, modified: Date)] {
        let fm = FileManager.default
        var result: [(URL, AssetID, Date)] = []
        for shard in try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) {
            guard shard.lastPathComponent != ".staging", shard.hasDirectoryPath else { continue }
            for file in try fm.contentsOfDirectory(at: shard, includingPropertiesForKeys: [.contentModificationDateKey]) {
                let name = file.deletingPathExtension().lastPathComponent
                guard name.count == 64 else { continue }
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                result.append((file, AssetID(sha256: name), modified))
            }
        }
        return result
    }

    /// Deletes leftover staging files from interrupted writes.
    func clearStaging(olderThan cutoff: Date) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: stagingURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    static func writeSynchronously(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw StoreError.io("Could not create \(url.lastPathComponent)")
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    static func fsyncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = fsync(fd)
    }
}

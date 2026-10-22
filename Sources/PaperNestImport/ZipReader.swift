import Compression
import Foundation

/// Reads ZIP archives (PKWARE APPNOTE 6.3) that other apps made, which means
/// treating every one of them as hostile until proven otherwise.
///
/// `ZipWriter` in PaperNestExport writes the archives PaperNest produces and
/// only needs "stored" entries; this reader also inflates method 8, because
/// almost everything else compresses.
///
/// Refused outright: entries that escape the destination, symbolic links,
/// encrypted entries, methods other than stored and deflate, and archives
/// that would expand past the caller's limits. A refusal names the entry.
public struct ZipReader: Sendable {
    public struct Entry: Sendable, Equatable {
        public var path: String
        public var isDirectory: Bool
        public var compressedSize: Int64
        public var uncompressedSize: Int64
        var method: UInt16
        var crc32: UInt32
        var localHeaderOffset: Int
        var isSymbolicLink: Bool
        var isEncrypted: Bool
    }

    /// What an extraction is allowed to cost. The defaults are deliberately
    /// finite: an archive is untrusted input, not a promise.
    public struct Limits: Sendable {
        public var maximumEntries: Int
        public var maximumTotalBytes: Int64
        /// Uncompressed ÷ compressed, per entry. A zip bomb's whole trick.
        public var maximumExpansionRatio: Double

        public init(maximumEntries: Int = 10_000,
                    maximumTotalBytes: Int64 = 2 << 30,
                    maximumExpansionRatio: Double = 200) {
            self.maximumEntries = maximumEntries
            self.maximumTotalBytes = maximumTotalBytes
            self.maximumExpansionRatio = maximumExpansionRatio
        }
    }

    public enum ArchiveError: Error, Equatable {
        case notAnArchive
        case damaged(String)
        case unsupportedEntry(String)
        case encryptedEntry(String)
        case unsafePath(String)
        case symbolicLink(String)
        case tooManyEntries(limit: Int)
        case tooLarge(limit: Int64)
    }

    public let entries: [Entry]
    private let data: Data

    public init(data: Data, limits: Limits = Limits()) throws {
        self.data = data
        guard data.count >= 22 else { throw ArchiveError.notAnArchive }
        let directory = try Self.centralDirectoryRange(in: data)
        var parsed: [Entry] = []
        var cursor = directory.lowerBound
        while cursor + 46 <= directory.upperBound, data.u32(cursor) == 0x0201_4b50 {
            let flags = data.u16(cursor + 8)
            let method = data.u16(cursor + 10)
            let crc = data.u32(cursor + 16)
            let compressed = Int64(data.u32(cursor + 20))
            let uncompressed = Int64(data.u32(cursor + 24))
            let nameLength = Int(data.u16(cursor + 28))
            let extraLength = Int(data.u16(cursor + 30))
            let commentLength = Int(data.u16(cursor + 32))
            let externalAttributes = data.u32(cursor + 38)
            let offset = Int(data.u32(cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ArchiveError.damaged("central directory") }
            let raw = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(decoding: raw, as: UTF8.self)
            let unixMode = (externalAttributes >> 16) & 0xF000
            parsed.append(Entry(
                path: name,
                isDirectory: name.hasSuffix("/"),
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                method: method,
                crc32: crc,
                localHeaderOffset: offset,
                isSymbolicLink: unixMode == 0xA000,
                isEncrypted: flags & 1 == 1
            ))
            cursor = nameStart + nameLength + extraLength + commentLength
            guard parsed.count <= limits.maximumEntries else { throw ArchiveError.tooManyEntries(limit: limits.maximumEntries) }
        }
        guard !parsed.isEmpty else { throw ArchiveError.notAnArchive }
        entries = parsed
    }

    /// Checks every entry before writing anything, so a bad archive cannot
    /// leave half of itself on disk.
    public func extract(to destination: URL, limits: Limits = Limits()) throws -> [URL] {
        var total: Int64 = 0
        for entry in entries {
            _ = try Self.safeRelativePath(entry)
            guard !entry.isSymbolicLink else { throw ArchiveError.symbolicLink(entry.path) }
            guard !entry.isEncrypted else { throw ArchiveError.encryptedEntry(entry.path) }
            guard entry.isDirectory || entry.method == 0 || entry.method == 8 else {
                throw ArchiveError.unsupportedEntry(entry.path)
            }
            if entry.compressedSize > 0 {
                let ratio = Double(entry.uncompressedSize) / Double(entry.compressedSize)
                guard ratio <= limits.maximumExpansionRatio else { throw ArchiveError.tooLarge(limit: limits.maximumTotalBytes) }
            }
            total += entry.uncompressedSize
            guard total <= limits.maximumTotalBytes else { throw ArchiveError.tooLarge(limit: limits.maximumTotalBytes) }
        }

        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            for entry in entries {
                let relative = try Self.safeRelativePath(entry)
                let target = destination.appendingPathComponent(relative)
                if entry.isDirectory {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try Task.checkCancellation()
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let bytes = try contents(of: entry)
                try bytes.write(to: target, options: .atomic)
                written.append(target)
            }
        } catch {
            // Nothing half-extracted is left behind.
            try? fm.removeItem(at: destination)
            throw error
        }
        return written
    }

    /// The bytes of one entry, inflated and checked against its CRC.
    public func contents(of entry: Entry) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.u32(header) == 0x0403_4b50 else {
            throw ArchiveError.damaged(entry.path)
        }
        let nameLength = Int(data.u16(header + 26))
        let extraLength = Int(data.u16(header + 28))
        let start = header + 30 + nameLength + extraLength
        let end = start + Int(entry.compressedSize)
        guard end <= data.count else { throw ArchiveError.damaged(entry.path) }
        let payload = data.subdata(in: start..<end)

        let bytes: Data
        switch entry.method {
        case 0:
            bytes = payload
        case 8:
            bytes = try Self.inflate(payload, expecting: Int(entry.uncompressedSize), named: entry.path)
        default:
            throw ArchiveError.unsupportedEntry(entry.path)
        }
        guard Int64(bytes.count) == entry.uncompressedSize else { throw ArchiveError.damaged(entry.path) }
        guard Self.crc32(bytes) == entry.crc32 else { throw ArchiveError.damaged(entry.path) }
        return bytes
    }

    // MARK: - Safety

    /// A path that stays inside the destination: no absolute paths, no
    /// drive letters, no `..`, and no empty or `.` components.
    static func safeRelativePath(_ entry: Entry) throws -> String {
        let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.contains(":") else {
            throw ArchiveError.unsafePath(entry.path)
        }
        var components: [String] = []
        for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
            guard component != "..", component != "." else { throw ArchiveError.unsafePath(entry.path) }
            components.append(String(component))
        }
        guard !components.isEmpty else { throw ArchiveError.unsafePath(entry.path) }
        return components.joined(separator: "/")
    }

    static func centralDirectoryRange(in data: Data) throws -> Range<Int> {
        // The end record is last, after a comment of up to 64 KiB.
        let lowest = max(0, data.count - 22 - 65_535)
        var index = data.count - 22
        while index >= lowest {
            if data.u32(index) == 0x0605_4b50 {
                let size = Int(data.u32(index + 12))
                let offset = Int(data.u32(index + 16))
                guard offset >= 0, size >= 0, offset + size <= data.count else { throw ArchiveError.damaged("end record") }
                return offset..<(offset + size)
            }
            index -= 1
        }
        throw ArchiveError.notAnArchive
    }

    static func inflate(_ payload: Data, expecting size: Int, named name: String) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let produced: Int = output.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard produced == size else { throw ArchiveError.damaged(name) }
        return output
    }

    static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= count, offset >= 0 else { return 0 }
        return UInt32(self[startIndex + offset])
            | UInt32(self[startIndex + offset + 1]) << 8
            | UInt32(self[startIndex + offset + 2]) << 16
            | UInt32(self[startIndex + offset + 3]) << 24
    }
}

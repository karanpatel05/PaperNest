import Foundation
import Testing
@testable import PaperNestImport

/// F2b: reading archives other apps made. The fixtures here are built by
/// `/usr/bin/zip` where a real archive is needed, and by hand where a real
/// tool refuses to produce something hostile.
@Suite struct ZipReaderTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZipReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A ZIP with one stored entry under any name we like, including names a
    /// real archiver would refuse to write.
    private func handBuiltArchive(name: String, contents: Data, unixMode: UInt32 = 0o100_644) -> Data {
        let nameBytes = Array(name.utf8)
        let crc = ZipReader.crc32(contents)
        var local = Data()
        local.appendLE(UInt32(0x0403_4b50))
        local.appendLE(UInt16(20)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0))
        local.appendLE(UInt16(0)); local.appendLE(UInt16(0))
        local.appendLE(crc)
        local.appendLE(UInt32(contents.count)); local.appendLE(UInt32(contents.count))
        local.appendLE(UInt16(nameBytes.count)); local.appendLE(UInt16(0))
        local.append(contentsOf: nameBytes)
        local.append(contents)

        var central = Data()
        central.appendLE(UInt32(0x0201_4b50))
        central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0))
        central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
        central.appendLE(crc)
        central.appendLE(UInt32(contents.count)); central.appendLE(UInt32(contents.count))
        central.appendLE(UInt16(nameBytes.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
        central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
        central.appendLE(unixMode << 16)
        central.appendLE(UInt32(0))
        central.append(contentsOf: nameBytes)

        var end = Data()
        end.appendLE(UInt32(0x0605_4b50))
        end.appendLE(UInt16(0)); end.appendLE(UInt16(0))
        end.appendLE(UInt16(1)); end.appendLE(UInt16(1))
        end.appendLE(UInt32(central.count)); end.appendLE(UInt32(local.count))
        end.appendLE(UInt16(0))

        return local + central + end
    }

    @Test func readsARealDeflatedArchiveAndRestoresItByteForByte() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Repetitive content, so /usr/bin/zip actually deflates it.
        let body = Data(String(repeating: "quarterly statement ", count: 500).utf8)
        try body.write(to: dir.appendingPathComponent("report.txt"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: dir.appendingPathComponent("notes/inner.txt"))
        let zipped = try run("/usr/bin/zip", ["-q", "-r", "archive.zip", "report.txt", "notes"], in: dir)
        #expect(zipped == 0)

        let reader = try ZipReader(data: try Data(contentsOf: dir.appendingPathComponent("archive.zip")))
        #expect(reader.entries.contains { $0.path == "report.txt" && !$0.isDirectory })
        let compressed = try #require(reader.entries.first { $0.path == "report.txt" })
        #expect(compressed.method == 8, "the fixture should be deflated, not stored")
        #expect(compressed.compressedSize < compressed.uncompressedSize)

        let out = dir.appendingPathComponent("out", isDirectory: true)
        let written = try reader.extract(to: out)
        #expect(written.count == 2)
        let restored = try Data(contentsOf: out.appendingPathComponent("report.txt"))
        let inner = try Data(contentsOf: out.appendingPathComponent("notes/inner.txt"))
        #expect(restored == body)
        #expect(inner == Data("inner".utf8))
    }

    @Test(arguments: ["../escape.txt", "/etc/passwd", "notes/../../escape.txt", "..\\windows.txt", "C:/x.txt"])
    func anEntryThatEscapesTheDestinationIsRefused(_ name: String) async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = handBuiltArchive(name: name, contents: Data("owned".utf8))
        let reader = try ZipReader(data: archive)
        let out = dir.appendingPathComponent("out", isDirectory: true)

        #expect(throws: ZipReader.ArchiveError.unsafePath(name)) { try reader.extract(to: out) }
        // Nothing was written anywhere, inside or outside the destination.
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.txt").path))
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aSymbolicLinkIsRefusedRatherThanRecreated() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        let zipped = try run("/usr/bin/zip", ["-q", "--symlinks", "links.zip", "link"], in: dir)
        #expect(zipped == 0)

        let reader = try ZipReader(data: try Data(contentsOf: dir.appendingPathComponent("links.zip")))
        #expect(reader.entries.contains { $0.isSymbolicLink }, "the fixture should contain a real symlink entry")
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(throws: ZipReader.ArchiveError.symbolicLink("link")) { try reader.extract(to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func anEntryThatExpandsTooFarIsRefused() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Highly compressible: a real bomb's shape, in miniature.
        try Data(repeating: 0, count: 400_000).write(to: dir.appendingPathComponent("zeros.bin"))
        let zipped = try run("/usr/bin/zip", ["-q", "-9", "bomb.zip", "zeros.bin"], in: dir)
        #expect(zipped == 0)
        let data = try Data(contentsOf: dir.appendingPathComponent("bomb.zip"))

        let strict = ZipReader.Limits(maximumExpansionRatio: 10)
        let reader = try ZipReader(data: data)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(throws: ZipReader.ArchiveError.self) { try reader.extract(to: out, limits: strict) }
        #expect(!FileManager.default.fileExists(atPath: out.path))

        // The same archive is fine when the caller allows that much.
        let written = try reader.extract(to: out, limits: ZipReader.Limits(maximumExpansionRatio: 10_000))
        #expect(written.count == 1)
    }

    @Test func anArchiveLargerThanTheBudgetIsRefusedBeforeAnythingIsWritten() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(String(repeating: "a", count: 60_000).utf8).write(to: dir.appendingPathComponent("big.txt"))
        let zipped = try run("/usr/bin/zip", ["-q", "big.zip", "big.txt"], in: dir)
        #expect(zipped == 0)

        let reader = try ZipReader(data: try Data(contentsOf: dir.appendingPathComponent("big.zip")))
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(throws: ZipReader.ArchiveError.tooLarge(limit: 1_000)) {
            try reader.extract(to: out, limits: ZipReader.Limits(maximumTotalBytes: 1_000, maximumExpansionRatio: 10_000))
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func anEncryptedEntryIsRefusedAndSaysSo() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("secret".utf8).write(to: dir.appendingPathComponent("secret.txt"))
        let encrypted = try run("/usr/bin/zip", ["-q", "-P", "hunter2", "locked.zip", "secret.txt"], in: dir)
        guard encrypted == 0 else {
            Issue.record("zip could not make an encrypted fixture")
            return
        }
        let reader = try ZipReader(data: try Data(contentsOf: dir.appendingPathComponent("locked.zip")))
        let allEncrypted = reader.entries.allSatisfy { $0.isEncrypted }
        #expect(allEncrypted)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(throws: ZipReader.ArchiveError.encryptedEntry("secret.txt")) { try reader.extract(to: out) }
    }

    @Test func damagedContentIsCaughtByTheChecksum() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var archive = handBuiltArchive(name: "note.txt", contents: Data("original".utf8))
        // Flip a byte of the stored payload; the CRC in the headers no longer matches.
        let payloadIndex = 30 + "note.txt".utf8.count
        archive[payloadIndex] = archive[payloadIndex] ^ 0xFF

        let reader = try ZipReader(data: archive)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(throws: ZipReader.ArchiveError.damaged("note.txt")) { try reader.extract(to: out) }
    }

    @Test func somethingThatIsNotAnArchiveIsRejected() async throws {
        #expect(throws: ZipReader.ArchiveError.notAnArchive) { try ZipReader(data: Data("not a zip at all".utf8)) }
        #expect(throws: ZipReader.ArchiveError.notAnArchive) { try ZipReader(data: Data()) }
    }

    @Test func ourOwnStoredArchivesReadBackUnchanged() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = handBuiltArchive(name: "plain.txt", contents: Data("stored entry".utf8))
        let reader = try ZipReader(data: archive)
        #expect(reader.entries.map(\.method) == [0])
        let out = dir.appendingPathComponent("out", isDirectory: true)
        let written = try reader.extract(to: out)
        #expect(written.count == 1)
        let restored = try Data(contentsOf: written[0])
        #expect(restored == Data("stored entry".utf8))
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

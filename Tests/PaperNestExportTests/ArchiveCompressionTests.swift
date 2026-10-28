import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Row 35's last remainder. The archive already packed a selection; it could
/// not make any of it smaller, and ZIP's own deflate does nearly nothing to a
/// PDF or a JPEG.
///
/// Two rules carry this: never drop an entry, and never grow one.
@Suite struct ArchiveCompressionTests {
    private let scanRaster = SyntheticDocuments.textImage(
        lines: Array(repeating: "Invoice total 1234 EUR", count: 20), width: 1600, height: 2000)

    private func scannedDocument(_ fixture: ExportFixture) async throws -> LibraryExportEntry {
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(raster: scanRaster), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        return .document(LibraryExportItem(name: item.name, pages: pages))
    }

    private func looseFile(_ name: String, _ data: Data, in directory: URL) throws -> LibraryExportEntry {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return .file(name: name, originalFilename: name, url: url)
    }

    private func entries(of output: ExportOutput) throws -> [String] {
        let listed = try unzip(["-Z1", output.files[0].path])
        return listed.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    @Test func aPresetMakesAnArchiveOfScansSmaller() async throws {
        let fixture = try ExportFixture()
        let entry = try await scannedDocument(fixture)

        let plain = try await fixture.exporter.exportArchive([entry], archiveName: "Backup")
        defer { plain.removeTemporaryFiles() }
        let compressed = try await fixture.exporter.exportArchive([entry], archiveName: "Backup",
                                                                  preset: .smallest)
        defer { compressed.removeTemporaryFiles() }

        #expect(compressed.totalByteCount < plain.totalByteCount,
                "compressed \(compressed.totalByteCount) vs plain \(plain.totalByteCount)")
    }

    /// An archive missing a file is data loss, and invisible until someone
    /// goes looking. Anything that cannot be compressed goes in as it was.
    @Test func nothingIsEverDroppedFromTheArchive() async throws {
        let fixture = try ExportFixture()
        let scratch = fixture.url.appendingPathComponent("loose", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let mixed = [
            try await scannedDocument(fixture),
            try looseFile("notes.txt", Data("just some text".utf8), in: scratch),
            try looseFile("clip.mov", Data("not a movie either".utf8), in: scratch),
            try looseFile("photo.png", SyntheticDocuments.image(width: 1200, height: 1600, type: .png), in: scratch),
        ]

        let plain = try await fixture.exporter.exportArchive(mixed, archiveName: "Backup")
        defer { plain.removeTemporaryFiles() }
        let compressed = try await fixture.exporter.exportArchive(mixed, archiveName: "Backup", preset: .smallest)
        defer { compressed.removeTemporaryFiles() }

        #expect(try entries(of: plain).count == 4)
        #expect(try entries(of: compressed).count == 4, "an entry went missing when compressing")
    }

    /// `LibraryExportEntry` promises a file comes back as it was given, because
    /// re-encoding someone's video or spreadsheet would be a lie about what
    /// they got. A preset does not change that — it only reaches what can
    /// genuinely be re-encoded.
    @Test func aNonImageFileKeepsItsBytesExactly() async throws {
        let fixture = try ExportFixture()
        let scratch = fixture.url.appendingPathComponent("loose", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let original = Data("ledger,amount\nrent,1200\n".utf8)
        let entry = try looseFile("ledger.csv", original, in: scratch)

        let output = try await fixture.exporter.exportArchive([entry], archiveName: "Backup", preset: .smallest)
        defer { output.removeTemporaryFiles() }

        let extracted = output.directory.appendingPathComponent("unpacked", isDirectory: true)
        _ = try unzip(["-q", output.files[0].path, "-d", extracted.path])
        let back = try Data(contentsOf: extracted.appendingPathComponent("ledger.csv"))
        #expect(back == original, "the file was altered on the way into the archive")
    }

    /// A re-encode that came out bigger is thrown away and the original kept —
    /// the same rule the document and file paths already follow.
    @Test func anAlreadyCompactImageIsNotGrown() async throws {
        let fixture = try ExportFixture()
        let scratch = fixture.url.appendingPathComponent("loose", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        // A flat synthetic page stores as a tiny PNG; re-encoding makes it bigger.
        let flat = SyntheticDocuments.image(width: 1200, height: 1600, type: .png)
        let entry = try looseFile("flat.png", flat, in: scratch)

        let plain = try await fixture.exporter.exportArchive([entry], archiveName: "Backup")
        defer { plain.removeTemporaryFiles() }
        let compressed = try await fixture.exporter.exportArchive([entry], archiveName: "Backup", preset: .light)
        defer { compressed.removeTemporaryFiles() }

        #expect(compressed.totalByteCount <= plain.totalByteCount,
                "compressing grew the archive: \(compressed.totalByteCount) from \(plain.totalByteCount)")
    }

    @Test func withoutAPresetTheArchiveIsUnchanged() async throws {
        let fixture = try ExportFixture()
        let entry = try await scannedDocument(fixture)

        let a = try await fixture.exporter.exportArchive([entry], archiveName: "Backup")
        defer { a.removeTemporaryFiles() }
        let b = try await fixture.exporter.exportArchive([entry], archiveName: "Backup", preset: nil)
        defer { b.removeTemporaryFiles() }

        #expect(a.totalByteCount == b.totalByteCount)
        #expect(try entries(of: a) == entries(of: b))
    }
}

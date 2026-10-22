import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
@testable import PaperNestImport

/// F2a: bringing a file into the library as itself. Any type is accepted —
/// the bytes are kept, not interpreted — which is the owner's decision
/// recorded in docs/F2_FILE_ITEMS_DESIGN.md.
@Suite struct FileItemImportTests {
    /// Counts stored originals from the outside, without reaching into the
    /// store's internals.
    private func storedAssetCount(_ library: TestLibrary) -> Int {
        let root = library.store.assets.rootURL
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        return files.compactMap { $0 as? URL }
            .filter { !$0.path.contains("/.staging/") }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .count
    }

    private func write(_ library: TestLibrary, _ name: String, _ bytes: Data) throws -> URL {
        let url = library.url.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    @Test func anyFileTypeBecomesALibraryItemThatKeepsItsBytes() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let bytes = Data("column,value\n1,2\n".utf8)
        let url = try write(library, "Budget 2026.csv", bytes)

        let item = try await importer.importFile(at: url)
        #expect(item.kind == .file)
        #expect(item.name == "Budget 2026", "the extension belongs to the file, not the item name")

        let payload = try #require(try await library.store.filePayload(item.id))
        #expect(payload.originalFilename == "Budget 2026.csv")
        #expect(payload.byteCount == Int64(bytes.count))
        #expect(payload.uti == UTType.commaSeparatedText.identifier)
        #expect(try await library.store.assetData(payload.assetID).0 == bytes)
        #expect(try await library.store.pages(of: item.id).isEmpty)
    }

    @Test func anUnknownExtensionIsKeptAsPlainData() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let url = try write(library, "Archive.weirdext", Data([0x01, 0x02, 0x03]))

        let item = try await importer.importFile(at: url)
        let payload = try #require(try await library.store.filePayload(item.id))
        // Honest rather than guessed: bytes the system cannot identify are
        // public.data, and they are still kept.
        #expect(payload.uti == UTType.data.identifier)
        #expect(payload.originalFilename == "Archive.weirdext")
        #expect(try await library.store.assetData(payload.assetID).0 == Data([0x01, 0x02, 0x03]))
    }

    @Test func aFileLandsInTheFolderItWasImportedInto() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let folder = try await library.store.createFolder(named: "Receipts")
        let url = try write(library, "Receipt.txt", Data("paid".utf8))

        let item = try await importer.importFile(at: url, into: folder.id)
        #expect(item.folderID == folder.id)
        #expect(try await library.store.items(in: .folder(folder.id)).map(\.id) == [item.id])
    }

    @Test func twoFilesWithTheSameNameBecomeDistinctItems() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let first = try write(library, "Notes.txt", Data("one".utf8))
        let second = library.url.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let secondURL = second.appendingPathComponent("Notes.txt")
        try Data("two".utf8).write(to: secondURL)

        let a = try await importer.importFile(at: first)
        let b = try await importer.importFile(at: secondURL)
        #expect(a.name == "Notes")
        #expect(b.name == "Notes 2")
        let payloadA = try #require(try await library.store.filePayload(a.id))
        let payloadB = try #require(try await library.store.filePayload(b.id))
        #expect(payloadA.assetID != payloadB.assetID, "different bytes, different assets")
    }

    @Test func importingTheSameBytesTwiceStoresThemOnce() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let bytes = Data("identical".utf8)
        let first = try write(library, "A.bin", bytes)
        let second = try write(library, "B.bin", bytes)

        let a = try await importer.importFile(at: first)
        let b = try await importer.importFile(at: second)
        let payloadA = try #require(try await library.store.filePayload(a.id))
        let payloadB = try #require(try await library.store.filePayload(b.id))
        #expect(payloadA.assetID == payloadB.assetID)
        #expect(storedAssetCount(library) == 1, "content addressing should store one copy")
        // Each item keeps the name it was imported under.
        #expect(payloadA.originalFilename == "A.bin")
        #expect(payloadB.originalFilename == "B.bin")
    }

    @Test func aMissingFileFailsWithoutLeavingAnItem() async throws {
        let library = try TestLibrary()
        let importer = FileItemImporter(store: library.store)
        let missing = library.url.appendingPathComponent("not-there.pdf")

        await #expect(throws: ImportError.self) { try await importer.importFile(at: missing) }
        #expect(try await library.store.items(in: .all).isEmpty)
        #expect(storedAssetCount(library) == 0)
    }
}

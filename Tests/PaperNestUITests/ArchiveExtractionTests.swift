import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// F2b through the real view model: unpacking an archive the user brought in,
/// and refusing one that is not safe to unpack.
@MainActor
@Suite(.serialized) struct ArchiveExtractionTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestArchive-\(UUID().uuidString)", isDirectory: true)
        libraryURL = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func readySession() async throws -> LibrarySession {
        let session = LibrarySession(libraryURL: libraryURL)
        await session.bootstrap()
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            throw CancellationError()
        }
        return session
    }

    @discardableResult
    private func zip(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Imports `archive` as a file item and returns its summary.
    private func importArchive(_ archive: URL, _ session: LibrarySession, _ library: LibraryModel) async throws -> LibraryStore.ItemSummary {
        let env = try #require(session.environment)
        _ = try await FileItemImporter(store: env.store).importFile(at: archive)
        await library.reload()
        return try #require(library.items.first { $0.item.kind == .file })
    }

    @Test func extractingPutsEachFileInAFolderOfItsOwn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try SyntheticDocuments.textPDF(pages: ["Inside the archive"]).write(to: staging.appendingPathComponent("Letter.pdf"))
        try Data("plain notes".utf8).write(to: staging.appendingPathComponent("Notes.txt"))
        let status = try zip(["-q", "Bundle.zip", "Letter.pdf", "Notes.txt"], in: staging)
        #expect(status == 0)

        let session = try await readySession()
        let library = LibraryModel(session: session)
        let archive = try await importArchive(staging.appendingPathComponent("Bundle.zip"), session, library)
        #expect(archive.item.name == "Bundle")

        #expect(await library.extractArchive(archive))

        let env = try #require(session.environment)
        let folder = try #require(try await env.store.folders().first { $0.name == "Bundle" })
        let extracted = try await env.store.items(in: .folder(folder.id))
        #expect(extracted.count == 2)
        // A PDF inside the archive becomes a real document, not an opaque file.
        let letter = try #require(extracted.first { $0.item.name == "Letter" })
        #expect(letter.item.kind == .document)
        #expect(letter.pageCount == 1)
        // Anything we cannot make pages from is still kept.
        let notes = try #require(extracted.first { $0.item.name == "Notes" })
        #expect(notes.item.kind == .file)
        #expect(notes.file?.originalFilename == "Notes.txt")
        #expect(try await env.store.assetData(try #require(notes.file).assetID).0 == Data("plain notes".utf8))
        // The archive itself is kept; unpacking is not moving.
        #expect(try await env.store.item(archive.id) != nil)
        #expect(library.presentedError == nil)
    }

    @Test func anArchiveWeCannotOpenSafelyAddsNothingAndSaysSo() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: staging.appendingPathComponent("secret.txt"))
        let status = try zip(["-q", "-P", "hunter2", "Locked.zip", "secret.txt"], in: staging)
        guard status == 0 else {
            Issue.record("zip could not make an encrypted fixture")
            return
        }

        let session = try await readySession()
        let library = LibraryModel(session: session)
        let archive = try await importArchive(staging.appendingPathComponent("Locked.zip"), session, library)
        let before = try await #require(session.environment).store.items(in: .all)

        #expect(await library.extractArchive(archive) == false)
        #expect(library.presentedError?.message == L10n.extractArchiveFailed)

        let env = try #require(session.environment)
        #expect(try await env.store.folders().isEmpty, "a refused archive must not leave a folder behind")
        #expect(try await env.store.items(in: .all) == before)
    }

    @Test func aFileThatIsNotAnArchiveIsRefusedRatherThanGuessedAt() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        // A .zip extension over bytes that are not a ZIP at all.
        try Data("definitely not a zip".utf8).write(to: staging.appendingPathComponent("Fake.zip"))

        let session = try await readySession()
        let library = LibraryModel(session: session)
        let archive = try await importArchive(staging.appendingPathComponent("Fake.zip"), session, library)

        #expect(await library.extractArchive(archive) == false)
        let env = try #require(session.environment)
        #expect(try await env.store.folders().isEmpty)
    }
}

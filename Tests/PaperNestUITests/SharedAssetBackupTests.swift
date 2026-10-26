import Foundation
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Originals are immutable and shared by hash, so a file item can point at
/// bytes that were first stored as a document's PDF. The `assets` row keeps
/// whichever kind arrived first, and the file on disk is named after that
/// kind, so every path that resolves an original has to read the record
/// rather than assume. Getting this wrong does not drop one entry: the
/// archive writer reads each file with `Data(contentsOf:)` and throws the
/// whole archive away, so one such item loses the user's entire backup.
@MainActor
@Suite(.serialized) struct SharedAssetBackupTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestSharedAsset-\(UUID().uuidString)", isDirectory: true)
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

    private func settle(upTo ticks: Int = 200, _ condition: () -> Bool) async throws {
        for _ in 0..<ticks where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func entries(of archive: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// A file item whose original was stored as a PDF, which is what happens
    /// when the same bytes reach the library as a document first.
    private func fileItemSharingAPDFOriginal(_ env: AppEnvironment) async throws -> (LibraryItem, Data) {
        let bytes = SyntheticDocuments.textPDF(pages: ["Shared original"])
        let staged = try env.store.assets.store(bytes, kind: .pdf, originalFilename: "shared.pdf")
        let item = try await env.store.createFileItem(named: "Shared PDF", asset: staged,
                                                     uti: "com.adobe.pdf", originalFilename: "shared.pdf")
        return (item, bytes)
    }

    @Test func bulkArchiveIncludesAFileWhoseOriginalWasStoredUnderAnotherKind() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let env = try #require(session.environment)
        let (item, bytes) = try await fileItemSharingAPDFOriginal(env)

        let model = BulkExportModel(session: session)
        model.start([item.id], archiveName: "Selected")
        try await settle { model.output != nil || model.hasFailed }

        let output = try #require(model.output, "one shared original must not fail the whole archive")
        // The exporter's temporary root is shared, and other tests check that
        // nothing is left in it.
        defer { output.removeTemporaryFiles() }
        #expect(try entries(of: output.files[0]) == ["shared.pdf"])

        let extracted = root.appendingPathComponent("bulk-unzipped", isDirectory: true)
        try unzip(output.files[0], into: extracted)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("shared.pdf")) == bytes,
                "the archive must hold the real original, byte for byte")
    }

    @Test func settingsBackupIncludesAFileWhoseOriginalWasStoredUnderAnotherKind() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let env = try #require(session.environment)
        let (_, bytes) = try await fileItemSharingAPDFOriginal(env)

        let model = SettingsModel(session: session)
        model.startBackup()
        try await settle { model.backupOutput != nil || model.backupHasFailed }

        let output = try #require(model.backupOutput, "a backup that fails outright is not a backup")
        defer { output.removeTemporaryFiles() }
        let extracted = root.appendingPathComponent("backup-unzipped", isDirectory: true)
        try unzip(output.files[0], into: extracted)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("shared.pdf")) == bytes)
    }

    private func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archive.path, "-d", directory.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

private extension BulkExportModel {
    var hasFailed: Bool { if case .failed = phase { return true }; return false }
}

private extension SettingsModel {
    var backupOutput: ExportOutput? { if case .ready(let output) = backup { return output }; return nil }
    var backupHasFailed: Bool { if case .failed = backup { return true }; return false }
}

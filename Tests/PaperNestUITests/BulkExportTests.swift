import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// F1 follow-up: exporting several chosen documents as one ZIP of PDFs,
/// through the same model the selection bar drives.
@MainActor
@Suite(.serialized) struct BulkExportTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestBulkExport-\(UUID().uuidString)", isDirectory: true)
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

    /// Entry names in stored order, which is the order they were written.
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

    @Test func archiveHoldsOnlyTheChosenDocuments_inSelectionOrder_skippingEmptyOnes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.pdf")
        let b = root.appendingPathComponent("B.pdf")
        try SyntheticDocuments.textPDF(pages: ["Alpha", "Beta"]).write(to: a)
        try SyntheticDocuments.textPDF(pages: ["Gamma"]).write(to: b)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([a, b])
        await library.reload()
        let env = try #require(session.environment)
        let aID = try #require(library.items.first { $0.item.name == "A" }?.id)
        let bID = try #require(library.items.first { $0.item.name == "B" }?.id)
        let empty = try await env.store.createItem(kind: .document, name: "Empty", pages: [], assets: [])
        let untouched = try await env.store.items(in: .all)

        let model = BulkExportModel(session: session)
        // Selection order, not library order, and an empty document in the middle.
        model.start([bID, empty.id, aID], archiveName: "Selected")
        try await settle { model.output != nil }
        let output = try #require(model.output, "the export never became ready")

        #expect(output.files.count == 1)
        #expect(output.files[0].lastPathComponent == "Selected.zip")
        #expect(try entries(of: output.files[0]) == ["B.pdf", "A.pdf"])

        let extracted = root.appendingPathComponent("unzipped", isDirectory: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", output.files[0].path, "-d", extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
        let first = try #require(PDFDocument(url: extracted.appendingPathComponent("B.pdf")))
        let second = try #require(PDFDocument(url: extracted.appendingPathComponent("A.pdf")))
        #expect(first.pageCount == 1)
        #expect(second.pageCount == 2)
        #expect(first.page(at: 0)?.string?.contains("Gamma") == true)
        #expect(second.page(at: 1)?.string?.contains("Beta") == true)

        // Exporting reads the library; it must not change it.
        #expect(try await env.store.items(in: .all) == untouched)

        let archive = output.files[0]
        model.finish()
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        if case .idle = model.phase {} else { Issue.record("the sheet should return to idle after finishing") }
    }

    @Test func filesGoInAsThemselvesAndDocumentsAsPDFs() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let letter = root.appendingPathComponent("Letter.pdf")
        try SyntheticDocuments.textPDF(pages: ["Alpha"]).write(to: letter)
        let notes = root.appendingPathComponent("Notes.txt")
        let noteBytes = Data("plain text, kept exactly\n".utf8)
        try noteBytes.write(to: notes)

        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([letter, notes])
        await library.reload()
        let env = try #require(session.environment)
        let document = try #require(library.items.first { $0.item.kind == .document })
        let file = try #require(library.items.first { $0.item.kind == .file })

        let model = BulkExportModel(session: session)
        model.start([file.id, document.id], archiveName: "Mixed")
        try await settle { model.output != nil }
        let output = try #require(model.output)
        defer { model.finish() }

        // Selection order, and the file keeps its own name and extension.
        #expect(try entries(of: output.files[0]) == ["Notes.txt", "Letter.pdf"])

        let extracted = root.appendingPathComponent("mixed", isDirectory: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", output.files[0].path, "-d", extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        // The file is byte-for-byte what was imported: not re-encoded.
        let restored = try Data(contentsOf: extracted.appendingPathComponent("Notes.txt"))
        #expect(restored == noteBytes)
        let pdf = try #require(PDFDocument(url: extracted.appendingPathComponent("Letter.pdf")))
        #expect(pdf.pageCount == 1)
        #expect(pdf.page(at: 0)?.string?.contains("Alpha") == true)
        #expect(try await env.store.items(in: .all).count == 2, "exporting must not change the library")
    }

    @Test func anArchiveOfOnlyFilesIsStillProduced() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appendingPathComponent("Only.txt")
        try Data("just a file".utf8).write(to: notes)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([notes])
        await library.reload()
        let file = try #require(library.items.first)

        let model = BulkExportModel(session: session)
        model.start([file.id], archiveName: "Files")
        try await settle { model.output != nil }
        let output = try #require(model.output, "a selection with no pages at all should still archive")
        defer { model.finish() }
        #expect(try entries(of: output.files[0]) == ["Only.txt"])
    }

    /// The Settings backup is the one place that promises "everything".
    @Test func theLibraryBackupIncludesFilesNotJustDocuments() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let letter = root.appendingPathComponent("Letter.pdf")
        try SyntheticDocuments.textPDF(pages: ["Alpha"]).write(to: letter)
        let notes = root.appendingPathComponent("Receipt.txt")
        try Data("a receipt".utf8).write(to: notes)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([letter, notes])
        await library.reload()

        let settings = SettingsModel(session: session)
        settings.startBackup()
        try await settle {
            if case .ready = settings.backup { return true } else { return false }
        }
        guard case .ready(let output) = settings.backup else {
            Issue.record("the backup never became ready: \(settings.backup)")
            return
        }
        defer { settings.finishBackup() }
        let names = try entries(of: output.files[0]).sorted()
        #expect(names == ["Letter.pdf", "Receipt.txt"], "a backup must carry files too, got \(names)")
    }

    @Test func cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Long.pdf")
        try SyntheticDocuments.textPDF(pages: (1...12).map { "Page \($0)" }).write(to: file)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([file])
        await library.reload()
        let id = try #require(library.items.first?.id)
        let env = try #require(session.environment)

        let model = BulkExportModel(session: session)
        model.start([id], archiveName: "Cancelled")
        model.cancel()
        if case .idle = model.phase {} else { Issue.record("cancel must return the sheet to idle at once") }
        // A late finish must not resurrect a ready state or leave a file.
        // A 12-page export takes well under this, so the wait is generous.
        try await settle(upTo: 40) { false }
        if case .ready = model.phase { Issue.record("a cancelled export must not become ready") }
        let temporaries = try FileManager.default.contentsOfDirectory(atPath: env.exporter.temporaryRoot.path)
        #expect(temporaries.allSatisfy { !$0.hasPrefix("PaperNestExport-") }, "left behind: \(temporaries)")
    }

    @Test func anEmptySelectionAndEmptyDocumentsNeverProduceAnArchive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let env = try #require(session.environment)
        let empty = try await env.store.createItem(kind: .document, name: "Empty", pages: [], assets: [])

        let model = BulkExportModel(session: session)
        model.start([], archiveName: "Nothing")
        if case .idle = model.phase {} else { Issue.record("an empty selection must not start an export") }

        model.start([empty.id], archiveName: "Nothing")
        try await settle { if case .failed = model.phase { return true } else { return false } }
        if case .failed = model.phase {} else { Issue.record("a page-less selection must fail, not write an empty archive") }
        #expect(model.output == nil)
    }
}

import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The M1 workflow through the same view models the windows use:
/// import → edit → quit → relaunch → reopen → export, with nothing lost.
/// SwiftUI view rendering is not covered here (see docs/TEST_MATRIX.md).
@MainActor
@Suite(.serialized) struct LibraryWorkflowTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestWorkflow-\(UUID().uuidString)", isDirectory: true)
        libraryURL = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writeSample(_ data: Data, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func readySession() async throws -> LibrarySession {
        let session = LibrarySession(libraryURL: libraryURL)
        await session.bootstrap()
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            throw CancellationError()
        }
        return session
    }

    /// Undo handlers finish their store work asynchronously.
    func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    @Test func importEditRelaunchAndExportKeepsPagesAndOrientation() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let letter = try writeSample(SyntheticDocuments.textPDF(pages: ["Alpha page", "Bêta page", "Gamma página"]), "Letter.pdf")
        let receipt = try writeSample(SyntheticDocuments.image(width: 600, height: 900, type: .jpeg, exifOrientation: 6), "Receipt.jpg")
        let locked = try writeSample(SyntheticDocuments.encryptedPDF(text: "Locked text", password: "sample"), "Locked.pdf")
        let notes = try writeSample(Data("not a document".utf8), "notes.txt")

        // --- First launch: import ---
        var session: LibrarySession? = try await readySession()
        let library = LibraryModel(session: session!)
        await library.importFiles([letter, receipt, locked, notes])
        #expect(library.presentedError?.title == L10n.importErrorTitle("notes.txt"))
        #expect(library.passwordQueue.map(\.filename) == ["Locked.pdf"])

        await library.submitPassword("wrong", for: library.passwordQueue[0])
        #expect(library.passwordQueue.first?.lastAttemptFailed == true)
        await library.submitPassword("sample", for: library.passwordQueue[0])
        #expect(library.passwordQueue.isEmpty)

        await library.reload()
        #expect(Set(library.items.map(\.item.name)) == ["Letter", "Receipt", "Locked"])
        let letterID = try #require(library.items.first { $0.item.name == "Letter" }?.id)

        // --- Edit: rotate page 2, move page 3 to the front, delete + undo ---
        let undo = UndoManager()
        let document = DocumentModel(itemID: letterID, session: session!)
        await document.load()
        let original = document.pages
        document.selectedPageID = original[1].id
        await document.rotate(clockwise: true, undoManager: undo)
        document.selectedPageID = original[2].id
        await document.moveSelected(by: -2, undoManager: undo)
        #expect(document.pages.map(\.id) == [original[2].id, original[0].id, original[1].id])

        document.selectedPageID = original[0].id
        await document.deleteSelectedPage(undoManager: undo)
        #expect(document.pages.count == 2)
        undo.undo()
        // The inverse must be registered while undoing, or Redo is lost.
        #expect(undo.canRedo)
        try await eventually { document.pages.count == 3 }
        #expect(document.pages.map(\.id) == [original[2].id, original[0].id, original[1].id])
        undo.redo()
        #expect(undo.canUndo)
        try await eventually { document.pages.count == 2 }
        undo.undo()
        try await eventually { document.pages.count == 3 }
        #expect(document.pages.map(\.id) == [original[2].id, original[0].id, original[1].id])

        // Rotation undo/redo round trip.
        document.selectedPageID = original[0].id
        await document.rotate(clockwise: true, undoManager: undo)
        undo.undo()
        #expect(undo.canRedo)
        try await eventually { document.pages.first { $0.id == original[0].id }?.transform.rotation == QuarterTurns.none }
        undo.redo()
        try await eventually { document.pages.first { $0.id == original[0].id }?.transform.rotation == .clockwise90 }
        undo.undo()
        try await eventually { document.pages.first { $0.id == original[0].id }?.transform.rotation == QuarterTurns.none }

        // --- Quit and relaunch ---
        session = nil
        let relaunched = try await readySession()
        let reopenedLibrary = LibraryModel(session: relaunched)
        await reopenedLibrary.reload()
        #expect(reopenedLibrary.items.count == 3)
        let reopened = DocumentModel(itemID: letterID, session: relaunched)
        await reopened.load()
        #expect(reopened.pages.map(\.id) == [original[2].id, original[0].id, original[1].id])
        #expect(reopened.pages.map(\.transform.rotation) == [.none, .none, .clockwise90])

        // --- Export what was reopened ---
        let env = try #require(relaunched.environment)
        let output = try await env.exporter.export(itemName: "Letter", pages: reopened.pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(pdf.pageCount == 3)
        #expect(pdf.page(at: 0)?.string?.contains("Gamma página") == true)
        #expect(pdf.page(at: 1)?.string?.contains("Alpha page") == true)
        #expect(pdf.page(at: 2)?.string?.contains("Bêta page") == true)
        #expect(pdf.page(at: 2)?.bounds(for: .mediaBox).size == CGSize(width: 792, height: 612))

        // The photo was stored upright (EXIF applied) and stays portrait.
        let receiptID = try #require(reopenedLibrary.items.first { $0.item.name == "Receipt" }?.id)
        let receiptPage = try #require(try await env.store.pages(of: receiptID).first)
        #expect(receiptPage.geometry.pageSize.height > receiptPage.geometry.pageSize.width)
    }

    @Test func recentlyDeletedRecoverAndPermanentDelete() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([try writeSample(SyntheticDocuments.textPDF(pages: ["x"]), "Temp.pdf")])
        await library.reload()
        let id = try #require(library.items.first?.id)

        await library.moveToRecentlyDeleted([id])
        await library.reload()
        #expect(library.items.isEmpty)
        library.scope = .recentlyDeleted
        await library.reload()
        #expect(library.items.map(\.id) == [id])

        await library.recover([id])
        library.scope = .all
        await library.reload()
        #expect(library.items.map(\.id) == [id])

        await library.moveToRecentlyDeleted([id])
        await library.deletePermanently([id])
        library.scope = .recentlyDeleted
        await library.reload()
        #expect(library.items.isEmpty)
    }

    @Test func searchFiltersByTitleIgnoringAccents() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([
            try writeSample(SyntheticDocuments.textPDF(pages: ["1"]), "Relevé bancaire.pdf"),
            try writeSample(SyntheticDocuments.textPDF(pages: ["2"]), "Factura.pdf"),
        ])
        library.searchText = "releve"
        await library.reload()
        #expect(library.items.map(\.item.name) == ["Relevé bancaire"])
    }

    @Test func newerLibraryShowsAnUpdateMessageInsteadOfOpening() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LibraryStore(directory: libraryURL)
        let db = libraryURL.appendingPathComponent(LibraryStore.databaseFilename).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [db, "PRAGMA user_version = 99;"]
        try process.run()
        process.waitUntilExit()

        let session = LibrarySession(libraryURL: libraryURL)
        await session.bootstrap()
        guard case .failed(let title, let message) = session.state else {
            Issue.record("expected failure, got \(session.state)")
            return
        }
        #expect(title == L10n.libraryErrorTitle)
        #expect(message == L10n.libraryNewer)
    }
}

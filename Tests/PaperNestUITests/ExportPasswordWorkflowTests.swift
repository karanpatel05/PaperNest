import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
@testable import PaperNestUI

/// The export sheet's password, taken all the way to a file on disk.
///
/// `ExportPasswordTests` covers which passwords the sheet allows, and
/// `EncryptedExportTests` covers that the engine really encrypts. Between
/// them sat the link nobody had exercised: the value the sheet decides on
/// reaching the exporter. Typing into the field could not be driven — a
/// secure text field refuses synthetic typing from the background, and
/// taking over the screen was not approved — so this runs the same value
/// through the same call the sheet makes.
///
/// **What it still does not cover:** the SwiftUI binding from the keystroke
/// to `@State password`. Everything after that is here.
@MainActor
@Suite(.serialized) struct ExportPasswordWorkflowTests {
    private let typed = "Quarterly-2026"

    private func exported(password typedPassword: String) async throws -> (URL, ExportOutput) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestPasswordFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = LibrarySession(libraryURL: root.appendingPathComponent("Library", isDirectory: true))
        await session.bootstrap()
        let environment = try #require(session.environment)
        let library = LibraryModel(session: session)
        let id = try await library.createNotebook(named: "Statement", template: .lined)
        let pages = try await environment.store.pages(of: id)

        // Exactly what the sheet does: refuse nothing, then hand over the
        // value `passwordToUse` decides on.
        #expect(ExportSheet.passwordProblem(in: typedPassword, format: .pdf) == nil)
        let output = try await environment.exporter.export(
            itemName: "Statement", pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original),
            password: ExportSheet.passwordToUse(typedPassword))
        return (output.files[0], output)
    }

    /// The whole point: what someone types into the field is what the file
    /// then demands.
    @Test func aTypedPasswordIsWhatTheWrittenFileAsksFor() async throws {
        let (file, output) = try await exported(password: typed)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: file))
        #expect(document.isLocked, "the file opened without a password")
        #expect(document.unlock(withPassword: "wrong-one") == false)
        #expect(document.unlock(withPassword: typed), "the typed password does not open it")
    }

    /// An untouched field must leave the file unprotected rather than
    /// protected by an empty password — the failure mode the engine's
    /// `emptyPassword` refusal exists to prevent, seen from this side.
    @Test func anUntouchedFieldLeavesTheFileUnprotected() async throws {
        let (file, output) = try await exported(password: "")
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: file))
        #expect(!document.isLocked)
        #expect(!document.isEncrypted, "a file nobody asked to protect came out encrypted")
    }
}

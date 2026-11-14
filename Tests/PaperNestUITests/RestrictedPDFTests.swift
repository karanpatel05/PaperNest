import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// What the screens do with a PDF whose author switched copying or printing
/// off: what they offer, what they refuse, and how they say why.
@MainActor @Suite struct RestrictedPDFTests {
    private let noCopying = DocumentPermissions(allowsCopying: false, allowsPrinting: true)
    private let noPrinting = DocumentPermissions(allowsCopying: true, allowsPrinting: false)

    private func session() async throws -> (URL, LibrarySession, AppEnvironment) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRestricted-\(UUID().uuidString)", isDirectory: true)
        let session = LibrarySession(libraryURL: url)
        await session.bootstrap()
        return (url, session, try #require(session.environment))
    }

    // MARK: - Export

    /// A format the exporter would refuse is not offered in the first place.
    @Test func whereCopyingIsOffOnlyAPDFIsOffered() {
        #expect(ExportSheet.formats(offeredFor: noCopying).map(\.format) == [.pdf])
        #expect(ExportSheet.formats(offeredFor: .unknown).map(\.format) == [.pdf])
        #expect(Set(ExportSheet.formats(offeredFor: .unrestricted).map(\.format)) == Set(ExportFormat.allCases))
        // Printing switched off says nothing about taking the words out.
        #expect(Set(ExportSheet.formats(offeredFor: noPrinting).map(\.format)) == Set(ExportFormat.allCases))
    }

    /// "The export couldn't be completed" would send someone looking for a
    /// fault. Nothing failed: the author said no.
    @Test func aRefusalOnTheAuthorsBehalfSaysSo() {
        #expect(ExportSheet.message(for: .copyingNotAllowed) == L10n.restrictedExportRefused)
        #expect(ExportSheet.message(for: .printingNotAllowed) == L10n.restrictedPrintRefused)
        #expect(ExportSheet.message(for: .copyingNotAllowed) != L10n.exportFailed)
        #expect(ExportSheet.message(for: .printingNotAllowed) != L10n.exportFailed)
    }

    // MARK: - The open document

    @Test func anOpenDocumentKnowsWhatItsAuthorAllows() async throws {
        let (url, session, environment) = try await session()
        defer { try? FileManager.default.removeItem(at: url) }
        let form = try await environment.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["Application"]), name: "Form.pdf"))
        let letter = try await environment.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Letter"]), name: "Letter.pdf"))

        let restricted = DocumentModel(itemID: form.id, session: session)
        #expect(restricted.permissions == .unrestricted, "nothing is known before the pages are read")
        await restricted.load()
        let ordinary = DocumentModel(itemID: letter.id, session: session)
        await ordinary.load()

        #expect(restricted.permissions == noCopying)
        #expect(ordinary.permissions == .unrestricted)
    }

    // MARK: - Print

    @MainActor final class Panel {
        var files: [Data] = []
        func show(_ job: PrintJob) async { files.append((try? Data(contentsOf: job.file)) ?? Data()) }
    }

    /// A form that may be printed reaches the print panel, and the file the
    /// panel is handed is still closed to copying — the panel can save a PDF.
    @Test func aFormThatMayBePrintedReachesThePanelStillClosedToCopying() async throws {
        let (url, _, environment) = try await session()
        defer { try? FileManager.default.removeItem(at: url) }
        let form = try await environment.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["Application", "Signature"]), name: "Form.pdf"))
        let page = try #require(try await environment.store.pages(of: form.id).first)
        try await environment.store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 20,
                                    points: [InkPoint(x: 300, y: 600), InkPoint(x: 500, y: 600)])),
            modifiedAt: Date()))
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show)

        await printer.print(form.id, in: environment)?.value

        let printed = try #require(panel.files.first)
        let document = try #require(CGDataProvider(data: printed as CFData).flatMap(CGPDFDocument.init))
        #expect(document.numberOfPages == 2)
        #expect(document.isUnlocked && document.allowsPrinting)
        #expect(!document.allowsCopying, "the file handed to the print panel can be copied from")
        #expect(!printer.isShowingFailure)
    }

    @Test func aDocumentThatMayNotBePrintedSaysWhyAndShowsNoPanel() async throws {
        let (url, _, environment) = try await session()
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = try await environment.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["Draft"], allowsCopying: true, allowsPrinting: false),
                  name: "Draft.pdf"))
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show)

        await printer.print(draft.id, in: environment)?.value

        #expect(panel.files.isEmpty)
        #expect(printer.isShowingFailure)
        #expect(printer.failureMessage == L10n.restrictedPrintRefused)
        #expect(printer.phase == .idle)
    }

    /// The ordinary failure still says what it always said.
    @Test func anyOtherPrintFailureKeepsItsOwnMessage() async throws {
        let (url, _, environment) = try await session()
        defer { try? FileManager.default.removeItem(at: url) }
        let printer = DocumentPrinter(panel: { _ in })

        await printer.print(ItemID(rawValue: "no-such-document"), in: environment)?.value

        #expect(printer.isShowingFailure)
        #expect(printer.failureMessage == L10n.printFailed)
    }
}

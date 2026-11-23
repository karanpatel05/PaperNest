import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Page comments written into an exported PDF as notes — the sticky notes
/// Preview and Acrobat show in the margin — when, and only when, the export
/// asks for them. Read back from the written file on each path the writer can
/// take: the untouched original handed back, a rebuilt page, a password.
@Suite struct CommentExportTests {
    private func comment(_ text: String, on page: Page, _ fixture: ExportFixture) async throws {
        _ = try await fixture.store.setPageComment(on: page.id, replacing: nil, text: text)
    }

    private func notes(on page: PDFPage?) -> [PDFAnnotation] {
        (page?.annotations ?? []).filter { $0.type == "Text" }
    }

    private func export(_ fixture: ExportFixture, _ pages: [Page], comments: Bool, password: String? = nil,
                        paper: PaperSize = .original) async throws -> ExportOutput {
        var options = ExportOptions(format: .pdf, paperSize: paper)
        options.includesComments = comments
        return try await fixture.exporter.export(itemName: "Doc", pages: pages, options: options, password: password)
    }

    @Test func eachCommentBecomesANoteOnItsOwnPage() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["First page", "Second page"])
        try await comment("Check the total", on: pages[0], fixture)
        try await comment("Sign here", on: pages[1], fixture)
        try await comment("Ask Ana about the date", on: pages[1], fixture)

        let output = try await export(fixture, pages, comments: true)
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(pdf.pageCount == 2)
        #expect(notes(on: pdf.page(at: 0)).map(\.contents) == ["Check the total"])
        #expect(notes(on: pdf.page(at: 1)).compactMap(\.contents).sorted() == ["Ask Ana about the date", "Sign here"])
        // Every note sits on its page, and two notes on one page do not cover each other.
        for index in 0..<2 {
            let page = try #require(pdf.page(at: index))
            let box = page.bounds(for: .mediaBox)
            let placed = notes(on: page).map(\.bounds)
            #expect(placed.allSatisfy { box.contains($0) }, "page \(index + 1): a note is off the page")
            for (a, b) in zip(placed, placed.dropFirst()) { #expect(!a.intersects(b), "page \(index + 1): notes overlap") }
        }
        // The page's own words are still there: the notes are added, nothing is redrawn.
        #expect(pdf.page(at: 0)?.string?.contains("First page") == true)
    }

    @Test func commentsStayOutOfAnExportThatDidNotAskForThem() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["First page"])
        try await comment("Private thought", on: pages[0], fixture)
        let output = try await export(fixture, pages, comments: false)
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(notes(on: pdf.page(at: 0)).isEmpty)
        let bytes = try Data(contentsOf: output.files[0])
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Private thought"))
    }

    /// Asking for comments in a document that has none leaves the export
    /// exactly as it would have been: an untouched import is still handed back
    /// byte for byte, not rewritten for nothing.
    @Test func askingWithNoCommentsChangesNothing() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["First page"])
        let plain = try await export(fixture, pages, comments: false)
        defer { plain.removeTemporaryFiles() }
        let asked = try await export(fixture, pages, comments: true)
        defer { asked.removeTemporaryFiles() }
        #expect(try Data(contentsOf: plain.files[0]) == Data(contentsOf: asked.files[0]))
    }

    @Test func notesSurviveAPassword() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["First page", "Second page"])
        try await comment("For your eyes", on: pages[1], fixture)
        // Something drawn on the first page, so the file is a rebuild with the
        // second page copied in — the path that re-applies the password.
        try await fixture.store.saveObject(PageObject(pageID: pages[0].id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 4,
                                    points: [InkPoint(x: 72, y: 700), InkPoint(x: 300, y: 700)])), modifiedAt: Date()))

        let output = try await export(fixture, pages, comments: true, password: "correct-horse")
        defer { output.removeTemporaryFiles() }
        let bytes = try Data(contentsOf: output.files[0])
        #expect(String(decoding: bytes, as: UTF8.self).contains("/Encrypt"), "the notes cost the password")
        let pdf = try #require(PDFDocument(data: bytes))
        #expect(pdf.isLocked)
        #expect(pdf.unlock(withPassword: "correct-horse"))
        #expect(notes(on: pdf.page(at: 1)).map(\.contents) == ["For your eyes"])
        #expect(notes(on: pdf.page(at: 0)).isEmpty)
    }

    /// On Letter paper the page is fitted inside the sheet; its notes go in
    /// the page's corner, not the paper's empty margin.
    @Test func notesGoOnThePageWhereItSitsOnThePaper() async throws {
        let fixture = try ExportFixture()
        // A wide page on portrait paper is turned to landscape and fitted,
        // leaving bands of empty paper above and below it.
        let (_, pages) = try await fixture.importPDF(["Wide page"], size: CGSize(width: 800, height: 300))
        try await comment("Corner note", on: pages[0], fixture)
        let output = try await export(fixture, pages, comments: true, paper: .usLetter)
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        let page = try #require(pdf.page(at: 0))
        let layout = PaperLayout(pageSize: CGSize(width: 800, height: 300), paper: .usLetter)
        // The page's place on the paper, in PDF space (y up).
        let content = CGRect(x: layout.contentRect.minX, y: layout.paperSize.height - layout.contentRect.maxY,
                             width: layout.contentRect.width, height: layout.contentRect.height)
        let note = try #require(notes(on: page).first)
        #expect(content.contains(note.bounds), "note at \(note.bounds), page at \(content)")
        // Near the page's top left, where a reader looks first.
        #expect(note.bounds.minX - content.minX < 40 && content.maxY - note.bounds.maxY < 40)
    }

    /// A comment is the reader's text; it is written as it was typed, accents
    /// and all, and a long one is not cut.
    @Test func aNoteKeepsItsWordsAsTyped() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Page"])
        let long = "Vérifier l’année — año. " + String(repeating: "More detail. ", count: 200)
        try await comment(long, on: pages[0], fixture)
        let output = try await export(fixture, pages, comments: true)
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(notes(on: pdf.page(at: 0)).first?.contents == long.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A file whose author switched copying off stays closed to copying when
    /// notes are added — handed back whole, or rebuilt after a drawing.
    @Test(arguments: [false, true]) func aRestrictedFileKeepsItsLimitsWithNotes(drawnOn: Bool) async throws {
        let fixture = try ExportFixture()
        let original = SyntheticDocuments.restrictedPDF(pages: ["Form", "Signature"], allowsCopying: false,
                                                        allowsPrinting: true)
        let item = try await fixture.importer.importItem(.data(original, name: "Form.pdf"))
        let pages = try await fixture.store.pages(of: item.id)
        try await comment("Initial each page", on: pages[0], fixture)
        if drawnOn {
            try await fixture.store.saveObject(PageObject(pageID: pages[1].id, zKey: "m",
                payload: .ink(InkStroke(tool: .pen, color: .black, width: 20,
                                        points: [InkPoint(x: 300, y: 600), InkPoint(x: 500, y: 600)])), modifiedAt: Date()))
        }
        let output = try await export(fixture, pages, comments: true)
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])
        let written = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
        #expect(written.isEncrypted, "the notes cost the author's limits")
        #expect(!written.allowsCopying, "copying was switched back on")
        #expect(written.numberOfPages == 2)
        let pdf = try #require(PDFDocument(data: data))
        #expect(notes(on: pdf.page(at: 0)).map(\.contents) == ["Initial each page"])
    }

    @Test func imagesAndWordsCarryNoNotes() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Page"])
        try await comment("Only for PDF", on: pages[0], fixture)
        var options = ExportOptions(format: .png)
        options.includesComments = true
        let output = try await fixture.exporter.export(itemName: "Doc", pages: pages, options: options)
        defer { output.removeTemporaryFiles() }
        #expect(output.files.allSatisfy { $0.pathExtension == "png" })
    }
}

import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
import PaperNestCore
@testable import PaperNestStore
@testable import PaperNestImport

/// Owner, 2026-11-15: "all files should be editable". A file that is text
/// becomes pages on import, so it opens in the editor to be marked up, instead
/// of sitting in the library as a file that only previews. Files that are not
/// text still fall through to being kept as files.
@Suite struct TextDocumentImportTests {
    /// The words on every page of an imported document, read back from the
    /// stored PDF rather than from what was handed in.
    private func storedText(of item: PaperNestCore.LibraryItem, in lib: TestLibrary) async throws -> String {
        let pages = try await lib.store.pages(of: item.id)
        var text: [String] = []
        for page in pages {
            guard case .pdfPage(let asset, let index) = page.content else {
                Issue.record("expected a PDF page, got \(page.content)")
                continue
            }
            let data = try await lib.store.assetData(asset).0
            text.append(PDFTextExtractor.text(in: data, pageIndexes: [index])[index] ?? "")
        }
        return text.joined(separator: " ")
    }

    @Test func aTextFileBecomesPagesWhoseWordsReadBack() async throws {
        let lib = try TestLibrary()
        let file = try lib.writeFile(Data("Meeting notes\nBuy more paper\n".utf8), named: "Notes.txt")
        let item = try await lib.importer.importItem(.file(file))

        #expect(item.name == "Notes")
        #expect(try await lib.store.pages(of: item.id).count == 1)
        let text = try await storedText(of: item, in: lib)
        #expect(text.contains("Meeting notes"))
        #expect(text.contains("Buy more paper"))
    }

    /// Markdown, CSV, logs, source code and JSON are all text to read and mark up.
    @Test(arguments: ["Plan.md", "Budget.csv", "Server.log", "Script.swift", "Settings.json"])
    func otherTextFormatsBecomePagesToo(_ filename: String) async throws {
        let lib = try TestLibrary()
        let file = try lib.writeFile(Data("quarterly figures 2026\n".utf8), named: filename)
        let item = try await lib.importer.importItem(.file(file))

        #expect(try await storedText(of: item, in: lib).contains("quarterly figures 2026"))
    }

    @Test func textInUTF16ReadsBackToo() async throws {
        let lib = try TestLibrary()
        let file = try lib.writeFile(try #require("Reçu café 12,50 €".data(using: .utf16)), named: "Receipt.txt")
        let item = try await lib.importer.importItem(.file(file))

        #expect(try await storedText(of: item, in: lib).contains("Reçu café 12,50 €"))
    }

    @Test func anRTFFileBecomesPagesWhoseWordsReadBack() async throws {
        let lib = try TestLibrary()
        let rtf = #"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0\fs24 Contract summary\par {\b Signed} by both parties\par}"#
        let file = try lib.writeFile(Data(rtf.utf8), named: "Contract.rtf")
        let item = try await lib.importer.importItem(.file(file))

        let text = try await storedText(of: item, in: lib)
        #expect(text.contains("Contract summary"))
        #expect(text.contains("Signed by both parties"))
        #expect(!text.contains("rtf1"), "the RTF is laid out, not printed as its source")
    }

    #if os(macOS)
    /// The Mac reads Word itself, so a Word file becomes pages in the importer
    /// (owner, 2026-11-15: "Yes, build both"). iPhone and iPad lay Word out
    /// in the app instead, where WebKit can; see `OfficeDocumentRenderer`.
    @Test(arguments: [("Proposal.docx", NSAttributedString.DocumentType.officeOpenXML),
                      ("Proposal.doc", NSAttributedString.DocumentType.docFormat)])
    func aWordFileBecomesPagesOnTheMac(_ filename: String, _ type: NSAttributedString.DocumentType) async throws {
        let lib = try TestLibrary()
        let lines = ["Project proposal", "Prepared for the quarterly review"] + (1...80).map { "Line \($0) of the proposal" }
        let source = NSAttributedString(string: lines.joined(separator: "\n"))
        let word = try source.data(from: NSRange(location: 0, length: source.length), documentAttributes: [.documentType: type])
        let item = try await lib.importer.importItem(.file(try lib.writeFile(word, named: filename)))

        #expect(item.name == "Proposal")
        #expect(try await lib.store.pages(of: item.id).count >= 2, "80 lines run onto a second page")
        let text = try await storedText(of: item, in: lib)
        #expect(text.contains("Project proposal"))
        #expect(text.contains("Line 80 of the proposal"), "nothing is lost at a page break")
    }
    #endif

    /// Not text, or nothing in it: kept as the file it is, not turned into
    /// pages of garbage or a blank page.
    @Test(arguments: [
        ("Archive.bin", Data([0x00, 0x01, 0xFF, 0xFE, 0x00, 0x7F, 0x80, 0x00])),
        ("Binary.txt", Data([0x48, 0x69, 0x00, 0x00, 0xFF, 0xD9, 0x00])),
        ("Blank.txt", Data(" \n\t \n".utf8)),
        ("Sheet.xlsx", Data("PK\u{03}\u{04} not really a spreadsheet".utf8)),
    ])
    func filesThatAreNotTextStayUnsupported(_ filename: String, _ bytes: Data) async throws {
        let lib = try TestLibrary()
        let file = try lib.writeFile(bytes, named: filename)
        await #expect(throws: ImportError.unsupportedType(filename: filename)) {
            try await lib.importer.importItem(.file(file))
        }
        #expect(try await lib.store.items(in: .all).isEmpty)
        #expect(try lib.store.assets.allFiles().isEmpty, "a refused file leaves nothing behind")
    }
}

import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// What the export sheet says will happen to a form's fillable fields,
/// checked against what really happens: for each case the answer of
/// `formFieldFate` beside the fields read back from the exported file.
@Suite struct FormFieldFateTests {
    private let password = "correct-horse"

    private struct Case {
        let name: String
        let pages: [Page]
        let options: ExportOptions
        let password: String?
        let expected: FormFieldFate
    }

    /// The form's field names in an exported file, unlocked with `password`.
    private func fieldNames(_ data: Data, password: String?) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        if let password, !document.isUnlocked { _ = document.unlockWithPassword(password) }
        guard let catalog = document.catalog else { return 0 }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return 0 }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return 0 }
        return CGPDFArrayGetCount(fields)
    }

    private func check(_ fixture: ExportFixture, _ item: Case) async throws {
        let fate = try await fixture.exporter.formFieldFate(of: item.pages, options: item.options, password: item.password)
        #expect(fate == item.expected, "\(item.name): said \(fate), expected \(item.expected)")
        let output = try await fixture.exporter.export(itemName: "Form", pages: item.pages, options: item.options,
                                                       password: item.password)
        defer { output.removeTemporaryFiles() }
        guard item.options.format == .pdf else { return }
        let fields = fieldNames(try Data(contentsOf: output.files[0]), password: item.password)
        switch fate {
        case .kept: #expect(fields > 0, "\(item.name): said kept, but the export has no fields")
        case .lost: #expect(fields == 0, "\(item.name): said lost, but the export still has fields")
        case .notApplicable: break
        }
    }

    private func form(_ fixture: ExportFixture, _ data: Data = SyntheticDocuments.acroFormPDF(
        fields: [.init(name: "customer"), .init(name: "city")])) async throws -> [Page] {
        let item = try await fixture.importer.importItem(.data(data, name: "Form"))
        return try await fixture.store.pages(of: item.id)
    }

    @Test func whatTheSheetSaysIsWhatTheExportDoes() async throws {
        let fixture = try ExportFixture()
        let pages = try await form(fixture)
        let pdf = ExportOptions(format: .pdf, paperSize: .original)
        var watermarked = pdf
        watermarked.watermark = Watermark(preset: .confidential, text: "CONFIDENTIAL")
        var marked = pdf
        marked.attribution = .attribution(name: "PaperNest", logo: nil)

        let cases = [
            Case(name: "unchanged", pages: pages, options: pdf, password: nil, expected: .kept),
            Case(name: "unchanged with a password", pages: pages, options: pdf, password: password, expected: .kept),
            Case(name: "on A4", pages: pages, options: ExportOptions(format: .pdf, paperSize: .a4), password: nil, expected: .lost),
            Case(name: "a watermark", pages: pages, options: watermarked, password: nil, expected: .lost),
            Case(name: "the PaperNest mark", pages: pages, options: marked, password: nil, expected: .lost),
            Case(name: "as JPEG", pages: pages, options: ExportOptions(format: .jpeg), password: nil, expected: .notApplicable),
        ]
        for item in cases { try await check(fixture, item) }
    }

    /// Something drawn on the page redraws it.
    @Test func aPageDrawnOnLosesTheFields() async throws {
        let fixture = try ExportFixture()
        let pages = try await form(fixture)
        try await fixture.store.saveObject(PageObject(pageID: pages[0].id, zKey: "V", payload: .ink(InkStroke(
            tool: .pen, color: .black, width: 2, points: [InkPoint(x: 100, y: 100), InkPoint(x: 200, y: 140)])), modifiedAt: Date()))
        let drawn = try await fixture.store.pages(of: pages[0].itemID)

        try await check(fixture, Case(name: "drawn on", pages: drawn, options: ExportOptions(format: .pdf, paperSize: .original),
                                      password: nil, expected: .lost))
    }

    /// The same page twice is not the original file.
    @Test func aPageTwiceLosesTheFields() async throws {
        let fixture = try ExportFixture()
        let pages = try await form(fixture)
        try await check(fixture, Case(name: "a page twice", pages: [pages[0], pages[0]],
                                      options: ExportOptions(format: .pdf, paperSize: .original), password: nil, expected: .lost))
    }

    /// A form whose author restricted it: copied as it is without a password;
    /// with one, rebuilt with its limits, and its fields go.
    @Test func aRestrictedFormKeepsItsFieldsOnlyWithoutAPassword() async throws {
        let fixture = try ExportFixture()
        let pages = try await form(fixture, SyntheticDocuments.restrictedAcroFormPDF())
        let pdf = ExportOptions(format: .pdf, paperSize: .original)
        try await check(fixture, Case(name: "restricted", pages: pages, options: pdf, password: nil, expected: .kept))
        try await check(fixture, Case(name: "restricted with a password", pages: pages, options: pdf, password: password,
                                      expected: .lost))
    }

    @Test func aPDFWithoutAFormHasNothingToSay() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["A memo with no form"])
        try await check(fixture, Case(name: "no form", pages: pages, options: ExportOptions(format: .pdf, paperSize: .original),
                                      password: nil, expected: .notApplicable))
    }
}

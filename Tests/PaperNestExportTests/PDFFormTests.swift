import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestTestSupport
@testable import PaperNestExport

/// Ledger row 24. Every check here reads the written file through **Core
/// Graphics**, never PDFKit: PDFKit reports a `fieldName` whether or not the
/// document has a form at all, and that misled this project once already.
@Suite struct PDFFormTests {
    /// The catalog's AcroForm fields, as another reader would see them.
    private func formFields(in data: Data) -> [(name: String, value: String)] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), let catalog = document.catalog else { return [] }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return [] }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return [] }
        var found: [(String, String)] = []
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var title: CGPDFStringRef?, value: CGPDFStringRef?
            let name = CGPDFDictionaryGetString(field, "T", &title)
                ? (title.flatMap { CGPDFStringCopyTextString($0) } as String?) : nil
            let current = CGPDFDictionaryGetString(field, "V", &value)
                ? (value.flatMap { CGPDFStringCopyTextString($0) } as String?) : nil
            found.append((name ?? "", current ?? ""))
        }
        return found
    }

    @Test func aRealFormReportsItsFields() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "Existing"),
            .init(type: "Btn", name: "agreed"),
        ])

        let fields = try PDFForm.fields(in: data)

        #expect(fields.map(\.name) == ["customer", "agreed"])
        #expect(fields.first?.value == "Existing")
        // A checkbox is reported with its kind rather than hidden, so a caller
        // can say what it cannot fill instead of implying the form is done.
        #expect(fields.first?.isFillable == true)
        #expect(fields.last?.isFillable == false)
    }

    /// Most PDFs PaperNest itself produces are in exactly this state, so it is
    /// the common case rather than an edge.
    @Test func aPDFWithNoFormHasNoFields() throws {
        #expect(try PDFForm.fields(in: SyntheticDocuments.textPDF(pages: ["Plain"])).isEmpty)
    }

    @Test func aFilledValueIsInTheWrittenFile() throws {
        let data = SyntheticDocuments.acroFormPDF()

        let filled = try PDFForm.filled(data, with: ["customer": "Jane Appleseed"])

        #expect(formFields(in: filled).first?.name == "customer")
        #expect(formFields(in: filled).first?.value == "Jane Appleseed",
                "another reader cannot see the value")
    }

    /// Silently dropping an unknown name would let a caller believe a value
    /// was written that is not in the file.
    @Test func fillingAFieldTheFormDoesNotHaveIsRefused() throws {
        let data = SyntheticDocuments.acroFormPDF()

        #expect(throws: FormError.noSuchField("postcode")) {
            try PDFForm.filled(data, with: ["postcode": "SW1A 1AA"])
        }
    }

    @Test func fillingAPDFWithNoFormIsRefused() throws {
        #expect(throws: FormError.noForm) {
            try PDFForm.filled(SyntheticDocuments.textPDF(pages: ["Plain"]), with: ["customer": "Jane"])
        }
    }

    @Test func otherFieldsAreLeftAlone() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer"), .init(name: "reference", value: "ABC-123"),
        ])

        let filled = try PDFForm.filled(data, with: ["customer": "Jane"])

        let fields = formFields(in: filled)
        #expect(fields.first { $0.name == "reference" }?.value == "ABC-123")
        #expect(fields.first { $0.name == "customer" }?.value == "Jane")
    }

    /// Filling a form does not lock it: the field is still a field, and the
    /// next reader can change it. A caller must not call the result final.
    @Test func theFieldIsStillAFieldAfterwards() throws {
        let filled = try PDFForm.filled(SyntheticDocuments.acroFormPDF(), with: ["customer": "Jane"])

        #expect(try PDFForm.fields(in: filled).map(\.name) == ["customer"])
        #expect(try PDFForm.fields(in: filled).first?.value == "Jane")
    }
}

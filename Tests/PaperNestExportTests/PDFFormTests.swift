import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestTestSupport
@testable import PaperNestExport

/// Ledger row 24. Form existence and stored values are checked through Core
/// Graphics, never solely through PDFKit's widget metadata.
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
        // A checkbox is fillable too, and says which kind it wants.
        #expect(fields.last?.isFillable == true)
        #expect(fields.last?.isCheckbox == true)
        #expect(fields.first?.isCheckbox == false)
    }

    /// Most PDFs PaperNest itself produces are in exactly this state, so it is
    /// the common case rather than an edge.
    @Test func aPDFWithNoFormHasNoFields() throws {
        #expect(try PDFForm.fields(in: SyntheticDocuments.textPDF(pages: ["Plain"])).isEmpty)
    }

    @Test func aFilledValueIsInTheWrittenFile() throws {
        let data = SyntheticDocuments.acroFormPDF()

        let filled = try PDFForm.filled(data, with: ["customer": .text("Jane Appleseed")])

        #expect(formFields(in: filled).first?.name == "customer")
        #expect(formFields(in: filled).first?.value == "Jane Appleseed",
                "another reader cannot see the value")
    }

    /// Silently dropping an unknown name would let a caller believe a value
    /// was written that is not in the file.
    @Test func fillingAFieldTheFormDoesNotHaveIsRefused() throws {
        let data = SyntheticDocuments.acroFormPDF()

        #expect(throws: FormError.noSuchField("postcode")) {
            try PDFForm.filled(data, with: ["postcode": .text("SW1A 1AA")])
        }
    }

    @Test func fillingAPDFWithNoFormIsRefused() throws {
        #expect(throws: FormError.noForm) {
            try PDFForm.filled(SyntheticDocuments.textPDF(pages: ["Plain"]), with: ["customer": .text("Jane")])
        }
    }

    @Test func otherFieldsAreLeftAlone() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer"), .init(name: "reference", value: "ABC-123"),
        ])

        let filled = try PDFForm.filled(data, with: ["customer": .text("Jane")])

        let fields = formFields(in: filled)
        #expect(fields.first { $0.name == "reference" }?.value == "ABC-123")
        #expect(fields.first { $0.name == "customer" }?.value == "Jane")
    }

    /// Filling a form does not lock it: the field is still a field, and the
    /// next reader can change it. A caller must not call the result final.
    @Test func theFieldIsStillAFieldAfterwards() throws {
        let filled = try PDFForm.filled(SyntheticDocuments.acroFormPDF(), with: ["customer": .text("Jane")])

        #expect(try PDFForm.fields(in: filled).map(\.name) == ["customer"])
        #expect(try PDFForm.fields(in: filled).first?.value == "Jane")
    }

    /// Checked through Core Graphics: a ticked box writes both `/V` and `/AS`
    /// as names, which is what another reader looks at.
    @Test func tickingACheckboxIsVisibleToAnotherReader() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [.init(type: "Btn", name: "agreed")])

        let filled = try PDFForm.filled(data, with: ["agreed": .checked(true)])

        #expect(try PDFForm.fields(in: filled).first?.value == "on")
        #expect(rawNames(in: filled, key: "V") == ["/Yes"], "the form value was not written")
        #expect(rawNames(in: filled, key: "AS") == ["/Yes"], "the appearance state was not written")
    }

    @Test func aBoxCanBeLeftUnticked() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [.init(type: "Btn", name: "agreed")])

        let ticked = try PDFForm.filled(data, with: ["agreed": .checked(true)])
        let cleared = try PDFForm.filled(ticked, with: ["agreed": .checked(false)])

        #expect(try PDFForm.fields(in: cleared).first?.value == "off")
    }

    /// Writing "true" into a name field, or ticking a box because a string was
    /// non-empty, is a guess about what the caller meant.
    @Test func aMismatchedKindIsRefused() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer"), .init(type: "Btn", name: "agreed"),
        ])

        #expect(throws: FormError.wrongKind("agreed")) {
            try PDFForm.filled(data, with: ["agreed": .text("yes please")])
        }
        #expect(throws: FormError.wrongKind("customer")) {
            try PDFForm.filled(data, with: ["customer": .checked(true)])
        }
    }

    @Test(arguments: ["Ch", "Sig", "Btn"])
    func unsupportedWidgetsCannotReceiveText(_ type: String) throws {
        // A Btn with the pushbutton flag is not a checkbox.
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(type: type, name: "unsupported", flags: type == "Btn" ? 65_536 : 0),
        ])
        #expect(try PDFForm.fields(in: data).first?.isFillable == false)
        #expect(throws: FormError.wrongKind("unsupported")) {
            try PDFForm.filled(data, with: ["unsupported": .text("must not write")])
        }
    }

    @Test(arguments: ["Tx", "Btn"])
    func readOnlyFieldsCannotBeFilled(_ type: String) throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(type: type, name: "locked", value: "Original", flags: 1),
        ])
        #expect(try PDFForm.fields(in: data).first?.isFillable == false)
        #expect(throws: FormError.readOnlyField("locked")) {
            try PDFForm.filled(data, with: ["locked": type == "Tx" ? .text("Changed") : .checked(true)])
        }
        #expect(formFields(in: data).first?.value == "Original")
    }

    @Test func repeatedTextNamesAreRefusedRatherThanPartlyWritten() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "First"),
            .init(name: "customer", value: "Second"),
        ])
        #expect(try PDFForm.fields(in: data).allSatisfy { !$0.isFillable })
        #expect(throws: FormError.wrongKind("customer")) {
            try PDFForm.filled(data, with: ["customer": .text("Updated")])
        }
        #expect(formFields(in: data).map(\.value) == ["First", "Second"])
    }

    @Test func repeatedCheckboxNamesAreRefusedRatherThanPartlyWritten() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(type: "Btn", name: "agreed"), .init(type: "Btn", name: "agreed"),
        ])
        #expect(try PDFForm.fields(in: data).allSatisfy { !$0.isFillable })
        #expect(throws: FormError.wrongKind("agreed")) {
            try PDFForm.filled(data, with: ["agreed": .checked(true)])
        }
    }

    @Test func repeatedNamesValidateEveryWidgetBeforeFilling() throws {
        let mixed = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "shared"), .init(type: "Ch", name: "shared"),
        ])
        #expect(throws: FormError.wrongKind("shared")) {
            try PDFForm.filled(mixed, with: ["shared": .text("Cannot change a choice")])
        }
        let locked = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "shared"), .init(name: "shared", flags: 1),
        ])
        #expect(throws: FormError.readOnlyField("shared")) {
            try PDFForm.filled(locked, with: ["shared": .text("Cannot change the locked mirror")])
        }
    }

    @Test func childWidgetsAreReportedUnsupportedAndInheritReadOnlyFlag() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "Original", widgetCount: 2),
        ])
        let fields = try PDFForm.fields(in: data)
        #expect(fields.count == 2 && fields.allSatisfy { !$0.isFillable && $0.value == "Original" })
        #expect(throws: FormError.wrongKind("customer")) {
            try PDFForm.filled(data, with: ["customer": .text("Updated")])
        }

        let locked = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "Original", flags: 1, widgetCount: 2),
        ])
        #expect(try PDFForm.fields(in: locked).allSatisfy { !$0.isFillable })
        #expect(throws: FormError.readOnlyField("customer")) {
            try PDFForm.filled(locked, with: ["customer": .text("Changed")])
        }
    }

    @Test func cyclicFieldTreeIsRejectedBeforePDFKitLoadsWidgets() throws {
        let data = SyntheticDocuments.acroFormPDF(cyclicFieldTree: true)
        #expect(throws: FormError.writeFailed) { try PDFForm.fields(in: data) }
        #expect(throws: FormError.writeFailed) {
            try PDFForm.filled(data, with: ["customer": .text("No write")])
        }
    }

    /// A refusal must leave the file untouched, not half filled.
    @Test func aRefusalWritesNothingAtAll() throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer"), .init(type: "Btn", name: "agreed"),
        ])

        #expect(throws: (any Error).self) {
            try PDFForm.filled(data, with: ["customer": .text("Jane"), "agreed": .text("oops")])
        }
        // The original is unchanged: nothing was written anywhere.
        #expect(try PDFForm.fields(in: data).first?.value == "")
    }

    /// Several fills at once must all finish.
    ///
    /// Not a stress test — it pins a trap that cost a long, silent hang to
    /// find. PDFKit loads a page's annotations lazily, and building a widget
    /// makes it resolve the font named in the field's `/DA`: `/Helv` here, and
    /// in most forms Acrobat writes, which is not a real PostScript name, so
    /// CoreText goes looking for it over **synchronous XPC**. Blocking like
    /// that on several of Swift concurrency's cooperative threads at once
    /// deadlocks — before `PDFForm` took a lock, this test never returned, and
    /// not one task of it finished. The same calls on plain threads were fine,
    /// so the task group is the point of the test and not an accident of it.
    ///
    /// **If this regresses it hangs rather than fails**, and that cannot be
    /// helped: a thread stuck in `mach_msg` never reaches a cancellation
    /// point, so no time limit fires, and the starved pool cannot run the
    /// test harness either. A hang at this test's name is the warning.
    @Test func manyFillsAtOnceAllFinish() async throws {
        let data = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        // Comfortably wider than the cooperative pool, whatever this machine's
        // core count: the deadlock needs every one of its threads blocked.
        let callers = max(8, ProcessInfo.processInfo.activeProcessorCount * 2)

        let filled = await withTaskGroup(of: String?.self) { group in
            for index in 0..<callers {
                group.addTask {
                    guard let written = try? PDFForm.filled(
                        data, with: ["customer": .text("Jane \(index)")]) else { return nil }
                    return (try? PDFForm.fields(in: written))?.first?.value
                }
            }
            var found: [String] = []
            for await value in group { if let value { found.append(value) } }
            return found
        }

        // Each caller got its own value back: serializing must not mix them.
        #expect(Set(filled) == Set((0..<callers).map { "Jane \($0)" }))
    }

    /// The raw `/V` or `/AS` names of each field, as a name rather than a string.
    private func rawNames(in data: Data, key: String) -> [String] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), let catalog = document.catalog else { return [] }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return [] }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return [] }
        var found: [String] = []
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var name: UnsafePointer<Int8>?
            if CGPDFDictionaryGetName(field, key, &name), let name {
                found.append("/" + String(cString: name))
            }
        }
        return found
    }
}

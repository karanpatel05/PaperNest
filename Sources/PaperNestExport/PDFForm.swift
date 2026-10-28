import Foundation
import PDFKit

public enum FormError: Error, Equatable, Sendable {
    /// The PDF has no document-level `/AcroForm`. Most PDFs PaperNest itself
    /// writes are in this state: a widget annotation on a page is not a form.
    case noForm
    /// A value was offered for a field the form does not have. Refused rather
    /// than ignored, so a caller cannot believe it wrote something it did not.
    case noSuchField(String)
    case writeFailed
}

/// One field of a PDF's form.
public struct FormField: Hashable, Sendable {
    public let name: String
    public let value: String
    /// Which page it sits on, counting from zero.
    public let pageIndex: Int
    /// Whether `filled(_:with:)` can set it. Only text fields can be, today;
    /// a checkbox or choice field needs appearance-state handling that is not
    /// built, so it is reported with `false` rather than left out — a caller
    /// can then say what it cannot do instead of implying the form is done.
    public let isFillable: Bool
}

/// Reading and filling the form a PDF already carries.
///
/// This does not *create* forms, and PDFKit cannot: it keeps an `/AcroForm` it
/// is given but never makes one. Checks about what a filled file contains go
/// through Core Graphics, because PDFKit reports a `fieldName` for a widget
/// whether or not the document has a form at all.
public enum PDFForm {
    /// Every field of the document's form, in page order.
    ///
    /// Empty when there is no form — which is not an error, just an answer.
    public static func fields(in data: Data) throws -> [FormField] {
        guard let document = PDFDocument(data: data) else { throw FormError.writeFailed }
        guard hasAcroForm(data) else { return [] }
        var fields: [FormField] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.fieldName != nil {
                guard let name = annotation.fieldName else { continue }
                let kind = annotation.widgetFieldType
                fields.append(FormField(
                    name: name,
                    value: annotation.widgetStringValue ?? "",
                    pageIndex: index,
                    isFillable: kind == .text))
            }
        }
        return fields
    }

    /// The document with `values` written into its fields.
    ///
    /// Filling **does not flatten**: each field stays a field and the next
    /// reader can change it. That is what filling a form means, and the result
    /// must not be described as locked or final.
    public static func filled(_ data: Data, with values: [String: String]) throws -> Data {
        guard hasAcroForm(data) else { throw FormError.noForm }
        guard let document = PDFDocument(data: data) else { throw FormError.writeFailed }

        var widgets: [String: PDFAnnotation] = [:]
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if let name = annotation.fieldName, widgets[name] == nil {
                    widgets[name] = annotation
                }
            }
        }
        // Every name is checked before anything is written, so a refusal
        // leaves the document untouched rather than half filled.
        for name in values.keys where widgets[name] == nil {
            throw FormError.noSuchField(name)
        }
        for (name, value) in values {
            widgets[name]?.widgetStringValue = value
        }
        guard let written = document.dataRepresentation() else { throw FormError.writeFailed }
        return written
    }

    /// Whether the catalog really has a form, read through Core Graphics.
    /// PDFKit cannot answer this: it reports a field name for a loose widget.
    private static func hasAcroForm(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return false }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        return CGPDFArrayGetCount(fields) > 0
    }
}

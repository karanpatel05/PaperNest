import Foundation
import PDFKit

public enum FormError: Error, Equatable, Sendable {
    /// The PDF has no document-level `/AcroForm`. Most PDFs PaperNest itself
    /// writes are in this state: a widget annotation on a page is not a form.
    case noForm
    /// A value was offered for a field the form does not have. Refused rather
    /// than ignored, so a caller cannot believe it wrote something it did not.
    case noSuchField(String)
    /// Text was offered for a checkbox, or a tick for a text field. Refused
    /// rather than coerced: writing "true" into a name field, or ticking a box
    /// because a string was non-empty, is a guess about what was meant.
    case wrongKind(String)
    case writeFailed
}

/// One field of a PDF's form.
/// What to put in a field. Typed rather than a bare string so a checkbox
/// cannot be "filled" with arbitrary text, and a mismatch is refused instead
/// of being quietly coerced into something the form never said.
public enum FormValue: Hashable, Sendable {
    case text(String)
    case checked(Bool)
}

public struct FormField: Hashable, Sendable {
    public let name: String
    public let value: String
    /// Which page it sits on, counting from zero.
    public let pageIndex: Int
    /// Whether `filled(_:with:)` can set it: text fields and checkboxes can.
    ///
    /// A choice field (a dropdown or list) cannot, because picking a value
    /// means picking from the options the form declares, which this does not
    /// read. Such a field is reported with `false` rather than left out, so a
    /// caller can say what it cannot do instead of implying the form is done.
    public let isFillable: Bool
    /// True for a checkbox, which takes `.checked` rather than `.text`.
    public let isCheckbox: Bool
}

/// Reading and filling the form a PDF already carries.
///
/// This does not *create* forms, and PDFKit cannot: it keeps an `/AcroForm` it
/// is given but never makes one. Checks about what a filled file contains go
/// through Core Graphics, because PDFKit reports a `fieldName` for a widget
/// whether or not the document has a form at all.
public enum PDFForm {
    /// PDFKit's work here happens one caller at a time.
    ///
    /// Reading a page's annotations makes PDFKit build each widget, and
    /// building one makes it resolve the font named in the field's `/DA`
    /// appearance string — `/Helv` in most forms Acrobat writes, which is not
    /// a real PostScript name, so CoreText goes looking for it over
    /// **synchronous XPC**. Blocking like that on several of Swift
    /// concurrency's cooperative threads at once deadlocks: measured, eight
    /// concurrent `filled` calls in a task group never returned, not one of
    /// them, while the same eight on plain threads finished in 0.07s. Why the
    /// pool cannot recover is inside CoreText and is not claimed here.
    private static let pdfKit = NSLock()

    /// Every field of the document's form, in page order.
    ///
    /// Empty when there is no form — which is not an error, just an answer.
    public static func fields(in data: Data) throws -> [FormField] {
        pdfKit.lock()
        defer { pdfKit.unlock() }
        guard let document = PDFDocument(data: data) else { throw FormError.writeFailed }
        guard hasAcroForm(data) else { return [] }
        var fields: [FormField] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.fieldName != nil {
                guard let name = annotation.fieldName else { continue }
                let kind = annotation.widgetFieldType
                let isCheckbox = kind == .button && annotation.widgetControlType == .checkBoxControl
                fields.append(FormField(
                    name: name,
                    value: isCheckbox
                        ? (annotation.buttonWidgetState == .onState ? "on" : "off")
                        : (annotation.widgetStringValue ?? ""),
                    pageIndex: index,
                    isFillable: kind == .text || isCheckbox,
                    isCheckbox: isCheckbox))
            }
        }
        return fields
    }

    /// The document with `values` written into its fields.
    ///
    /// Filling **does not flatten**: each field stays a field and the next
    /// reader can change it. That is what filling a form means, and the result
    /// must not be described as locked or final.
    public static func filled(_ data: Data, with values: [String: FormValue]) throws -> Data {
        pdfKit.lock()
        defer { pdfKit.unlock() }
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
        // Kinds are checked up front too, so a form is never left half filled
        // because the third value turned out to be the wrong sort.
        for (name, value) in values {
            guard let widget = widgets[name] else { continue }
            let isCheckbox = widget.widgetFieldType == .button
                && widget.widgetControlType == .checkBoxControl
            switch (value, isCheckbox) {
            case (.text, true), (.checked, false):
                throw FormError.wrongKind(name)
            default: break
            }
        }
        for (name, value) in values {
            guard let widget = widgets[name] else { continue }
            switch value {
            case .text(let text):
                widget.widgetStringValue = text
            case .checked(let on):
                // PDFKit writes both `/V` and `/AS` from this, using the
                // widget's own on-state name rather than an assumed one.
                widget.buttonWidgetState = on ? .onState : .offState
            }
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

import Foundation
import PDFKit
import PaperNestCore
import PaperNestRender

public enum FormError: Error, Equatable, Sendable {
    /// The PDF has no document-level `/AcroForm`. Most PDFs PaperNest itself
    /// writes are in this state: a widget annotation on a page is not a form.
    case noForm
    /// A value was offered for a field the form does not have. Refused rather
    /// than ignored, so a caller cannot believe it wrote something it did not.
    case noSuchField(String)
    /// Text was offered for a checkbox, a tick for a text field, or a value
    /// for an unsupported widget type. Refused
    /// rather than coerced: writing "true" into a name field, or ticking a box
    /// because a string was non-empty, is a guess about what was meant.
    case wrongKind(String)
    /// A read-only field cannot be changed, including through a writable
    /// widget with the same name as a read-only sibling.
    case readOnlyField(String)
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
    /// Whether `filled(_:with:)` can set it: writable text fields and checkboxes can.
    ///
    /// A choice field (a dropdown or list) cannot, because picking a value
    /// means picking from the options the form declares, which this does not
    /// read. Such a field is reported with `false` rather than left out, so a
    /// caller can say what it cannot do instead of implying the form is done.
    /// Repeated names are also unsupported: PDFKit can write only one mirror's
    /// value or appearance even when every widget is explicitly updated.
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
        guard let readOnlyNames = try readOnlyFieldNames(in: data) else { return [] }
        guard let document = PDFDocument(data: data) else { throw FormError.writeFailed }
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
                    isFillable: !readOnlyNames.contains(name) && !annotation.isReadOnly && (kind == .text || isCheckbox),
                    isCheckbox: isCheckbox))
            }
        }
        let counts = Dictionary(grouping: fields, by: \.name).mapValues(\.count)
        return fields.map { field in
            FormField(name: field.name, value: field.value, pageIndex: field.pageIndex,
                      isFillable: field.isFillable && counts[field.name] == 1, isCheckbox: field.isCheckbox)
        }
    }

    /// The document with `values` written into its fields.
    ///
    /// Filling **does not flatten**: each field stays a field and the next
    /// reader can change it. That is what filling a form means, and the result
    /// must not be described as locked or final.
    public static func filled(_ data: Data, with values: [String: FormValue]) throws -> Data {
        pdfKit.lock()
        defer { pdfKit.unlock() }
        guard let readOnlyNames = try readOnlyFieldNames(in: data) else { throw FormError.noForm }
        guard let document = PDFDocument(data: data) else { throw FormError.writeFailed }

        var widgets: [String: [PDFAnnotation]] = [:]
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if let name = annotation.fieldName {
                    widgets[name, default: []].append(annotation)
                }
            }
        }
        // Every name is checked before anything is written, so a refusal
        // leaves the document untouched rather than half filled.
        for name in values.keys where widgets[name] == nil {
            throw FormError.noSuchField(name)
        }
        // Every widget sharing a name is checked before any mutation, including
        // inherited read-only flags. Updating only the first leaves stale values
        // or appearances elsewhere in the same form.
        for (name, value) in values {
            guard !readOnlyNames.contains(name) else { throw FormError.readOnlyField(name) }
            guard widgets[name]?.count == 1 else { throw FormError.wrongKind(name) }
            for widget in widgets[name] ?? [] {
                guard !widget.isReadOnly else { throw FormError.readOnlyField(name) }
                let isText = widget.widgetFieldType == .text
                let isCheckbox = widget.widgetFieldType == .button
                    && widget.widgetControlType == .checkBoxControl
                switch value {
                case .text:
                    guard isText else { throw FormError.wrongKind(name) }
                case .checked:
                    guard isCheckbox else { throw FormError.wrongKind(name) }
                }
            }
        }
        for (name, value) in values {
            for widget in widgets[name] ?? [] {
                switch value {
                case .text(let text):
                    widget.widgetStringValue = text
                case .checked(let on):
                    // PDFKit writes both `/V` and `/AS` from this, using the
                    // widget's own on-state name rather than an assumed one.
                    widget.buttonWidgetState = on ? .onState : .offState
                }
            }
        }
        guard let written = document.dataRepresentation() else { throw FormError.writeFailed }
        // A filled copy of a form whose author switched copying or printing
        // off has to be as closed as the form. PDFKit keeps a document's
        // encryption when it writes one it opened (measured on a USCIS form:
        // still encrypted, copying still off), and this is here so that the
        // day it stops, filling a form fails instead of quietly producing an
        // open copy of a closed file.
        if let before = PageRenderer.permissions(ofPDF: data), before.isRestricted {
            guard let after = PageRenderer.permissions(ofPDF: written),
                  before.allowsCopying || !after.allowsCopying,
                  before.allowsPrinting || !after.allowsPrinting else { throw FormError.writeFailed }
        }
        return written
    }

    /// Read flags from the original dictionaries: PDFKit can report a checkbox's
    /// `/Ff 1` as zero. Follow the form hierarchy to inherit flags and names before
    /// asking PDFKit to construct widgets. Cycles/deep malformed trees are refused.
    /// Nil means there is no real document-level form.
    private static func readOnlyFieldNames(in data: Data) throws -> Set<String>? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else { throw FormError.writeFailed }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return nil }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields,
              CGPDFArrayGetCount(fields) > 0 else { return nil }
        var names = Set<String>()
        var visitedCount = 0
        func visit(_ field: CGPDFDictionaryRef, prefix: String, inheritedFlags: CGPDFInteger, depth: Int) throws {
            guard depth < 64, visitedCount < 4_096 else { throw FormError.writeFailed }
            visitedCount += 1
            var flags = inheritedFlags
            if !CGPDFDictionaryGetInteger(field, "Ff", &flags) { flags = inheritedFlags }
            var title: CGPDFStringRef?
            let part = CGPDFDictionaryGetString(field, "T", &title)
                ? title.flatMap { CGPDFStringCopyTextString($0) } as String? : nil
            let name = part.map { prefix.isEmpty ? $0 : "\(prefix).\($0)" } ?? prefix
            if flags & 1 != 0 { names.insert(name) }
            var children: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &children), let children {
                for index in 0..<CGPDFArrayGetCount(children) {
                    var child: CGPDFDictionaryRef?
                    guard CGPDFArrayGetDictionary(children, index, &child), let child else { throw FormError.writeFailed }
                    try visit(child, prefix: name, inheritedFlags: flags, depth: depth + 1)
                }
            }
        }
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { throw FormError.writeFailed }
            try visit(field, prefix: "", inheritedFlags: 0, depth: 0)
        }
        return names
    }
}

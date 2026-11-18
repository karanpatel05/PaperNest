import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore

/// What an export does to the fillable fields of the PDFs its pages come
/// from — so the export sheet can say so before anything is written.
public enum FormFieldFate: Equatable, Sendable {
    /// No chosen page comes from a PDF with fillable fields, or the format is
    /// not a PDF (a picture or words alone, which never are fillable).
    case notApplicable
    /// The exported PDF is the original written out again, and its fields are
    /// still fields.
    case kept
    /// The pages are redrawn: the answers are drawn on them and can no longer
    /// be changed.
    case lost
}

extension Exporter {
    /// The fate of the chosen pages' form fields under `options` and a
    /// password or none, decided by **the same rules `writePDF` follows**:
    /// fields survive only when the export is the unchanged original — every
    /// page untouched (`isUntouched`), all of them in order (`wholeSourceAsset`)
    /// — and, with a password, only from a source with no author limits that
    /// is not encrypted already (`writeProtectedCopy`). Reads the pages'
    /// marks and sources; writes nothing.
    public func formFieldFate(of pages: [Page], options: ExportOptions, password: String?) async throws -> FormFieldFate {
        guard options.format == .pdf, !pages.isEmpty else { return .notApplicable }
        var sources: [AssetID: Data] = [:]
        for page in pages {
            guard case .pdfPage(let asset, _) = page.content, sources[asset] == nil else { continue }
            if let data = try await renderer.sourcePDFData(for: page) { sources[asset] = data }
        }
        guard sources.values.contains(where: Self.hasFormFields) else { return .notApplicable }

        for page in pages {
            try Task.checkCancellation()
            // Only whether anything is painted matters here, so a tiny scale.
            let layers = try await renderer.layers(for: page, pixelsPerPoint: 0.1)
            let textLayer = options.includesRecognizedText ? try await renderer.recognizedLines(for: page) : []
            guard Self.isUntouched(page, options: options, hasPaintedObjects: !layers.isEmpty,
                                   hasTextLayer: !textLayer.isEmpty) else { return .lost }
        }
        guard let asset = Self.wholeSourceAsset(of: pages, options: options, rasterQuality: nil),
              let data = sources[asset], let document = PDFDocument(data: data),
              document.pageCount == pages.count else { return .lost }
        guard password != nil else { return .kept }
        let protection = AuthorProtection(try await renderer.permissions(for: pages))
        return protection == nil && !document.isEncrypted ? .kept : .lost
    }

    /// Whether a PDF's catalog lists any form field.
    static func hasFormFields(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return false }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        return CGPDFArrayGetCount(fields) > 0
    }
}

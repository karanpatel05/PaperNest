import CoreGraphics
import Foundation
import PaperNestCore

extension PageRenderer {
    /// What the authors of these pages' PDFs allow, taken together.
    ///
    /// Read from the stored originals each time, which is what makes it
    /// trustworthy: nothing has to remember that a document is restricted, so
    /// nothing can forget — a page carries its author's limits into every
    /// document it is merged, split or duplicated into, because it carries
    /// its original. Pages that are not from a PDF add no limits.
    ///
    /// Throws when an original cannot be read (it is only in iCloud, or the
    /// file is gone). A caller that cannot export without the answer should
    /// let that travel; one that only wants to know what to offer should
    /// treat a throw as `DocumentPermissions.unknown`.
    public func permissions(for pages: [Page]) async throws -> DocumentPermissions {
        var result = DocumentPermissions.unrestricted
        var seen = Set<AssetID>()
        for page in pages {
            guard case .pdfPage(let asset, _) = page.content, seen.insert(asset).inserted else { continue }
            guard let data = try await sourcePDFData(for: page), let limits = Self.permissions(ofPDF: data) else {
                throw RenderError.sourceUnavailable
            }
            result = result.combined(with: limits)
            if result == .unknown { break }
        }
        return result
    }

    /// The limits written into a PDF, as someone opening it without the
    /// owner's password gets them. Nil when the bytes are not a PDF that opens.
    public static func permissions(ofPDF data: Data) -> DocumentPermissions? {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              document.isUnlocked else { return nil }
        return DocumentPermissions(allowsCopying: document.allowsCopying, allowsPrinting: document.allowsPrinting)
    }
}

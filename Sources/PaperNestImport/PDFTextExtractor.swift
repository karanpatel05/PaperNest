import Foundation
import PDFKit

/// Reads the text a digital PDF already carries, so a page made from a vector
/// PDF can be found by its own words and not only by its title.
///
/// This is not recognition. A scanned page is pixels and yields nothing here;
/// `TextRecognizer` is what reads words off pixels. Keeping the two apart is
/// what lets a result be honest about where its text came from.
public struct PDFTextExtractor: Sendable {
    /// The text on `pageIndex`, or nil when the bytes are not a PDF, the
    /// index falls outside the document, or the page carries no text layer.
    public static func text(in data: Data, pageIndex: Int) -> String? {
        text(in: data, pageIndexes: [pageIndex])[pageIndex]
    }

    /// The text for each of `pageIndexes` in the PDF at `url`, read in a
    /// single parse.
    ///
    /// Reading from disk lets PDFKit memory-map the file, so indexing a large
    /// original never holds all of it in memory. On a phone, loading a few
    /// hundred megabytes during launch housekeeping risks being killed.
    /// Nil when the file cannot be opened at all, which callers must treat
    /// differently from an empty result: a document that opened and carries
    /// no text has been checked, an unreadable one has not.
    public static func text(at url: URL, pageIndexes: [Int]) -> [Int: String]? {
        guard let document = PDFDocument(url: url) else { return nil }
        return text(in: document, pageIndexes: pageIndexes)
    }

    /// The text for each of `pageIndexes`, read in a **single parse**, so a
    /// long PDF is opened once rather than once per page. Pages with no text
    /// layer, and indexes outside the document, are simply absent.
    public static func text(in data: Data, pageIndexes: [Int]) -> [Int: String] {
        guard let document = PDFDocument(data: data) else { return [:] }
        return text(in: document, pageIndexes: pageIndexes)
    }

    private static func text(in document: PDFDocument, pageIndexes: [Int]) -> [Int: String] {
        var found: [Int: String] = [:]
        for index in Set(pageIndexes) where index >= 0 && index < document.pageCount {
            if let raw = document.page(at: index)?.string, let words = normalized(raw) {
                found[index] = words
            }
        }
        return found
    }

    /// PDF text extraction leaves long runs of spacing and hard line breaks
    /// behind. The search index tokenizes anyway, so the words are collapsed
    /// onto one line; a page whose "text" is only spacing counts as no text.
    static func normalized(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

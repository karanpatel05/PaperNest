import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore
import PaperNestStore

/// Reads a page's words, and where they are, into a `PageTextLayout`.
///
/// Three sources, in this order of trust:
///
/// 1. **The page's own PDF.** A box per character, straight from the file.
/// 2. **Recognition**, only when the file carries no text: a box per word.
///    A page that has both says each word once, from the file.
/// 3. **Text boxes typed onto the page**, always, after whichever came first:
///    each box is one fragment holding everything typed in it.
///
/// Nothing is stored or cached. The text is read from the asset the page
/// shows now, so it cannot describe paper the page no longer has.
extension PageRenderer {
    /// The words on `page` and where they are, less anything a crop hides.
    public func textLayout(for page: Page) async throws -> PageTextLayout {
        var pdfPage: PDFPage?
        if case .pdfPage(_, let index) = page.content, let data = try await sourcePDFData(for: page) {
            pdfPage = PDFDocument(data: data)?.page(at: index)
        }
        return try await layout(of: page, pdfPage: pdfPage, objects: store.objects(on: page.id))
    }

    /// What find matches against, for each of `pages` in turn.
    ///
    /// Text only, so it stays cheap enough to hold for every page of a long
    /// document; boxes are worked out later by `textLayout(for:)`, for the
    /// page on screen. Each source PDF is opened once however many of its
    /// pages are asked for. `each` is called once per page, in order, and a
    /// page with no text is reported as empty rather than left out — "looked,
    /// found nothing" and "not looked at yet" are different answers.
    ///
    /// A page that cannot be read — its original is not on this device, say —
    /// is reported as empty too, and the pass carries on: one unreadable page
    /// must not make every page after it unsearchable. Only cancellation
    /// stops it.
    public func searchTexts(for pages: [Page],
                            each: @Sendable (PageID, PageSearchText) async -> Void) async throws {
        var documents: [AssetID: PDFDocument] = [:]
        for page in pages {
            try Task.checkCancellation()
            do {
                await each(page.id, try await searchText(for: page, in: &documents))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await each(page.id, .empty)
            }
        }
    }

    private func searchText(for page: Page, in documents: inout [AssetID: PDFDocument]) async throws -> PageSearchText {
        var pdfPage: PDFPage?
        if case .pdfPage(let assetID, let index) = page.content {
            if documents[assetID] == nil, let data = try await sourcePDFData(for: page) {
                documents[assetID] = PDFDocument(data: data)
            }
            pdfPage = documents[assetID]?.page(at: index)
        }
        let objects = try await store.objects(on: page.id)
        // The common case — a PDF page nobody has typed on or cropped —
        // needs no boxes at all: its text is its string.
        if let raw = pdfPage?.string, page.transform.crop.isApproximately(.full),
           !objects.contains(where: { if case .text = $0.payload { true } else { false } }) {
            let text = PageSearchText(pageString: raw)
            if !text.isEmpty { return text }
        }
        return try await layout(of: page, pdfPage: pdfPage, objects: objects).searchText
    }

    private func layout(of page: Page, pdfPage: PDFPage?, objects: [PageObject]) async throws -> PageTextLayout {
        var lines = pdfPage.map { Self.embeddedLines(of: $0) } ?? []
        if lines.isEmpty {
            lines = Self.lines(from: try await recognizedLines(for: page))
        }
        lines += Self.typedLines(in: objects, sourceSize: page.sourceSize)
        return PageTextLayout(lines: lines).cropped(to: page.transform.crop)
    }

    /// A box per visible character of a PDF page.
    ///
    /// PDFKit reports character bounds in the file's own page space: y up,
    /// measured from wherever the crop box sits, and not turned by `/Rotate`.
    /// `PageGeometry.pdfToSource` is the one mapping from there to upright
    /// source space, the same one the renderer draws the page through, so a
    /// box lands on the glyph it belongs to.
    ///
    /// Each box is taken from a **selection** of the character, not from
    /// `characterBounds(at:)`. The two count differently: `string` has a line
    /// break between lines that `characterBounds(at:)` does not count, so
    /// indexing it with positions in `string` put every line's boxes one
    /// character further along than the line before's (measured: line 2's "L"
    /// came back with the "i"'s box, and by line 4 everything was three
    /// characters off). A selection is indexed the way `string` is. It is no
    /// slower: a 2,680-character form page took 3 ms.
    static func embeddedLines(of pdfPage: PDFPage) -> [PageTextLayout.Line] {
        guard let raw = pdfPage.string, !raw.isEmpty else { return [] }
        let box = pdfPage.bounds(for: .cropBox)
        let upright = PageGeometry.uprightPDFSize(box: box, rotationDegrees: pdfPage.rotation)
        guard upright.width > 0, upright.height > 0 else { return [] }
        // Normalized, so it does not matter whether the stored source size
        // was rounded: a fraction of the upright page is a fraction of it.
        let toUnit = PageGeometry.pdfToSource(box: box, rotationDegrees: pdfPage.rotation)
            .concatenating(CGAffineTransform(scaleX: 1 / upright.width, y: 1 / upright.height))
        let length = (raw as NSString).length
        return PageTextTokenizer.lines(of: raw).map { tokens in
            PageTextLayout.Line(fragments: tokens.map { token in
                var bounds = CGRect.null
                for index in token.range.location..<(token.range.location + token.range.length) where index < length {
                    let character = pdfPage.selection(for: NSRange(location: index, length: 1))?
                        .bounds(for: pdfPage) ?? .null
                    if !character.isNull, character.width > 0, character.height > 0 { bounds = bounds.union(character) }
                }
                // A character PDFKit cannot place keeps its turn in the text
                // with an empty box, so every later hit still counts right.
                let unit = bounds.isNull ? CGRect.zero : bounds.applying(toUnit)
                return PageTextLayout.Fragment(
                    text: token.text,
                    box: .exact(x: unit.minX, y: unit.minY, width: unit.width, height: unit.height),
                    spaceAfter: token.spaceAfter)
            }, origin: .embedded)
        }
    }

    /// A box per recognised word — or per line, where the words cannot be
    /// trusted to be all there.
    ///
    /// Results from before words had boxes carry none, and Vision does not
    /// box every word of every line. Using a partial list would make the
    /// unboxed words unfindable, so a line whose boxes do not account for all
    /// of its words is one fragment: a hit lights the line, which is true.
    static func lines(from recognized: [RecognizedLine]) -> [PageTextLayout.Line] {
        recognized.compactMap { line in
            let spoken = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !spoken.isEmpty else { return nil }
            let fragments = line.words.map(\.text) == spoken
                ? line.words.map { PageTextLayout.Fragment(text: $0.text, box: $0.box, spaceAfter: true) }
                : [PageTextLayout.Fragment(text: line.text, box: line.box, spaceAfter: true)]
            return PageTextLayout.Line(fragments: fragments, origin: .recognized)
        }
    }

    /// One fragment per typed text box, in the page's own paint order.
    static func typedLines(in objects: [PageObject], sourceSize: CGSize) -> [PageTextLayout.Line] {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return [] }
        return objects.compactMap { object in
            guard case .text(let textBox) = object.payload,
                  !textBox.text.allSatisfy(\.isWhitespace) else { return nil }
            let frame = textBox.frame
            return PageTextLayout.Line(fragments: [PageTextLayout.Fragment(
                text: textBox.text,
                box: .exact(x: frame.minX / sourceSize.width, y: frame.minY / sourceSize.height,
                            width: frame.width / sourceSize.width, height: frame.height / sourceSize.height),
                spaceAfter: true)], origin: .typed)
        }
    }
}

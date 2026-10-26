import Foundation
import PaperNestCore

extension Exporter {
    /// Writes `pages` as a Word file.
    ///
    /// A `.docx` is a ZIP of XML parts, so this writes the three a word
    /// processor needs — the content-type map, the package relationships and
    /// the document body — through the existing `ZipWriter`, rather than
    /// taking on a dependency for a container we can already produce.
    ///
    /// **Basic** is the operative word: one paragraph per recognized line and
    /// a page break between pages. The words, in order, in a file Word can
    /// open. Tables, columns, positioned images and everything else about
    /// layout belong to the later Office work and are deliberately absent
    /// rather than approximated badly.
    ///
    /// Text follows the same precedence as the plain-text writer: current
    /// completed recognition first, because those lines keep their structure,
    /// then the text a digital PDF already carries. Throws
    /// `ExportError.noTextToExport` when no page has any, because a Word file
    /// containing nothing is not an export of anything.
    func writeDocx(_ pages: [Page], to url: URL,
                   progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        var body: [String] = []
        var foundAnyText = false

        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            if index > 0 { body.append(Self.docxPageBreak) }

            let recognized = try await renderer.recognizedLines(for: page)
            let lines: [String]
            if !recognized.isEmpty {
                lines = recognized.map(\.text)
            } else if let embedded = try await renderer.embeddedText(for: page) {
                lines = [embedded]
            } else {
                lines = []
            }

            for line in lines {
                let escaped = Self.xmlEscaped(line)
                guard !escaped.isEmpty else { continue }
                foundAnyText = true
                body.append("<w:p><w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>")
            }
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }

        guard foundAnyText else { throw ExportError.noTextToExport }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:body>\(body.joined())</w:body></w:document>
        """
        let zip = try ZipWriter(url: url)
        try zip.addFile(named: "[Content_Types].xml", data: Data(Self.docxContentTypes.utf8))
        try zip.addFile(named: "_rels/.rels", data: Data(Self.docxPackageRelationships.utf8))
        try zip.addFile(named: "word/document.xml", data: Data(document.utf8))
        try zip.finish()
        return url
    }

    static let docxPageBreak = "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"

    /// Escapes text for XML content, and drops the characters XML 1.0 forbids.
    ///
    /// Recognized text is whatever was printed on the paper, so an ampersand
    /// is ordinary rather than exotic; written unescaped it would produce a
    /// file no word processor can open. Recognition of a noisy scan can also
    /// return control characters, which XML 1.0 does not allow at all outside
    /// tab, newline and carriage return — one of those would make the whole
    /// document unreadable, so they are dropped rather than written.
    static func xmlEscaped(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\t", "\n", "\r": escaped.append(character)
            default:
                if let scalar = character.unicodeScalars.first, scalar.value < 0x20 { continue }
                escaped.append(character)
            }
        }
        return escaped
    }

    static let docxContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    </Types>
    """

    static let docxPackageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="word/document.xml"/></Relationships>
    """
}

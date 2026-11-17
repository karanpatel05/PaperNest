import CoreGraphics
import Foundation
import PaperNestCore
import UniformTypeIdentifiers

/// One page of a Word file of page images: the size of the Word page, and
/// where on it the picture of the PaperNest page goes, in the units
/// WordprocessingML uses — twentieths of a point ("twips") for the page and
/// its margins, English Metric Units for the picture.
///
/// Everything is decided in whole twips first and the picture is derived from
/// them, so the picture is exactly the area inside the margins: a picture a
/// fraction of a point taller than that area is a line Word cannot fit, and
/// where it goes then is up to the reader.
struct DocxPageSection: Hashable, Sendable {
    /// Word's largest page, 22 inches on either side. A bigger `w:pgSz` is
    /// refused or clamped by Word itself, so a poster-sized PDF page is
    /// scaled down whole to fit rather than handed over larger than that.
    static let maximumSideTwips = 22 * 1440
    /// EMUs per twip: 914,400 to the inch over 1,440.
    static let emusPerTwip = 635

    let pageWidthTwips: Int
    let pageHeightTwips: Int
    let leftTwips: Int
    let topTwips: Int
    let rightTwips: Int
    let bottomTwips: Int

    /// - Parameters:
    ///   - pageSize: the PaperNest page as it is seen, crop and rotation
    ///     applied (`PageGeometry.pageSize`).
    ///   - paper: `.original` makes the Word page the page's own size, with
    ///     no margins; Letter or A4 fit the page whole on that sheet, as a PDF
    ///     export does (`PaperLayout`), and the space around it becomes the
    ///     margins.
    init(pageSize: CGSize, paper: PaperSize) {
        let layout = PaperLayout(pageSize: pageSize, paper: paper)
        let longest = max(layout.paperSize.width, layout.paperSize.height) * 20
        let shrink = longest > CGFloat(Self.maximumSideTwips) ? CGFloat(Self.maximumSideTwips) / longest : 1
        func twips(_ points: CGFloat) -> Int { Int((points * 20 * shrink).rounded()) }

        pageWidthTwips = max(1, twips(layout.paperSize.width))
        pageHeightTwips = max(1, twips(layout.paperSize.height))
        leftTwips = min(max(0, twips(layout.contentRect.minX)), pageWidthTwips - 1)
        topTwips = min(max(0, twips(layout.contentRect.minY)), pageHeightTwips - 1)
        let width = min(max(1, twips(layout.contentRect.width)), pageWidthTwips - leftTwips)
        let height = min(max(1, twips(layout.contentRect.height)), pageHeightTwips - topTwips)
        rightTwips = pageWidthTwips - leftTwips - width
        bottomTwips = pageHeightTwips - topTwips - height
    }

    var pictureWidthTwips: Int { pageWidthTwips - leftTwips - rightTwips }
    var pictureHeightTwips: Int { pageHeightTwips - topTwips - bottomTwips }
    var pictureWidthEMU: Int { pictureWidthTwips * Self.emusPerTwip }
    var pictureHeightEMU: Int { pictureHeightTwips * Self.emusPerTwip }
    var isLandscape: Bool { pageWidthTwips > pageHeightTwips }

    /// How many points the picture is drawn at for each point of the
    /// PaperNest page — 1 at the page's own size, less on Letter or A4 or
    /// when a large page was shrunk to Word's limit. The picture's pixels
    /// follow it, so a page drawn smaller is not rendered at full size.
    func pictureScale(for pageSize: CGSize) -> CGFloat {
        guard pageSize.width > 0 else { return 1 }
        return CGFloat(pictureWidthTwips) / 20 / pageSize.width
    }

    /// `w:sectPr`: this section's page size and margins. No header or
    /// footer distance either, so nothing but the picture claims the page.
    var properties: String {
        let orientation = isLandscape ? " w:orient=\"landscape\"" : ""
        return "<w:sectPr><w:pgSz w:w=\"\(pageWidthTwips)\" w:h=\"\(pageHeightTwips)\"\(orientation)/>"
            + "<w:pgMar w:top=\"\(topTwips)\" w:right=\"\(rightTwips)\" w:bottom=\"\(bottomTwips)\" "
            + "w:left=\"\(leftTwips)\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"
    }
}

extension Exporter {
    /// Writes `pages` as a Word file holding one picture per page: the
    /// brief's "appearance-preserving page images embedded in DOCX".
    ///
    /// Each page is drawn the way a JPEG export draws it — onto white, with
    /// its ink, marks and placed pictures, and the source's annotations as
    /// its author meant them for paper — and placed alone on a Word page of
    /// its own size (or fitted on Letter or A4). So a document of portrait
    /// and landscape pages stays that, and a notebook nobody has recognized
    /// exports as it looks. The cost is the point of the other layout: the
    /// words are pictures here, and Word cannot edit or search them.
    ///
    /// **One section per page, the picture inline.** Each page's paragraph
    /// ends its own section, so the next page starts on a fresh Word page
    /// sized for it, with no page-break paragraph that would leave a blank
    /// page behind a full-page picture. The picture is inline rather than
    /// floating because a floating picture placed against the page was
    /// rendered out of order and on top of its neighbours by the system's
    /// own Word reader (Quick Look, measured), while an inline one kept
    /// every page in order at its size.
    ///
    /// Pages are rendered and added to the archive one at a time, so memory
    /// holds one page's picture, not the document's.
    func writeDocxPageImages(_ pages: [Page], to url: URL, options: ExportOptions,
                             progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        guard !pages.isEmpty else { throw ExportError.noPages }
        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        let zip = try ZipWriter(url: url)
        try zip.addFile(named: "[Content_Types].xml", data: Data(Self.docxPageImagesContentTypes.utf8))
        try zip.addFile(named: "_rels/.rels", data: Data(Self.docxPackageRelationships.utf8))

        var sections: [DocxPageSection] = []
        sections.reserveCapacity(pages.count)
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let pageSize = page.geometry.pageSize
            let section = DocxPageSection(pageSize: pageSize, paper: options.paperSize)
            let pixelsPerPoint = CGFloat(options.imageDPI) / 72 * section.pictureScale(for: pageSize)
            let image = try await renderer.renderImage(page, pixelsPerPoint: pixelsPerPoint, annotations: .paper)
            guard let data = Self.encode(image, type: .jpeg, quality: options.jpegQuality, dpi: options.imageDPI) else {
                throw ExportError.writeFailed
            }
            try zip.addFile(named: "word/" + Self.docxMediaTarget(index), data: data)
            sections.append(section)
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }

        try zip.addFile(named: "word/_rels/document.xml.rels",
                        data: Data(Self.docxPageImageRelationships(count: sections.count).utf8))
        try zip.addFile(named: "word/document.xml", data: Data(Self.docxPageImagesDocument(sections).utf8))
        try zip.finish()
        return url
    }

    /// The picture of page `index` (zero-based), relative to `word/`.
    /// `.jpeg`, to match the one image type `[Content_Types].xml` declares:
    /// a part whose extension has no content type makes Word refuse the file.
    static func docxMediaTarget(_ index: Int) -> String { "media/page\(index + 1).jpeg" }

    static func docxImageRelationshipID(_ index: Int) -> String { "rIdPage\(index + 1)" }

    /// The body: one paragraph per page, holding nothing but its picture.
    ///
    /// The paragraph has no spacing and a 1-point paragraph mark, so its one
    /// line is the picture's height and hardly more. Every paragraph but the
    /// last carries its page's section properties; the last page's are the
    /// body's own, which is where WordprocessingML wants the final section.
    static func docxPageImagesDocument(_ sections: [DocxPageSection]) -> String {
        let tinyMark = "<w:rPr><w:sz w:val=\"2\"/><w:szCs w:val=\"2\"/></w:rPr>"
        let spacing = "<w:spacing w:before=\"0\" w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/>"
        var body = ""
        for (index, section) in sections.enumerated() {
            let ending = index < sections.count - 1 ? section.properties : ""
            // Schema order inside w:pPr: spacing, then rPr, then sectPr.
            body += "<w:p><w:pPr>\(spacing)\(tinyMark)\(ending)</w:pPr>"
                + "<w:r>\(tinyMark)<w:drawing>\(docxInlinePicture(index, section))</w:drawing></w:r></w:p>"
        }
        body += sections.last?.properties ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <w:body>\(body)</w:body></w:document>
        """
    }

    /// The whole `wp:inline` → `a:graphic` → `pic:pic` tree Word expects,
    /// in schema order. The names are the media file's, which is the same in
    /// every language; Word shows them in its Selection pane.
    static func docxInlinePicture(_ index: Int, _ section: DocxPageSection) -> String {
        let id = index + 1
        let name = (docxMediaTarget(index) as NSString).lastPathComponent
        let cx = section.pictureWidthEMU, cy = section.pictureHeightEMU
        return "<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>"
            + "<wp:docPr id=\"\(id)\" name=\"\(name)\"/>"
            + "<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>"
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(docxImageRelationshipID(index))\"/>"
            + "<a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>"
            + "</a:graphicData></a:graphic></wp:inline>"
    }

    /// `word/_rels/document.xml.rels`: one image relationship per page.
    static func docxPageImageRelationships(count: Int) -> String {
        let entries = (0..<count).map { index in
            "<Relationship Id=\"\(docxImageRelationshipID(index))\" "
                + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" "
                + "Target=\"\(docxMediaTarget(index))\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(entries)</Relationships>
        """
    }

    static let docxPageImagesContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Default Extension="jpeg" ContentType="image/jpeg"/>\
    <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    </Types>
    """
}

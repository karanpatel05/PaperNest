import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore

extension PageRenderer {
    /// The links `page`'s own PDF carries, where they still lead somewhere.
    ///
    /// A link inside a PDF points at a page of **that file**, and a PaperNest
    /// document is not that file: its pages may have been reordered, deleted
    /// or drawn from several PDFs. So an internal link is resolved through
    /// the pages the document shows now, by asset and source index — exactly
    /// as the outline is — and one whose page is gone is dropped: a link that
    /// goes nowhere is worse than no link. Web links are kept only when they
    /// are of a kind `PageLink.opens` allows.
    ///
    /// A link a crop hides is not returned; the reader cannot see it to tap.
    /// Image and template pages have none, which is an ordinary answer.
    public func links(on page: Page, in pages: [Page]) async throws -> [PageLink] {
        guard case .pdfPage(let assetID, let index) = page.content,
              let data = try await sourcePDFData(for: page),
              let document = PDFDocument(data: data), let pdfPage = document.page(at: index) else { return [] }
        // Where each page of this file ended up. The first wins if one was
        // duplicated, as it does for the outline.
        var landing: [Int: PageID] = [:]
        for candidate in pages {
            if case .pdfPage(let asset, let sourceIndex) = candidate.content, asset == assetID,
               landing[sourceIndex] == nil {
                landing[sourceIndex] = candidate.id
            }
        }
        let box = pdfPage.bounds(for: .cropBox)
        let upright = PageGeometry.uprightPDFSize(box: box, rotationDegrees: pdfPage.rotation)
        guard upright.width > 0, upright.height > 0 else { return [] }
        let toUnit = PageGeometry.pdfToSource(box: box, rotationDegrees: pdfPage.rotation)
            .concatenating(CGAffineTransform(scaleX: 1 / upright.width, y: 1 / upright.height))
        let crop = page.transform.crop

        // Under the app's PDFKit lock: listing a page's annotations builds
        // every one of them, form fields included, and that is the work that
        // must not run on several threads at once (`PDFKitAnnotationLock`).
        return PDFKitAnnotationLock.run { pdfPage.annotations.compactMap { annotation in
            guard annotation.type == "Link" else { return nil }
            let target: PageLink.Target
            if let url = annotation.url ?? (annotation.action as? PDFActionURL)?.url {
                guard PageLink.opens(url) else { return nil }
                target = .url(url)
            } else if let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination,
                      let destinationPage = destination.page,
                      let pageID = landing[document.index(for: destinationPage)] {
                target = .page(pageID)
            } else {
                return nil
            }
            let unit = annotation.bounds.applying(toUnit)
            guard unit.width > 0, unit.height > 0,
                  unit.midX >= crop.x, unit.midX <= crop.x + crop.width,
                  unit.midY >= crop.y, unit.midY <= crop.y + crop.height else { return nil }
            return PageLink(box: .exact(x: unit.minX, y: unit.minY, width: unit.width, height: unit.height),
                            target: target)
        } }
    }
}

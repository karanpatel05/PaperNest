import CoreGraphics
import Testing
@testable import PaperNestCore

@Suite struct PageGeometryTests {
    let source = CGSize(width: 600, height: 800)

    private func assertClose(_ a: CGPoint, _ b: CGPoint, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001, "\(a) != \(b)", sourceLocation: sourceLocation)
    }

    @Test func identityKeepsCoordinates() {
        let g = PageGeometry(sourceSize: source)
        #expect(g.pageSize == source)
        assertClose(CGPoint(x: 10, y: 20).applying(g.sourceToPage), CGPoint(x: 10, y: 20))
    }

    /// The source's top-left corner must land where a viewer expects after
    /// each clockwise rotation; this is what keeps pages upright on export.
    @Test(arguments: [
        (QuarterTurns.none, CGPoint(x: 0, y: 0), CGSize(width: 600, height: 800)),
        (QuarterTurns.clockwise90, CGPoint(x: 800, y: 0), CGSize(width: 800, height: 600)),
        (QuarterTurns.half, CGPoint(x: 600, y: 800), CGSize(width: 600, height: 800)),
        (QuarterTurns.clockwise270, CGPoint(x: 0, y: 600), CGSize(width: 800, height: 600)),
    ])
    func rotationMovesTopLeftCorner(rotation: QuarterTurns, expectedCorner: CGPoint, expectedSize: CGSize) {
        let g = PageGeometry(sourceSize: source, rotation: rotation)
        #expect(g.pageSize == expectedSize)
        assertClose(CGPoint.zero.applying(g.sourceToPage), expectedCorner)
    }

    @Test func everySourceCornerStaysOnThePage() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 600, y: 0), CGPoint(x: 0, y: 800), CGPoint(x: 600, y: 800)]
        for rotation in QuarterTurns.allCases {
            let g = PageGeometry(sourceSize: source, rotation: rotation)
            let mapped = corners.map { $0.applying(g.sourceToPage) }
            for p in mapped {
                #expect(p.x >= -0.0001 && p.x <= g.pageSize.width + 0.0001)
                #expect(p.y >= -0.0001 && p.y <= g.pageSize.height + 0.0001)
            }
            #expect(Set(mapped.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }).count == 4)
        }
    }

    @Test func fourClockwiseTurnsReturnToStart() {
        var r = QuarterTurns.none
        for _ in 0..<4 { r = r.rotatedClockwise() }
        #expect(r == .none)
        #expect(QuarterTurns.none.rotatedCounterclockwise() == .clockwise270)
    }

    @Test func cropThenRotateMapsCropCornersToPageCorners() {
        let crop = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25) // 300x200 at (150, 400)
        let g = PageGeometry(sourceSize: source, crop: crop, rotation: .clockwise90)
        #expect(g.pageSize == CGSize(width: 200, height: 300))
        // Crop's top-left goes to the page's top-right under a 90° turn.
        assertClose(CGPoint(x: 150, y: 400).applying(g.sourceToPage), CGPoint(x: 200, y: 0))
        assertClose(CGPoint(x: 450, y: 600).applying(g.sourceToPage), CGPoint(x: 0, y: 300))
    }

    @Test func pageToSourceInvertsSourceToPage() {
        let g = PageGeometry(sourceSize: source, crop: NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.7), rotation: .clockwise270)
        let p = CGPoint(x: 123.4, y: 456.7)
        assertClose(p.applying(g.sourceToPage).applying(g.pageToSource), p)
    }

    @Test func normalizedOCRBoxFollowsRotation() {
        // A box in the source's top strip ends up on the right edge after 90°.
        let g = PageGeometry(sourceSize: source, rotation: .clockwise90)
        let r = g.pageRect(forNormalizedSourceRect: NormalizedRect(x: 0, y: 0, width: 1, height: 0.1))
        #expect(abs(r.maxX - 800) < 0.001)
        #expect(abs(r.width - 80) < 0.001)
        #expect(abs(r.height - 600) < 0.001)
    }

    @Test(arguments: [0, 90, 180, 270, -90, 450])
    func pdfBoxMapsOntoUprightSource(rotation: Int) {
        let box = CGRect(x: 10, y: 20, width: 612, height: 792)
        let upright = PageGeometry.uprightPDFSize(box: box, rotationDegrees: rotation)
        let t = PageGeometry.pdfToSource(box: box, rotationDegrees: rotation)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        let mapped = corners.map { $0.applying(t) }
        #expect(abs(mapped.map(\.x).min()!) < 0.001 && abs(mapped.map(\.y).min()!) < 0.001)
        #expect(abs(mapped.map(\.x).max()! - upright.width) < 0.001)
        #expect(abs(mapped.map(\.y).max()! - upright.height) < 0.001)
        // With no /Rotate, the PDF's top-left (minX, maxY in y-up) is the source origin.
        if rotation == 0 {
            assertClose(CGPoint(x: box.minX, y: box.maxY).applying(t), .zero)
        }
    }

    @Test func pdfRotate90PutsPDFTopLeftAtSourceTopRight() {
        let box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let t = PageGeometry.pdfToSource(box: box, rotationDegrees: 90)
        assertClose(CGPoint(x: 0, y: 792).applying(t), CGPoint(x: 792, y: 0))
    }

    @Test func imageFlipKeepsTheRectangleAndSwapsItsTopAndBottom() {
        let r = CGRect(x: 10, y: 100, width: 50, height: 40)
        let t = PageGeometry.yUpToYDown(in: r)
        assertClose(CGPoint(x: 10, y: 100).applying(t), CGPoint(x: 10, y: 140))
        assertClose(CGPoint(x: 60, y: 140).applying(t), CGPoint(x: 60, y: 100))
        #expect(r.applying(t) == r)
    }

    @Test func normalizedRectClampsToValidCrop() {
        let r = NormalizedRect(x: -1, y: 2, width: 5, height: 0)
        #expect(r.x == 0)
        #expect(r.y + r.height <= 1.000001)
        #expect(r.width == 1)
        #expect(r.height >= NormalizedRect.minimumSide)
    }
}

@Suite struct PaperLayoutTests {
    @Test func originalKeepsPageSize() {
        let layout = PaperLayout(pageSize: CGSize(width: 300, height: 500), paper: .original)
        #expect(layout.paperSize == CGSize(width: 300, height: 500))
        #expect(layout.contentRect == CGRect(x: 0, y: 0, width: 300, height: 500))
    }

    @Test(arguments: [PaperSize.usLetter, .a4])
    func contentIsNeverCroppedAndKeepsAspectRatio(paper: PaperSize) {
        for page in [CGSize(width: 200, height: 2000), CGSize(width: 2000, height: 300), CGSize(width: 612, height: 792), CGSize(width: 10, height: 10)] {
            let layout = PaperLayout(pageSize: page, paper: paper)
            let paperRect = CGRect(origin: .zero, size: layout.paperSize)
            #expect(paperRect.insetBy(dx: -0.001, dy: -0.001).contains(layout.contentRect))
            let aspect = page.width / page.height
            #expect(abs(layout.contentRect.width / layout.contentRect.height - aspect) < 0.001)
        }
    }

    @Test func landscapePagesGetLandscapePaper() {
        let layout = PaperLayout(pageSize: CGSize(width: 1000, height: 500), paper: .usLetter)
        #expect(layout.paperSize == CGSize(width: 792, height: 612))
    }

    @Test func pageToPaperMapsPageCornersToContentRect() {
        let page = CGSize(width: 400, height: 800)
        let layout = PaperLayout(pageSize: page, paper: .a4, margin: 18)
        let t = layout.pageToPaper(pageSize: page)
        let br = CGPoint(x: 400, y: 800).applying(t)
        #expect(abs(br.x - layout.contentRect.maxX) < 0.001 && abs(br.y - layout.contentRect.maxY) < 0.001)
    }
}

@Suite struct ImageResolutionPolicyTests {
    @Test func trustedDPIIsHonored() {
        let size = ImageResolutionPolicy.pointSize(pixelSize: CGSize(width: 2550, height: 3300), dpi: CGSize(width: 300, height: 300))
        #expect(abs(size.width - 612) < 0.01 && abs(size.height - 792) < 0.01)
    }

    @Test func cameraImagesWithoutDPIBecomeDocumentSized() {
        let size = ImageResolutionPolicy.pointSize(pixelSize: CGSize(width: 3024, height: 4032), dpi: CGSize(width: 72, height: 72))
        #expect(abs(size.height - 792) < 0.01)
        #expect(abs(size.width - 594) < 0.01)
    }
}

/// The crop editor shows the page rotated but uncropped; these mappings
/// convert between that view and the stored source-space crop.
@Suite struct CropMappingTests {
    let source = CGSize(width: 600, height: 800)

    @Test(arguments: QuarterTurns.allCases)
    func cropRoundTripsThroughTheEditorSpace(rotation: QuarterTurns) {
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        let g = PageGeometry(sourceSize: source, crop: crop, rotation: rotation)
        let editorRect = g.cropRectInUncroppedPage
        let back = g.crop(fromUncroppedPageRect: editorRect)
        #expect(abs(back.x - crop.x) < 1e-9 && abs(back.y - crop.y) < 1e-9)
        #expect(abs(back.width - crop.width) < 1e-9 && abs(back.height - crop.height) < 1e-9)
        // The editor rectangle has the cropped page's (rotated) size.
        #expect(abs(editorRect.width - g.pageSize.width) < 1e-9 && abs(editorRect.height - g.pageSize.height) < 1e-9)
    }

    @Test func topLeftQuarterOfTheSourceIsTopRightAfterAClockwiseTurn() {
        let g = PageGeometry(sourceSize: source, crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5), rotation: .clockwise90)
        // Uncropped rotated page is 800×600; the source's top-left quarter
        // (300×400) sits in its top-right corner as 400×300.
        let r = g.cropRectInUncroppedPage
        #expect(abs(r.minX - 400) < 1e-9 && abs(r.minY - 0) < 1e-9)
        #expect(abs(r.width - 400) < 1e-9 && abs(r.height - 300) < 1e-9)
    }

    @Test func aRectangleDrawnOnTheRotatedPageBecomesTheMatchingSourceCrop() {
        // Drawing the bottom half of a page shown upside down selects the
        // top half of the source.
        let g = PageGeometry(sourceSize: source, rotation: .half)
        let crop = g.crop(fromUncroppedPageRect: CGRect(x: 0, y: 400, width: 600, height: 400))
        #expect(abs(crop.x) < 1e-9 && abs(crop.y) < 1e-9)
        #expect(abs(crop.width - 1) < 1e-9 && abs(crop.height - 0.5) < 1e-9)
    }

    @Test func fullCropMapsToTheWholeRotatedPage() {
        for rotation in QuarterTurns.allCases {
            let g = PageGeometry(sourceSize: source, rotation: rotation)
            #expect(g.cropRectInUncroppedPage.size == g.uncropped.pageSize)
            #expect(g.crop(fromUncroppedPageRect: CGRect(origin: .zero, size: g.uncropped.pageSize)).isApproximately(.full))
        }
    }

    @Test func approximateEqualityToleratesRoundingOnly() {
        #expect(NormalizedRect(x: 1e-12, y: 0, width: 1 - 1e-12, height: 1).isApproximately(.full))
        #expect(!NormalizedRect(x: 0.01, y: 0, width: 0.99, height: 1).isApproximately(.full))
    }
}

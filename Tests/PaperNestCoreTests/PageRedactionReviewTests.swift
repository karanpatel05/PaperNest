import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Turning a box drawn on the page into a redaction area, and finding the
/// marks that would still show over it.
@Suite struct PageRedactionReviewTests {
    let size = CGSize(width: 600, height: 800)

    // MARK: - From the page as seen to the source

    /// Every rotation, with a crop: a box drawn on the page comes back to the
    /// same place on the page after the round trip through source space.
    @Test(arguments: [QuarterTurns.none, .clockwise90, .half, .clockwise270])
    func aBoxDrawnOnThePageRoundTrips(_ rotation: QuarterTurns) {
        let geometry = PageGeometry(sourceSize: size, crop: NormalizedRect(x: 0.1, y: 0.05, width: 0.8, height: 0.7),
                                    rotation: rotation)
        let page = geometry.pageSize
        let drawn = CGRect(x: page.width * 0.2, y: page.height * 0.3, width: page.width * 0.4, height: page.height * 0.2)

        let source = geometry.normalizedSourceRect(forPageRect: drawn)
        let back = geometry.pageRect(forNormalizedSourceRect: source)

        #expect(abs(back.minX - drawn.minX) < 0.001 && abs(back.minY - drawn.minY) < 0.001, "\(rotation): \(back)")
        #expect(abs(back.width - drawn.width) < 0.001 && abs(back.height - drawn.height) < 0.001, "\(rotation): \(back)")
    }

    /// A box dragged from its bottom-right corner up to its top-left is the
    /// same box.
    @Test func aBoxDrawnBackwardsIsTheSameBox() {
        let geometry = PageGeometry(sourceSize: size)
        let forwards = geometry.normalizedSourceRect(forPageRect: CGRect(x: 60, y: 80, width: 120, height: 40))
        let backwards = geometry.normalizedSourceRect(forPageRect: CGRect(x: 180, y: 120, width: -120, height: -40))
        #expect(forwards == backwards)
    }

    /// Too small to be a box, it grows to the smallest one; never smaller
    /// than what was drawn, so a tiny redaction still covers its mark.
    @Test func aTinyBoxGrowsAndNeverShrinks() {
        let geometry = PageGeometry(sourceSize: size)
        let tiny = geometry.normalizedSourceRect(forPageRect: CGRect(x: 300, y: 400, width: 2, height: 1))
        #expect(tiny.width >= NormalizedRect.minimumSide && tiny.height >= NormalizedRect.minimumSide)
        #expect(tiny.x <= 300.0 / 600 && tiny.y <= 400.0 / 800)
    }

    /// Drawn hard against the right and bottom edges, the box still reaches them.
    @Test func aBoxAtTheEdgeStillReachesIt() {
        let geometry = PageGeometry(sourceSize: size)
        let corner = geometry.normalizedSourceRect(forPageRect: CGRect(x: 594, y: 795, width: 30, height: 30))
        #expect(abs(corner.x + corner.width - 1) < 1e-9)
        #expect(abs(corner.y + corner.height - 1) < 1e-9)
        #expect(corner.x <= 594.0 / 600 && corner.y <= 795.0 / 800)
    }

    // MARK: - Marks over the areas

    private func object(_ payload: PageObject.Payload) -> PageObject {
        PageObject(pageID: PageID(rawValue: "p"), zKey: "m", payload: payload, modifiedAt: Date())
    }

    @Test func aMarksBoundsIncludeItsInkWidth() throws {
        let stroke = InkStroke(tool: .pen, color: .black, width: 10,
                               points: [InkPoint(x: 100, y: 100), InkPoint(x: 200, y: 100)])
        let bounds = try #require(object(.ink(stroke)).drawnSourceBounds)
        #expect(bounds.minY < 100 && bounds.maxY > 100, "a horizontal line still has height")
        #expect(bounds.minX < 100 && bounds.maxX > 200)
        #expect(object(.comment("Private")).drawnSourceBounds == nil, "a comment is never drawn")
    }

    @Test func onlyMarksOverAnAreaAreNamedAndCommentsNever() {
        let over = object(.text(TextBox(frame: CGRect(x: 60, y: 90, width: 200, height: 40), text: "Account 4471")))
        let beside = object(.text(TextBox(frame: CGRect(x: 60, y: 600, width: 200, height: 40), text: "Thanks")))
        let picture = object(.image(PlacedImage(assetID: AssetID(sha256: String(repeating: "a", count: 64)),
                                                frame: CGRect(x: 250, y: 100, width: 100, height: 100))))
        let comment = object(.comment("Shredded the original"))
        // An area across the top: 0.05…0.95 wide, 0.1…0.2 down (80…160 points).
        let area = NormalizedRect(x: 0.05, y: 0.1, width: 0.9, height: 0.1)

        let found = PageRedactionReview.marksOverlapping([area], in: [over, beside, picture, comment], sourceSize: size)

        #expect(found.map(\.id) == [over.id, picture.id])
        #expect(PageRedactionReview.comments(in: [over, comment]).map(\.id) == [comment.id])
    }

    @Test func aMarkOnlyGrazingAnAreaStillCounts() {
        // The box ends at y = 81; the area starts at 80.
        let grazing = object(.text(TextBox(frame: CGRect(x: 10, y: 41, width: 100, height: 40), text: "Name")))
        let area = NormalizedRect(x: 0, y: 0.1, width: 1, height: 0.1)
        #expect(PageRedactionReview.marksOverlapping([area], in: [grazing], sourceSize: size).count == 1)
    }
}

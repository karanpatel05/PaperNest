import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Where a newly placed image goes, and how its shape is read.
@Suite struct PlacedImageFrameTests {
    private func page(_ size: CGSize = CGSize(width: 612, height: 792)) -> Page {
        Page(id: PageID(rawValue: "page"), itemID: ItemID(rawValue: "item"), sortKey: "a",
             sourceSize: size, content: .template(.blank),
             createdAt: Date(), modifiedAt: Date())
    }

    /// A photo must not be squashed to fit a box.
    @Test func theImageKeepsItsOwnProportions() {
        let wide = DocumentModel.imageFrame(pixels: CGSize(width: 2000, height: 1000), on: page())
        let tall = DocumentModel.imageFrame(pixels: CGSize(width: 1000, height: 2000), on: page())

        #expect(abs(wide.width / wide.height - 2) < 0.01, "a 2:1 image came out \(wide.size)")
        #expect(abs(tall.width / tall.height - 0.5) < 0.01, "a 1:2 image came out \(tall.size)")
    }

    /// And it has to start somewhere sensible on the page rather than over the
    /// edge, since nothing places it by hand.
    @Test func theImageStartsOnThePage() {
        let frame = DocumentModel.imageFrame(pixels: CGSize(width: 4000, height: 3000), on: page())

        #expect(frame.minX >= 0 && frame.minY >= 0)
        #expect(frame.maxX <= 612.5 && frame.maxY <= 792.5)
        // Comfortably within the page, not filling it.
        #expect(frame.width <= 612 * 0.5 + 0.5)
        #expect(frame.height <= 792 * 0.4 + 0.5)
    }

    /// An image whose size cannot be read still gets a usable frame rather
    /// than a zero-sized one the renderer would skip.
    @Test func anUnreadableSizeStillGetsAFrame() {
        let frame = DocumentModel.imageFrame(pixels: nil, on: page())

        #expect(frame.width > 1 && frame.height > 1)
    }

    @Test func theShownSizeIsReadFromTheBytes() throws {
        let data = SyntheticDocuments.image(width: 300, height: 150, type: .png)

        let size = try #require(DocumentModel.pixelSize(of: data))

        #expect(size == CGSize(width: 300, height: 150))
    }

    /// A photo stored sideways reports the size it is *shown* at, because that
    /// is the shape the frame has to match — the renderer decodes it upright.
    @Test func aSidewaysPhotoReportsTheSizeItIsShownAt() throws {
        let data = SyntheticDocuments.image(width: 300, height: 150, type: .jpeg, exifOrientation: 6)

        let size = try #require(DocumentModel.pixelSize(of: data))

        #expect(size == CGSize(width: 300, height: 150), "the quarter turn was not accounted for")
    }

    @Test func bytesThatAreNotAnImageHaveNoSize() {
        #expect(DocumentModel.pixelSize(of: Data("not a picture".utf8)) == nil)
    }
}

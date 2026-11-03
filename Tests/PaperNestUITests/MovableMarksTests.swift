import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Picking up a text box or a placed image and moving it.
@Suite struct MovableMarksTests {
    private func textBox(at frame: CGRect) -> PageObject {
        PageObject(pageID: PageID(rawValue: "page"), zKey: "m",
                   payload: .text(TextBox(frame: frame, text: "Paid in full", fontSize: 20,
                                          color: .init(red: 1, green: 0, blue: 0, alpha: 1),
                                          alignment: .center)),
                   modifiedAt: Date(timeIntervalSince1970: 0))
    }

    /// Moving changes where it is and nothing else about it.
    @Test func movingATextBoxChangesOnlyItsFrame() throws {
        let original = textBox(at: CGRect(x: 10, y: 10, width: 200, height: 80))

        let moved = try #require(DocumentModel.moved(original, to: CGRect(x: 90, y: 300, width: 200, height: 80)))

        guard case .text(let box) = moved.payload else {
            Issue.record("the moved object is no longer a text box")
            return
        }
        #expect(box.frame == CGRect(x: 90, y: 300, width: 200, height: 80))
        #expect(box.text == "Paid in full")
        #expect(box.fontSize == 20)
        #expect(box.alignment == .center)
        #expect(box.color.red == 1)
        #expect(moved.id == original.id && moved.zKey == original.zKey)
        #expect(moved.modifiedAt > original.modifiedAt, "a move is an edit and should be dated")
    }

    @Test func aPlacedImageMovesTheSameWay() throws {
        let original = PageObject(
            pageID: PageID(rawValue: "page"), zKey: "m",
            payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "a", count: 64)),
                                        frame: CGRect(x: 0, y: 0, width: 100, height: 100))),
            modifiedAt: Date(timeIntervalSince1970: 0))

        let moved = try #require(DocumentModel.moved(original, to: CGRect(x: 50, y: 60, width: 100, height: 100)))

        guard case .image(let image) = moved.payload else {
            Issue.record("the moved object is no longer an image")
            return
        }
        #expect(image.frame.origin == CGPoint(x: 50, y: 60))
    }

    /// Ink is moved by the drawing canvas's lasso, and a comment has no frame.
    /// Both must come back nil rather than being silently mangled.
    @Test func inkAndCommentsAreNotMovedThisWay() {
        let ink = PageObject(pageID: PageID(rawValue: "page"), zKey: "m",
                             payload: .ink(InkStroke(tool: .pen, color: .black, width: 2,
                                                     points: [InkPoint(x: 0, y: 0)])),
                             modifiedAt: Date())
        let comment = PageObject(pageID: PageID(rawValue: "page"), zKey: "n",
                                 payload: .comment("private"), modifiedAt: Date())

        #expect(DocumentModel.moved(ink, to: CGRect(x: 1, y: 1, width: 2, height: 2)) == nil)
        #expect(DocumentModel.moved(comment, to: CGRect(x: 1, y: 1, width: 2, height: 2)) == nil)
    }

    /// Hanging over an edge is allowed — drawing clips it — but the origin
    /// stays on the page, so a mark dragged too far can always be found again.
    @Test func aMarkDraggedOffThePageKeepsItsOriginOnIt() {
        let page = CGSize(width: 612, height: 792)

        let farRight = DocumentModel.clamped(CGRect(x: 5000, y: 20, width: 100, height: 40), within: page)
        let negative = DocumentModel.clamped(CGRect(x: -400, y: -900, width: 100, height: 40), within: page)
        let hangingOver = DocumentModel.clamped(CGRect(x: 560, y: 700, width: 300, height: 200), within: page)

        #expect(farRight.minX <= page.width && farRight.minX >= 0)
        #expect(negative.origin == .zero)
        // Still allowed to hang off the right and bottom edges.
        #expect(hangingOver.origin == CGPoint(x: 560, y: 700))
        #expect(hangingOver.maxX > page.width)
    }

    @Test func onlyMarksWithAFrameOfferOne() {
        let box = textBox(at: CGRect(x: 3, y: 4, width: 5, height: 6))
        let comment = PageObject(pageID: PageID(rawValue: "page"), zKey: "n",
                                 payload: .comment("private"), modifiedAt: Date())

        #expect(MovableMarksOverlay.frame(of: box) == CGRect(x: 3, y: 4, width: 5, height: 6))
        #expect(MovableMarksOverlay.frame(of: comment) == nil)
    }
}

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

    // MARK: - Resizing by a corner

    private let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let minimum: Double = 16

    /// The corner opposite the one being dragged stays exactly where it is.
    /// That is the whole contract of a corner handle, and getting it wrong
    /// makes a box appear to run away from the pointer.
    @Test func theOppositeCornerStaysPutWhicheverIsDragged() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 80)
        let pull = CGPoint(x: 40, y: 30)

        let anchors: [(MarkCorner, CGPoint)] = [
            (.bottomTrailing, CGPoint(x: frame.minX, y: frame.minY)),
            (.topLeading, CGPoint(x: frame.maxX, y: frame.maxY)),
            (.topTrailing, CGPoint(x: frame.minX, y: frame.maxY)),
            (.bottomLeading, CGPoint(x: frame.maxX, y: frame.minY)),
        ]
        for (corner, anchor) in anchors {
            let resized = MovableMarksOverlay.resized(frame, corner: corner, by: pull,
                                                      minimum: minimum, aspect: nil, within: page)
            let corners = [CGPoint(x: resized.minX, y: resized.minY), CGPoint(x: resized.maxX, y: resized.minY),
                           CGPoint(x: resized.minX, y: resized.maxY), CGPoint(x: resized.maxX, y: resized.maxY)]
            #expect(corners.contains { abs($0.x - anchor.x) < 0.001 && abs($0.y - anchor.y) < 0.001 },
                    "\(corner) moved the corner that should have stayed")
        }
    }

    @Test func draggingTheBottomRightCornerGrowsTheBox() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 80)

        let resized = MovableMarksOverlay.resized(frame, corner: .bottomTrailing,
                                                  by: CGPoint(x: 50, y: 20),
                                                  minimum: minimum, aspect: nil, within: page)

        #expect(resized == CGRect(x: 100, y: 100, width: 250, height: 100))
    }

    @Test func draggingTheTopLeftCornerMovesTheOrigin() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 80)

        let resized = MovableMarksOverlay.resized(frame, corner: .topLeading,
                                                  by: CGPoint(x: 30, y: 20),
                                                  minimum: minimum, aspect: nil, within: page)

        #expect(resized == CGRect(x: 130, y: 120, width: 170, height: 60))
    }

    /// A mark dragged past itself must stop, not invert: a negative width
    /// draws nothing and leaves something on the page nobody can grab.
    @Test func aMarkCannotBeShrunkPastNothing() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 80)

        for corner in MarkCorner.allCases {
            let crushed = MovableMarksOverlay.resized(frame, corner: corner,
                                                      by: CGPoint(x: -900, y: -900),
                                                      minimum: minimum, aspect: nil, within: page)
            #expect(crushed.width >= minimum, "\(corner) width")
            #expect(crushed.height >= minimum, "\(corner) height")
            let stretched = MovableMarksOverlay.resized(frame, corner: corner,
                                                        by: CGPoint(x: 900, y: 900),
                                                        minimum: minimum, aspect: nil, within: page)
            #expect(stretched.width >= minimum, "\(corner) width stretched the other way")
            #expect(stretched.height >= minimum, "\(corner) height stretched the other way")
        }
    }

    /// A photo squashed out of shape is the thing the placing code went to
    /// trouble to avoid, so a resize must not undo it. An image keeps its
    /// proportions; a text box does not have any to keep.
    @Test func anImageKeepsItsProportions() throws {
        // 2:1, as `imageFrame` would have made it.
        let frame = CGRect(x: 50, y: 50, width: 200, height: 100)

        let resized = MovableMarksOverlay.resized(frame, corner: .bottomTrailing,
                                                  by: CGPoint(x: 100, y: 0),
                                                  minimum: minimum, aspect: 2, within: page)

        #expect(resized.width / resized.height == 2)
        // Dragged 100 wider, so the height follows to keep 2:1.
        #expect(resized.width == 300)
        #expect(resized.height == 150)
    }

    /// Dragging mostly downwards on a locked image grows it by the height,
    /// so the gesture follows the pointer rather than ignoring one axis.
    @Test func theAxisDraggedFurtherDrivesALockedResize() {
        let frame = CGRect(x: 50, y: 50, width: 200, height: 100)

        let byHeight = MovableMarksOverlay.resized(frame, corner: .bottomTrailing,
                                                   by: CGPoint(x: 2, y: 50),
                                                   minimum: minimum, aspect: 2, within: page)

        #expect(byHeight.height == 150)
        #expect(byHeight.width == 300)
    }

    /// The page is the limit, as it is for a move: a mark grown past the edge
    /// would have corners nobody can reach.
    @Test func aResizeStopsAtTheEdgeOfThePage() {
        let frame = CGRect(x: 500, y: 700, width: 80, height: 50)

        let resized = MovableMarksOverlay.resized(frame, corner: .bottomTrailing,
                                                  by: CGPoint(x: 900, y: 900),
                                                  minimum: minimum, aspect: nil, within: page)

        #expect(resized.maxX <= page.maxX)
        #expect(resized.maxY <= page.maxY)
        #expect(resized.minX == 500 && resized.minY == 700)
    }

    /// At the edge a locked image shrinks to fit rather than distorting: the
    /// easy mistake is to clamp one side and leave the other, which is
    /// exactly the squashing the lock exists to prevent.
    @Test func aLockedImageKeepsItsShapeEvenAtTheEdge() {
        let frame = CGRect(x: 400, y: 600, width: 200, height: 100)

        let resized = MovableMarksOverlay.resized(frame, corner: .bottomTrailing,
                                                  by: CGPoint(x: 900, y: 900),
                                                  minimum: minimum, aspect: 2, within: page)

        #expect(abs(resized.width / resized.height - 2) < 0.001, "the image was squashed to fit")
        #expect(resized.maxX <= page.maxX + 0.001)
        #expect(resized.maxY <= page.maxY + 0.001)
    }

    /// Only a mark with a frame can be resized, and only an image locks its
    /// shape — a text box has no proportions worth keeping.
    @Test func onlyAnImageLocksItsProportions() {
        let box = textBox(at: CGRect(x: 0, y: 0, width: 200, height: 80))
        let image = PageObject(pageID: PageID(rawValue: "page"), zKey: "n",
                               payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "c", count: 64)),
                                                           frame: CGRect(x: 0, y: 0, width: 200, height: 50))),
                               modifiedAt: Date())
        let comment = PageObject(pageID: PageID(rawValue: "page"), zKey: "o",
                                 payload: .comment("private"), modifiedAt: Date())

        #expect(MovableMarksOverlay.aspect(of: box) == nil)
        #expect(MovableMarksOverlay.aspect(of: image) == 4)
        #expect(MovableMarksOverlay.aspect(of: comment) == nil)
    }

    // MARK: - Opening a mark with a second click

    /// Counted by hand rather than with a `TapGesture(count: 2)`, which
    /// cannot live beside the move gesture — it waits for a possible second
    /// click and swallows the single one that never becomes one, which broke
    /// selecting a mark at all.
    @Test func asecondClickOnTheSameMarkOpensIt() {
        let mark = PageObjectID(rawValue: "a")
        let first = MovableMarksOverlay.Click(id: mark, time: Date(timeIntervalSince1970: 100))
        let soon = MovableMarksOverlay.Click(
            id: mark, time: first.time.addingTimeInterval(MovableMarksOverlay.doubleClickInterval / 2))

        #expect(MovableMarksOverlay.opens(first, with: soon))
    }

    @Test func aSlowSecondClickIsJustAnotherClick() {
        let mark = PageObjectID(rawValue: "a")
        let first = MovableMarksOverlay.Click(id: mark, time: Date(timeIntervalSince1970: 100))
        let late = MovableMarksOverlay.Click(
            id: mark, time: first.time.addingTimeInterval(MovableMarksOverlay.doubleClickInterval + 0.1))

        #expect(!MovableMarksOverlay.opens(first, with: late))
    }

    /// One click on each of two marks is not a double click on either.
    @Test func clicksOnDifferentMarksNeverPairUp() {
        let first = MovableMarksOverlay.Click(id: PageObjectID(rawValue: "a"),
                                              time: Date(timeIntervalSince1970: 100))
        let other = MovableMarksOverlay.Click(id: PageObjectID(rawValue: "b"),
                                              time: first.time.addingTimeInterval(0.05))

        #expect(!MovableMarksOverlay.opens(first, with: other))
        #expect(!MovableMarksOverlay.opens(nil, with: other))
    }
}

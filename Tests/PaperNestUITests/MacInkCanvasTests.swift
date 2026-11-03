#if os(macOS)
import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// The Mac's own drawing canvas. What can go wrong here is the geometry: a
/// stroke drawn at one zoom must be stored in the page's own coordinates, or
/// it lands somewhere else the next time the page is shown.
@Suite struct MacInkCanvasTests {
    private let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)

    @Test func pointsAreStoredInSourceSpaceNotViewSpace() throws {
        // The page drawn at double size: a view point is half as far in source.
        let sourceToView = CGAffineTransform(scaleX: 2, y: 2)

        let stroke = try #require(MacInkCanvas.stroke(
            from: [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 400)],
            sourceToView: sourceToView, tool: .pen, color: black, width: 2))

        #expect(stroke.points.count == 2)
        #expect(abs(stroke.points[0].x - 50) < 0.001)
        #expect(abs(stroke.points[0].y - 100) < 0.001)
        #expect(abs(stroke.points[1].x - 150) < 0.001)
        #expect(abs(stroke.points[1].y - 200) < 0.001)
    }

    /// Zoom must not change where a stroke ends up. The same place on screen
    /// at two different zooms is the same place on the page.
    @Test func thePlaceOnThePageDoesNotDependOnTheZoom() throws {
        let atOne = try #require(MacInkCanvas.stroke(
            from: [CGPoint(x: 60, y: 90)], sourceToView: CGAffineTransform(scaleX: 1, y: 1),
            tool: .pen, color: black, width: 2))
        let atThree = try #require(MacInkCanvas.stroke(
            from: [CGPoint(x: 180, y: 270)], sourceToView: CGAffineTransform(scaleX: 3, y: 3),
            tool: .pen, color: black, width: 2))

        #expect(abs(atOne.points[0].x - atThree.points[0].x) < 0.001)
        #expect(abs(atOne.points[0].y - atThree.points[0].y) < 0.001)
    }

    /// A click without movement is a dot someone meant to make, not nothing.
    @Test func aSingleClickIsKept() throws {
        let stroke = try #require(MacInkCanvas.stroke(
            from: [CGPoint(x: 10, y: 10)], sourceToView: .identity,
            tool: .pen, color: black, width: 3))

        #expect(stroke.points.count == 1)
        #expect(stroke.width == 3)
    }

    @Test func nothingDrawnIsNoStroke() {
        #expect(MacInkCanvas.stroke(from: [], sourceToView: .identity,
                                    tool: .pen, color: black, width: 2) == nil)
    }

    /// The tool and colour are the ones chosen, and the highlighter's
    /// translucency is added when drawing rather than stored in the colour.
    @Test func theChosenToolAndColourAreWhatIsStored() throws {
        let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

        let stroke = try #require(MacInkCanvas.stroke(
            from: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)], sourceToView: .identity,
            tool: .highlighter, color: red, width: 4))

        #expect(stroke.tool == .highlighter)
        #expect(stroke.color.red == 1 && stroke.color.alpha == 1)
        #expect(stroke.width == 4)
    }

    // MARK: - Eraser

    private func inkObject(_ points: [(Double, Double)], width: Double = 2,
                           id: String = UUID().uuidString) -> PageObject {
        PageObject(id: PageObjectID(rawValue: id), pageID: PageID(rawValue: "page"), zKey: "m",
                   payload: .ink(InkStroke(tool: .pen, color: black, width: width,
                                           points: points.map { InkPoint(x: $0.0, y: $0.1) })),
                   modifiedAt: Date())
    }

    @Test func theEraserTakesTheStrokeItCrosses() {
        let crossed = inkObject([(100, 100), (200, 100)], id: "crossed")
        let elsewhere = inkObject([(100, 500), (200, 500)], id: "elsewhere")

        let hit = MacInkCanvas.strokesHit(by: [CGPoint(x: 150, y: 102)],
                                          in: [crossed, elsewhere], radius: 8)

        #expect(hit.map(\.id.rawValue) == ["crossed"])
    }

    @Test func aStrokeTheEraserMissesIsLeftAlone() {
        let stroke = inkObject([(100, 100), (200, 100)])

        let hit = MacInkCanvas.strokesHit(by: [CGPoint(x: 150, y: 400)], in: [stroke], radius: 8)

        #expect(hit.isEmpty)
    }

    /// A thick stroke is hit from further away, because its edge is further
    /// from its centre line than a thin one's.
    @Test func aThickStrokeIsReachedFromFurtherAway() {
        let thin = inkObject([(100, 100)], width: 1, id: "thin")
        let thick = inkObject([(100, 100)], width: 40, id: "thick")
        // Just outside the thin stroke's reach, inside the thick one's.
        let point = [CGPoint(x: 100, y: 125)]

        #expect(MacInkCanvas.strokesHit(by: point, in: [thin], radius: 8).isEmpty)
        #expect(MacInkCanvas.strokesHit(by: point, in: [thick], radius: 8).count == 1)
    }

    /// The eraser is for ink. A text box or a placed image sitting under it is
    /// not quietly deleted — those are moved and removed their own way.
    @Test func theEraserNeverTakesATextBoxOrAnImage() {
        let box = PageObject(pageID: PageID(rawValue: "page"), zKey: "m",
                             payload: .text(TextBox(frame: CGRect(x: 90, y: 90, width: 100, height: 40),
                                                    text: "Keep me", fontSize: 12)),
                             modifiedAt: Date())
        let image = PageObject(pageID: PageID(rawValue: "page"), zKey: "n",
                               payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "b", count: 64)),
                                                           frame: CGRect(x: 90, y: 90, width: 100, height: 40))),
                               modifiedAt: Date())

        let hit = MacInkCanvas.strokesHit(by: [CGPoint(x: 100, y: 100)], in: [box, image], radius: 8)

        #expect(hit.isEmpty)
    }

    @Test func anEraserThatTouchedNothingTakesNothing() {
        #expect(MacInkCanvas.strokesHit(by: [], in: [inkObject([(1, 1)])], radius: 8).isEmpty)
    }

    /// A fast eraser drag is sampled sparsely, so a dot can fall between two
    /// of its samples. It still has to be taken — this is the second of the
    /// two directions `strokesHit` checks, and without it a quick flick over a
    /// full stop would leave it behind.
    @Test func aFastFlickStillTakesADotBetweenItsSamples() {
        let dot = inkObject([(150, 100)], id: "dot")
        // Two samples 100 apart, neither near the dot, but the line between
        // them passes right over it.
        let flick = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)]

        #expect(MacInkCanvas.strokesHit(by: flick, in: [dot], radius: 8).count == 1)
    }

    // MARK: - The lasso

    /// A loop drawn around a stroke takes it and leaves the one outside.
    @Test func theLassoTakesTheStrokeItEncloses() {
        let inside = inkObject([(100, 100), (200, 100)], id: "inside")
        let outside = inkObject([(100, 500), (200, 500)], id: "outside")
        let loop = [CGPoint(x: 80, y: 80), CGPoint(x: 220, y: 80),
                    CGPoint(x: 220, y: 140), CGPoint(x: 80, y: 140)]

        let taken = MacInkCanvas.strokesEnclosed(by: loop, in: [inside, outside])

        #expect(taken.map(\.id.rawValue) == ["inside"])
    }

    /// Nicking the end of a long stroke must not take the whole thing. The
    /// rule is that the loop goes **around** a mark, which is what drawing a
    /// circle round handwriting means, and a looser rule would make a lasso
    /// that grabs the neighbouring word.
    @Test func aStrokeOnlyPartlyInsideTheLoopIsNotTaken() {
        let long = inkObject([(100, 100), (900, 100)])
        let loop = [CGPoint(x: 80, y: 80), CGPoint(x: 220, y: 80),
                    CGPoint(x: 220, y: 140), CGPoint(x: 80, y: 140)]

        #expect(MacInkCanvas.strokesEnclosed(by: loop, in: [long]).isEmpty)
    }

    /// The loop is closed from its last point back to its first, because a
    /// drag ends where the pointer stopped rather than where it started.
    /// Walking only consecutive pairs would lose that side, and with it every
    /// lasso nobody closed by hand — which is all of them.
    @Test func anOpenLoopIsClosedFromItsLastPointToItsFirst() {
        let stroke = inkObject([(200, 200)])
        // Three sides of a box, drawn anticlockwise from the top right and
        // stopped at the bottom right: the right-hand side, from (300, 300)
        // back to (300, 100), exists only because the loop is closed here.
        // Without it the stroke is outside, which is the regression this pins.
        let open = [CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 100),
                    CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 300)]

        #expect(MacInkCanvas.strokesEnclosed(by: open, in: [stroke]).count == 1)
    }

    /// A click, or a straight drag, encloses nothing at all.
    @Test func aLoopWithNoAreaTakesNothing() {
        let stroke = inkObject([(150, 110)])

        #expect(MacInkCanvas.strokesEnclosed(by: [CGPoint(x: 150, y: 110)], in: [stroke]).isEmpty)
        #expect(MacInkCanvas.strokesEnclosed(
            by: [CGPoint(x: 100, y: 110), CGPoint(x: 200, y: 110)], in: [stroke]).isEmpty)
    }

    /// The lasso is for handwriting. A text box or a placed image inside the
    /// loop is not picked up with it — those are moved their own way, with the
    /// markup canvas down.
    @Test func theLassoNeverTakesATextBoxOrAnImage() {
        let loop = [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0),
                    CGPoint(x: 400, y: 400), CGPoint(x: 0, y: 400)]

        #expect(MacInkCanvas.strokesEnclosed(by: loop, in: [Self.textBox, Self.placedImage]).isEmpty)
    }

    /// The dashed box round a selection has to cover the ink's width, not just
    /// the line through its middle, or a thick stroke sticks out of its own box.
    @Test func theSelectionBoxCoversTheWidthOfTheInk() throws {
        let stroke = inkObject([(100, 100), (200, 100)], width: 20)

        let bounds = try #require(MacInkCanvas.selectionBounds(of: [stroke]))

        #expect(bounds == CGRect(x: 90, y: 90, width: 120, height: 20))
    }

    @Test func nothingSelectedHasNoBox() {
        #expect(MacInkCanvas.selectionBounds(of: []) == nil)
        #expect(MacInkCanvas.selectionBounds(of: [Self.textBox]) == nil)
    }

    /// Moving handwriting changes where it is and nothing else about it:
    /// pressure, timing, tool, colour and width all survive, and it keeps its
    /// identity so undo treats it as the same mark moved rather than one
    /// deleted and another added.
    @Test func movingHandwritingChangesOnlyItsPlace() throws {
        let original = PageObject(pageID: PageID(rawValue: "page"), zKey: "m",
                                  payload: .ink(InkStroke(tool: .highlighter, color: black, width: 7,
                                                          points: [InkPoint(x: 10, y: 20, widthScale: 2, time: 0.5)])),
                                  modifiedAt: Date(timeIntervalSince1970: 0))

        let moved = try #require(DocumentModel.translated(original, by: CGPoint(x: 5, y: -3)))

        guard case .ink(let stroke) = moved.payload else { Issue.record("not ink any more"); return }
        #expect(moved.id == original.id)
        #expect(stroke.points.map(\.x) == [15])
        #expect(stroke.points.map(\.y) == [17])
        #expect(stroke.points.first?.widthScale == 2)
        #expect(stroke.points.first?.time == 0.5)
        #expect(stroke.tool == .highlighter)
        #expect(stroke.width == 7)
        #expect(stroke.color == black)
        #expect(moved.modifiedAt > original.modifiedAt)
    }

    /// A text box has a frame, not points; it moves through `moved(_:to:)`.
    @Test func translatingIsForInkOnly() {
        #expect(DocumentModel.translated(Self.textBox, by: CGPoint(x: 5, y: 5)) == nil)
        #expect(DocumentModel.translated(Self.placedImage, by: CGPoint(x: 5, y: 5)) == nil)
    }

    /// The same drag moves the ink the same distance **on the page** whatever
    /// the zoom, because the drag is in view points and the ink is in source
    /// ones.
    @Test func theSameDragMovesTheSameDistanceAtAnyZoom() {
        let drag = CGSize(width: 100, height: 50)

        #expect(DocumentModel.sourceDelta(of: drag, sourceToView: CGAffineTransform(scaleX: 2, y: 2))
                == CGPoint(x: 50, y: 25))
        #expect(DocumentModel.sourceDelta(of: drag, sourceToView: CGAffineTransform(scaleX: 0.5, y: 0.5))
                == CGPoint(x: 200, y: 100))
    }

    /// A rotated page is where a hand-rolled "divide by the scale" breaks: the
    /// drag has to go through the page's own transform rather than past it.
    /// Dragging right across a page turned a quarter turn moves the ink *up*
    /// the page in its own coordinates.
    @Test func aDragOnARotatedPageMovesTheInkTheWayItLooks() {
        let quarterTurn = CGAffineTransform(rotationAngle: .pi / 2)

        let delta = DocumentModel.sourceDelta(of: CGSize(width: 100, height: 0), sourceToView: quarterTurn)

        #expect(abs(delta.x) < 0.0001)
        #expect(abs(delta.y + 100) < 0.0001)
    }

    /// Handwriting dragged off the page could never be lassoed back, because
    /// the canvas only covers the page.
    @Test func aSelectionCannotBeDraggedOffThePage() {
        let bounds = CGRect(x: 10, y: 10, width: 100, height: 50)
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)

        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: 20, y: 30), within: page)
                == CGPoint(x: 20, y: 30))
        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: -500, y: -500), within: page)
                == CGPoint(x: -10, y: -10))
        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: 900, y: 0), within: page)
                == CGPoint(x: 490, y: 0))
    }

    /// On a **cropped** page the canvas covers only the crop, so handwriting
    /// dragged outside it lands where no lasso can ever enclose it again —
    /// the same trap as dragging it off the page, one rectangle in.
    @Test func aSelectionCannotBeDraggedUnderTheCrop() {
        let bounds = CGRect(x: 110, y: 110, width: 50, height: 20)
        // What the crop leaves visible, in source points.
        let visible = CGRect(x: 100, y: 100, width: 300, height: 400)

        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: -500, y: -500), within: visible)
                == CGPoint(x: -10, y: -10))
        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: 900, y: 900), within: visible)
                == CGPoint(x: 240, y: 370))
    }

    /// A selection wider than the page cannot satisfy both edges, and the
    /// answer is to let it move rather than to pin it.
    @Test func aSelectionBiggerThanThePageCanStillBeMoved() {
        let bounds = CGRect(x: -50, y: 0, width: 900, height: 50)

        #expect(DocumentModel.clampedTranslation(of: bounds, by: CGPoint(x: 30, y: 10),
                                                 within: CGRect(x: 0, y: 0, width: 600, height: 800))
                == CGPoint(x: 30, y: 10))
    }

    private static let textBox = PageObject(
        pageID: PageID(rawValue: "page"), zKey: "m",
        payload: .text(TextBox(frame: CGRect(x: 90, y: 90, width: 100, height: 40),
                               text: "Keep me", fontSize: 12)),
        modifiedAt: Date(timeIntervalSince1970: 0))

    private static let placedImage = PageObject(
        pageID: PageID(rawValue: "page"), zKey: "n",
        payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "b", count: 64)),
                                    frame: CGRect(x: 90, y: 90, width: 100, height: 40))),
        modifiedAt: Date(timeIntervalSince1970: 0))
}
#endif

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
}
#endif

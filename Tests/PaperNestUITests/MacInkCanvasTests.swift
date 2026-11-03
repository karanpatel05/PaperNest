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
}
#endif

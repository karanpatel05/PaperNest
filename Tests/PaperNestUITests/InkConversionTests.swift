import CoreGraphics
import PencilKit
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Pass 7: PencilKit strokes (view points) ↔ stored ink (source points).
@Suite struct InkConversionTests {
    /// A 400 × 300 source page turned clockwise and shown at 1.5×.
    let conversion: InkConversion = {
        let geometry = PageGeometry(sourceSize: CGSize(width: 400, height: 300), rotation: .clockwise90)
        return InkConversion(sourceToView: geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: 1.5, y: 1.5)))
    }()

    @Test func storedInkSurvivesARoundTripThroughPencilKit() throws {
        let ink = InkStroke(tool: .pen, color: RGBAColor(red: 0, green: 0.4, blue: 1), width: 4, points: [
            InkPoint(x: 50, y: 40, widthScale: 1), InkPoint(x: 120, y: 60, widthScale: 0.5), InkPoint(x: 200, y: 90, widthScale: 1),
        ])
        let stroke = conversion.pkStroke(from: ink, seed: 7)
        #expect(stroke.randomSeed == 7)
        #expect(stroke.ink.inkType == .pen)
        // Source (50, 40) on a clockwise page of height 300 sits at (260, 50) on the page, × 1.5 in the view.
        let first = try #require(stroke.path.first)
        #expect(abs(first.location.x - 390) < 0.01 && abs(first.location.y - 75) < 0.01)
        #expect(abs(first.size.width - 6) < 0.01, "4 source points at 1.5×")

        let back = try #require(conversion.inkStrokes(from: stroke).first)
        #expect(back.tool == .pen)
        #expect(abs(back.color.green - 0.4) < 0.01 && abs(back.color.blue - 1) < 0.01)
        #expect(abs(back.width - 4) < 0.2)
        // The sampled path still runs from the first point to the last.
        let start = try #require(back.points.first), end = try #require(back.points.last)
        #expect(hypot(start.x - 50, start.y - 40) < 1.5)
        #expect(hypot(end.x - 200, end.y - 90) < 1.5)
        #expect(back.points.contains { $0.widthScale < 0.8 }, "the thin middle is kept")
    }

    @Test func highlighterBecomesAMarkerAndBack() throws {
        let ink = InkStroke(tool: .highlighter, color: RGBAColor(red: 1, green: 1, blue: 0), width: 12,
                            points: [InkPoint(x: 10, y: 10), InkPoint(x: 90, y: 10)])
        let stroke = conversion.pkStroke(from: ink, seed: 1)
        #expect(stroke.ink.inkType == .marker)
        let back = try #require(conversion.inkStrokes(from: stroke).first)
        #expect(back.tool == .highlighter)
        #expect(back.color.alpha > 0.99, "stored at full strength; translucency is added when drawing")
    }
}

import CoreGraphics
import Testing
@testable import PaperNestCore

@Suite struct TextMarkupTests {
    @Test func customColorsArePreservedAndInvalidColorsAreRejected() throws {
        let line = RecognizedLine(text: "Color", box: .exact(x: 0.1, y: 0.2, width: 0.5, height: 0.04), confidence: 1)
        let purple = RGBAColor(red: 0.5, green: 0.1, blue: 0.8)
        let stroke = try TextMarkupStyle.highlight.stroke(for: line, in: CGSize(width: 600, height: 800), color: purple)
        #expect(stroke.color == purple)
        for invalid in [RGBAColor(red: .nan, green: 0, blue: 0), RGBAColor(red: 2, green: 0, blue: 0),
                        RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)] {
            #expect(throws: TextMarkupError.invalidColor) {
                try TextMarkupStyle.underline.stroke(for: line, in: CGSize(width: 600, height: 800), color: invalid)
            }
        }
    }

    @Test(arguments: TextMarkupStyle.allCases)
    func marksStayInsideTheRecognizedSourceRectangle(_ style: TextMarkupStyle) throws {
        let line = RecognizedLine(text: "Résumé", box: .exact(x: 0.1, y: 0.2, width: 0.5, height: 0.02), confidence: 1)
        let stroke = try style.stroke(for: line, in: CGSize(width: 600, height: 800))
        #expect(stroke.points.count == 2)
        #expect(stroke.points[0].x - stroke.width / 2 == 60)
        #expect(stroke.points[1].x + stroke.width / 2 == 360)
        #expect(stroke.points[0].y == stroke.points[1].y)
        if style == .highlight {
            #expect(stroke.tool == .highlighter)
            #expect(stroke.width == 16)
            #expect(stroke.points[0].y == 168)
        } else if style == .underline {
            #expect(stroke.points[0].y + stroke.width / 2 == 176)
        } else {
            #expect(stroke.points[0].y == 168)
        }
    }

    @Test(arguments: TextMarkupStyle.allCases)
    func narrowAndThinBoxesDoNotCreateReversedLines(_ style: TextMarkupStyle) throws {
        let line = RecognizedLine(text: "I", box: .exact(x: 0, y: 0.99, width: 0.001, height: 0.001), confidence: 1)
        let stroke = try style.stroke(for: line, in: CGSize(width: 600, height: 800))
        #expect(stroke.width <= 0.6)
        #expect(stroke.points[0].x <= stroke.points[1].x)
        #expect(stroke.points[0].y + stroke.width / 2 <= 800)
    }

    @Test func invalidCoordinatesAreRejected() {
        for box in [NormalizedRect.exact(x: .nan, y: 0, width: 0.1, height: 0.1),
                    .exact(x: 0.8, y: 0, width: 0.5, height: 0.1),
                    .exact(x: 0, y: 0, width: 0, height: 0.1)] {
            let line = RecognizedLine(text: "Invalid", box: box, confidence: 1)
            #expect(throws: TextMarkupError.invalidBounds) {
                try TextMarkupStyle.highlight.stroke(for: line, in: CGSize(width: 600, height: 800))
            }
        }
    }
}

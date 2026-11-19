import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Presenting a document: stepping through its pages, and the laser
/// pointer's fading trail, with times given rather than read from a clock.
@Suite struct PresentationTests {
    @Test func aPresentationStartsOnThePageBeingRead() {
        #expect(PresentationDeck(pageCount: 5, startingAt: 2).index == 2)
        #expect(PresentationDeck(pageCount: 5, startingAt: 9).index == 4, "held to the last page")
        #expect(PresentationDeck(pageCount: 5, startingAt: -1).index == 0)
    }

    @Test func itStepsThroughThePagesAndStopsAtTheEnds() {
        var deck = PresentationDeck(pageCount: 3, startingAt: 0)
        #expect(!deck.canGoBack && deck.canGoForward)
        #expect(!deck.back() && deck.index == 0)
        #expect(deck.forward() && deck.index == 1)
        #expect(deck.forward() && deck.index == 2)
        #expect(!deck.canGoForward)
        #expect(!deck.forward() && deck.index == 2, "the last page stays")
        deck.go(to: 1)
        #expect(deck.index == 1)
        deck.go(to: 40)
        #expect(deck.index == 2)
    }

    @Test func aOnePageDocumentGoesNowhere() {
        var deck = PresentationDeck(pageCount: 1, startingAt: 0)
        #expect(!deck.canGoBack && !deck.canGoForward)
        #expect(!deck.forward() && !deck.back() && deck.index == 0)
    }

    @Test func theTrailFadesAndThenIsGone() {
        var trail = LaserTrail()
        trail.add(CGPoint(x: 0.2, y: 0.3), at: 10)
        trail.add(CGPoint(x: 0.25, y: 0.3), at: 10.3)
        let halfway = trail.visible(at: 10.3)
        #expect(halfway.count == 2)
        #expect(abs(halfway[0].opacity - 0.5) < 1e-9, "the older point is half faded")
        #expect(halfway[1].opacity == 1, "the newest is whole")
        #expect(trail.visible(at: 10.65).count == 1, "the first point is gone after its lifetime")
        #expect(trail.isAlive(at: 10.85))
        #expect(!trail.isAlive(at: 10.95), "nothing shows once the last point has faded")
        #expect(trail.visible(at: 10.95).isEmpty)
    }

    @Test func oldPointsAreDroppedAndALongGestureKeepsItsNewest() {
        var trail = LaserTrail()
        trail.add(CGPoint(x: 0.1, y: 0.1), at: 0)
        trail.add(CGPoint(x: 0.5, y: 0.5), at: 5)
        #expect(trail.points.count == 1, "a point past its lifetime is dropped when another comes")
        for step in 0..<200 { trail.add(CGPoint(x: Double(step) / 200, y: 0.5), at: 6 + Double(step) * 0.001) }
        #expect(trail.points.count == LaserTrail.maximumPoints)
        #expect(trail.points.last?.location.x == 199.0 / 200)
        trail.clear()
        #expect(trail.points.isEmpty)
    }
}

/// The pen pointer's drawing: strokes kept while the page is shown, a tap
/// leaves nothing, and clearing empties it.
@Suite struct PenSketchTests {
    @Test func aDragIsAStrokeAndATapIsNothing() {
        var sketch = PenSketch()
        #expect(sketch.isEmpty)
        sketch.extend(to: CGPoint(x: 0.2, y: 0.2))
        sketch.extend(to: CGPoint(x: 0.4, y: 0.25))
        #expect(sketch.current?.count == 2 && sketch.strokes.isEmpty, "the stroke is still being drawn")
        sketch.end()
        #expect(sketch.strokes.count == 1 && sketch.current == nil)
        sketch.extend(to: CGPoint(x: 0.5, y: 0.5))
        sketch.extend(to: CGPoint(x: 0.5, y: 0.5))
        sketch.end()
        #expect(sketch.strokes.count == 1, "a touch that never moved is not a stroke")
    }

    @Test func pointsAreHeldToThePageAndClearingEmpties() {
        var sketch = PenSketch()
        sketch.extend(to: CGPoint(x: -0.2, y: 0.5))
        sketch.extend(to: CGPoint(x: 1.4, y: 1.2))
        sketch.end()
        #expect(sketch.strokes[0] == [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 1)])
        sketch.clear()
        #expect(sketch.isEmpty)
    }

    @Test func thePointersAreThree() {
        #expect(PresentationPointer.allCases == [.none, .laser, .pen])
    }
}

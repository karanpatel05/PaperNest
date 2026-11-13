import Testing
@testable import PaperNestUI

/// The single finger goes to the scroll view unless the tool can really use it.
@Suite struct PageScrollTouchPolicyTests {
    /// The case the owner hit: Pen armed on iPad, where "Draw with Finger" is
    /// off by default. The finger cannot draw, so it must be free to scroll.
    @Test func aPenThatCannotDrawByFingerLeavesTheFingerToTheScrollView() {
        #expect(PageScrollTouchPolicy.requiresTwoFingers(
            markingUp: true, tool: .pen, fingerDrawing: false) == false)
        #expect(PageScrollTouchPolicy.requiresTwoFingers(
            markingUp: true, tool: .highlighter, fingerDrawing: false) == false)
        #expect(PageScrollTouchPolicy.requiresTwoFingers(
            markingUp: true, tool: .eraser, fingerDrawing: false) == false)
    }

    /// Lasso is selection, not drawing, so "Draw with Finger" does not gate
    /// it: a finger lassoes whatever that setting says. Hand the finger to
    /// the scroll view here and lasso selection stops working altogether.
    @Test func lassoKeepsTheFingerEvenWhenFingerDrawingIsOff() {
        #expect(PageScrollTouchPolicy.requiresTwoFingers(
            markingUp: true, tool: .lasso, fingerDrawing: false))
        #expect(PageScrollTouchPolicy.requiresTwoFingers(
            markingUp: true, tool: .lasso, fingerDrawing: true))
    }

    /// Where a finger may draw, the reservation earns its keep for every tool:
    /// a stroke must not be stolen by the scroll view.
    @Test func aFingerThatDrawsKeepsThePageStill() {
        for tool in MacMarkupTool.allCases {
            #expect(PageScrollTouchPolicy.requiresTwoFingers(
                markingUp: true, tool: tool, fingerDrawing: true), "\(tool)")
        }
    }

    /// Nothing is armed, so nothing is reserved — lasso included.
    @Test func withoutMarkupTheFingerAlwaysScrolls() {
        for tool in MacMarkupTool.allCases {
            #expect(PageScrollTouchPolicy.requiresTwoFingers(
                markingUp: false, tool: tool, fingerDrawing: false) == false, "\(tool)")
            #expect(PageScrollTouchPolicy.requiresTwoFingers(
                markingUp: false, tool: tool, fingerDrawing: true) == false, "\(tool)")
        }
    }
}

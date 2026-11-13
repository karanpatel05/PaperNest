/// Who gets the single finger on a notebook page: the ink, or the scroll view.
///
/// While markup is armed the page scroll view raises its pan recognizer to
/// `minimumNumberOfTouches = 2`, reserving one finger for drawing so a stroke
/// is not read as a scroll. That reservation only makes sense when a finger is
/// allowed to draw in the first place.
///
/// On iPad it often is not: "Draw with Finger" defaults to **off**, which runs
/// PencilKit at `.pencilOnly`. Reserving the finger there took it away from
/// the scroll view and gave it to a canvas that refuses it — so with the Pen
/// armed the finger could neither draw nor scroll, and the page would not move
/// for a hand at all. Only the Pencil worked.
///
/// Kept out of the view, and free of UIKit, so the rule can be tested directly
/// on any platform. The end-to-end touch behaviour cannot be: XCUITest
/// synthesizes drags that drive the scroll view whatever
/// `minimumNumberOfTouches` says, so a UI test passes either way and proves
/// nothing.
enum PageScrollTouchPolicy {
    /// `true` when the page should only pan under two fingers.
    ///
    /// Lasso is the exception that makes this a rule about the *tool* rather
    /// than about drawing. It selects, it does not draw, so "Draw with
    /// Finger" does not gate it and a finger lassoes whatever that setting
    /// says. Give the finger to the scroll view while lasso is armed and
    /// lasso selection stops working at all.
    ///
    /// The Shapes tool is the same case for the same reason: a shape is
    /// dragged out with one finger whatever "Draw with Finger" says, so that
    /// finger cannot also be the one that scrolls.
    static func requiresTwoFingers(markingUp: Bool, tool: MacMarkupTool, fingerDrawing: Bool) -> Bool {
        guard markingUp else { return false }
        return tool == .lasso || tool == .shape || fingerDrawing
    }
}

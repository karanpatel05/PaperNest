import XCTest

extension XCUIElement {
    /// Flip a SwiftUI `Toggle` drawn with the switch style.
    ///
    /// A plain `tap()` does not work on one. The element's frame covers the
    /// whole row — label on the leading edge, switch on the trailing one —
    /// and a centre tap therefore lands on the label, which does nothing,
    /// exactly as tapping a label in Settings does nothing. Measured on
    /// iPad: a centre tap left the value at 1, while a tap at 0.92 across
    /// moved it 1 → 0 → 1 and the inspector column followed.
    func flipSwitch() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Activate a control however its platform draws it: iPad and Mac fold
    /// the editor's panel toggles into switches inside the `editor-panels`
    /// popover, while the phone keeps plain buttons.
    func toggleControl() {
        if elementType == .switch { flipSwitch() } else { tap() }
    }
}

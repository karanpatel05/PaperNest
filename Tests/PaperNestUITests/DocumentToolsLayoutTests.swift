import CoreGraphics
import Testing
@testable import PaperNestUI

/// How many tools Document Tools puts in a row. The panel's inner width is its
/// column width less 48 points of padding.
@Suite struct DocumentToolsLayoutTests {
    #if os(macOS)
    /// The Mac mockup is denser than the iPad: four across in the default
    /// 320-point column, five once the column is dragged to its widest.
    @Test func aMacFitsFourToolsInTheDefaultColumnAndFiveInTheWidest() {
        let grid = ToolGridLayout()
        #expect(grid.columns(for: 320 - 48) == 4)
        #expect(grid.columns(for: 400 - 48) == 5)
        #expect(grid.columns(for: 280 - 48) == 3, "the narrowest the column goes")
    }
    #else
    @Test func anIPadColumnFitsTwoAndAPhoneDrawerThree() {
        let grid = ToolGridLayout()
        #expect(grid.columns(for: 320 - 48) == 2)
        #expect(grid.columns(for: 390 - 48) == 3)
    }
    #endif

    @Test func neverFewerThanTwoAcross() {
        #expect(ToolGridLayout().columns(for: 40) == 2)
    }
}

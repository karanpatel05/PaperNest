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

    /// A Mac inspector column asks its content for an ideal size at infinite
    /// width. That crashed the Mac editor the moment a document opened.
    @Test func anUnboundedWidthIsAnsweredWithoutTrapping() {
        let grid = ToolGridLayout()
        #expect(grid.columns(for: .infinity) == grid.columns(for: 272))
        #expect(grid.columns(for: .nan) == grid.columns(for: 272))
        #expect(grid.columns(for: 0) == grid.columns(for: 272))
        #expect(ToolGridLayout.usableWidth(nil) == 272)
        #expect(ToolGridLayout.usableWidth(.infinity) == 272)
        #expect(ToolGridLayout.usableWidth(300) == 300)
    }

    @Test func neverFewerThanTwoAcross() {
        #expect(ToolGridLayout().columns(for: 40) == 2)
    }
}

import CoreGraphics
import Testing
@testable import PaperNestUI

@Suite struct PageZoomTests {
    @Test func buttonsAdvanceFromArbitraryPinchScaleWithoutSkipping() {
        #expect(PageZoom.step(1.2, direction: 1) == 1.5)
        #expect(PageZoom.step(1.2, direction: -1) == 1)
        #expect(PageZoom.step(1.5, direction: 1) == 2)
        #expect(PageZoom.step(1.5, direction: -1) == 1)
    }
    @Test func zoomStopsAtSupportedLimits() {
        #expect(PageZoom.step(4, direction: 1) == 4)
        #expect(PageZoom.step(0.5, direction: -1) == 0.5)
        #expect(PageZoom.clamp(9) == 4)
        #expect(PageZoom.clamp(0.1) == 0.5)
    }
}

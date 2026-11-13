import Testing
@testable import PaperNestUI

/// "Go to Page": what counts as a page number.
@Suite struct PageNumberEntryTests {
    @Test func aNumberInRangeIsThatPage() {
        #expect(PageNumberEntry.pageIndex(for: "1", pageCount: 12) == 0)
        #expect(PageNumberEntry.pageIndex(for: " 7 ", pageCount: 12) == 6)
        #expect(PageNumberEntry.pageIndex(for: "12", pageCount: 12) == 11)
    }

    /// Asking for page 500 of twelve is asking for the last page, and page 0
    /// for the first: an error would only make the reader type it again.
    @Test func aNumberPastEitherEndMeansThatEnd() {
        #expect(PageNumberEntry.pageIndex(for: "500", pageCount: 12) == 11)
        #expect(PageNumberEntry.pageIndex(for: "0", pageCount: 12) == 0)
        #expect(PageNumberEntry.pageIndex(for: "-3", pageCount: 12) == 0)
    }

    @Test func anythingThatIsNotANumberGoesNowhere() {
        #expect(PageNumberEntry.pageIndex(for: "", pageCount: 12) == nil)
        #expect(PageNumberEntry.pageIndex(for: "seven", pageCount: 12) == nil)
        #expect(PageNumberEntry.pageIndex(for: "3.5", pageCount: 12) == nil)
        #expect(PageNumberEntry.pageIndex(for: "3", pageCount: 0) == nil)
    }
}

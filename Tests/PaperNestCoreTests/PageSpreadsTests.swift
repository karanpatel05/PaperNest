import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Which pages sit side by side in two-page view.
@Suite struct PageSpreadsTests {
    private static let portrait = CGSize(width: 612, height: 792)
    private static let landscape = CGSize(width: 792, height: 612)

    private func pages(_ sizes: [CGSize]) -> [(id: PageID, size: CGSize)] {
        sizes.enumerated().map { (PageID(rawValue: "p\($0.offset + 1)"), $0.element) }
    }

    /// The spreads as page numbers, for reading.
    private func numbers(_ spreads: [[PageID]]) -> [[Int]] {
        spreads.map { $0.map { Int($0.rawValue.dropFirst())! } }
    }

    @Test func pagesPairFromTheFirst() {
        let spreads = PageSpreads.spreads(of: pages(Array(repeating: Self.portrait, count: 5)), coverAlone: false)
        #expect(numbers(spreads) == [[1, 2], [3, 4], [5]])
    }

    @Test func withTheCoverAloneTwoFacesThree() {
        let spreads = PageSpreads.spreads(of: pages(Array(repeating: Self.portrait, count: 5)), coverAlone: true)
        #expect(numbers(spreads) == [[1], [2, 3], [4, 5]])
    }

    /// A landscape page stands alone, and the page before it is not paired
    /// across it out of order.
    @Test func aWidePageStandsAlone() {
        let sizes = [Self.portrait, Self.portrait, Self.portrait, Self.landscape, Self.portrait, Self.portrait]
        #expect(numbers(PageSpreads.spreads(of: pages(sizes), coverAlone: false)) == [[1, 2], [3], [4], [5, 6]])
    }

    @Test func aWideCoverAndWidePagesEverywhere() {
        #expect(numbers(PageSpreads.spreads(of: pages([Self.landscape, Self.landscape]), coverAlone: false)) == [[1], [2]])
        #expect(numbers(PageSpreads.spreads(of: pages([Self.landscape, Self.portrait, Self.portrait]), coverAlone: true))
                == [[1], [2, 3]])
    }

    @Test func aSquarePageIsNotWide() {
        let square = CGSize(width: 600, height: 600)
        #expect(numbers(PageSpreads.spreads(of: pages([square, square]), coverAlone: false)) == [[1, 2]])
    }

    @Test func noPagesNoSpreadsAndOnePageAlone() {
        #expect(PageSpreads.spreads(of: [], coverAlone: false).isEmpty)
        #expect(numbers(PageSpreads.spreads(of: pages([Self.portrait]), coverAlone: false)) == [[1]])
    }

    @Test func everyPageIsInExactlyOneSpreadInOrder() {
        let sizes = (0..<23).map { $0 % 7 == 3 ? Self.landscape : Self.portrait }
        for cover in [false, true] {
            let spreads = PageSpreads.spreads(of: pages(sizes), coverAlone: cover)
            #expect(numbers(spreads).flatMap { $0 } == Array(1...23))
            #expect(spreads.allSatisfy { (1...2).contains($0.count) })
        }
    }

    @Test func theSpreadAPageIsIn() throws {
        let spreads = PageSpreads.spreads(of: pages(Array(repeating: Self.portrait, count: 4)), coverAlone: false)
        let found = try #require(PageSpreads.spread(containing: PageID(rawValue: "p4"), in: spreads))
        #expect(numbers([found]) == [[3, 4]])
        #expect(PageSpreads.spread(containing: PageID(rawValue: "missing"), in: spreads) == nil)
    }
}

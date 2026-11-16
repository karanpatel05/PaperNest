import Testing
@testable import PaperNestCore

@Suite struct ScanPageBatchTests {
    struct Sheet: Identifiable, Equatable {
        let id: String
        var filter = "original"
    }

    private func queue(_ names: String...) -> [Sheet] { names.map { Sheet(id: $0) } }
    private func names(_ pages: [Sheet]) -> [String] { pages.map(\.id) }

    // MARK: Delete

    @Test func deletingRemovesOnlyTheChosenPagesAndKeepsTheOrder() {
        let result = ScanPageBatch.delete(["b", "d"], from: queue("a", "b", "c", "d", "e"), focus: 2)
        #expect(names(result.pages) == ["a", "c", "e"])
        #expect(result.focus == 1, "the page being shown, c, is still the one shown")
    }

    @Test func deletingThePageBeingShownShowsTheNextOneLeft() {
        let result = ScanPageBatch.delete(["b", "c"], from: queue("a", "b", "c", "d"), focus: 1)
        #expect(names(result.pages) == ["a", "d"])
        #expect(result.focus == 1, "d followed the deleted pages")
    }

    @Test func deletingTheLastPagesShowsTheLastOneLeft() {
        let result = ScanPageBatch.delete(["c", "d"], from: queue("a", "b", "c", "d"), focus: 3)
        #expect(names(result.pages) == ["a", "b"])
        #expect(result.focus == 1)
    }

    @Test func deletingEveryPageLeavesAnEmptyQueue() {
        let result = ScanPageBatch.delete(["a", "b"], from: queue("a", "b"), focus: 1)
        #expect(result.pages.isEmpty)
        #expect(result.focus == 0)
    }

    @Test func deletingAPageThatIsNotInTheQueueChangesNothing() {
        let result = ScanPageBatch.delete(["z"], from: queue("a", "b"), focus: 1)
        #expect(names(result.pages) == ["a", "b"])
        #expect(result.focus == 1)
    }

    // MARK: Duplicate

    @Test func eachDuplicateFollowsThePageItCopies() {
        let result = ScanPageBatch.duplicate(["a", "c"], in: queue("a", "b", "c"), focus: 1) {
            Sheet(id: $0.id + "-copy", filter: $0.filter)
        }
        #expect(names(result.pages) == ["a", "a-copy", "b", "c", "c-copy"])
        #expect(result.copies == ["a-copy", "c-copy"])
        #expect(result.focus == 2, "b is still the page being shown")
    }

    @Test func aDuplicateCarriesThePageEdits() {
        var pages = queue("a", "b")
        pages[1].filter = "grayscale"
        let result = ScanPageBatch.duplicate(["b"], in: pages, focus: 0) { Sheet(id: $0.id + "-copy", filter: $0.filter) }
        #expect(result.pages.map(\.filter) == ["original", "grayscale", "grayscale"])
    }

    // MARK: Move as a group

    @Test func aGroupMovesOnePlaceEarlierTogether() {
        let result = ScanPageBatch.move(["b", "c"], .earlier, in: queue("a", "b", "c", "d"), focus: 2)
        #expect(names(result.pages) == ["b", "c", "a", "d"])
        #expect(result.focus == 1, "c moved with its group and is still shown")
    }

    @Test func aGroupMovesOnePlaceLaterTogether() {
        let result = ScanPageBatch.move(["b", "c"], .later, in: queue("a", "b", "c", "d"), focus: 0)
        #expect(names(result.pages) == ["a", "d", "b", "c"])
        #expect(result.focus == 0)
    }

    @Test func aGroupAtTheEdgeStaysWhereItIs() {
        let pages = queue("a", "b", "c")
        #expect(names(ScanPageBatch.move(["a", "b"], .earlier, in: pages, focus: 0).pages) == ["a", "b", "c"])
        #expect(names(ScanPageBatch.move(["b", "c"], .later, in: pages, focus: 0).pages) == ["a", "b", "c"])
        #expect(!ScanPageBatch.canMove(["a", "b"], .earlier, in: pages))
        #expect(!ScanPageBatch.canMove(["b", "c"], .later, in: pages))
        #expect(ScanPageBatch.canMove(["b", "c"], .earlier, in: pages))
        #expect(ScanPageBatch.canMove(["a", "b"], .later, in: pages))
    }

    /// Pages picked from different places travel as one block from then on:
    /// the block lands one place beyond its first page (earlier) or its last
    /// page (later), in the order the pages already had.
    @Test func scatteredPagesAreGatheredIntoOneBlock() {
        let pages = queue("a", "b", "c", "d", "e")
        #expect(names(ScanPageBatch.move(["b", "d"], .earlier, in: pages, focus: 0).pages) == ["b", "d", "a", "c", "e"])
        #expect(names(ScanPageBatch.move(["b", "d"], .later, in: pages, focus: 0).pages) == ["a", "c", "e", "b", "d"])
    }

    @Test func scatteredPagesAtTheEdgeCanStillBeGathered() {
        let pages = queue("a", "b", "c")
        #expect(ScanPageBatch.canMove(["a", "c"], .earlier, in: pages))
        #expect(names(ScanPageBatch.move(["a", "c"], .earlier, in: pages, focus: 1).pages) == ["a", "c", "b"])
    }

    @Test func movingNothingOrEverythingChangesNothing() {
        let pages = queue("a", "b", "c")
        #expect(names(ScanPageBatch.move([], .later, in: pages, focus: 1).pages) == ["a", "b", "c"])
        #expect(names(ScanPageBatch.move(["a", "b", "c"], .later, in: pages, focus: 1).pages) == ["a", "b", "c"])
        #expect(!ScanPageBatch.canMove([], .earlier, in: pages))
        #expect(!ScanPageBatch.canMove(["a", "b", "c"], .earlier, in: pages))
    }

    // MARK: Edit

    @Test func anEditReachesTheChosenPagesAndNoOthers() {
        var pages = queue("a", "b", "c")
        ScanPageBatch.update(["a", "c", "z"], in: &pages) { $0.filter = "blackAndWhite" }
        #expect(pages.map(\.filter) == ["blackAndWhite", "original", "blackAndWhite"])
    }
}

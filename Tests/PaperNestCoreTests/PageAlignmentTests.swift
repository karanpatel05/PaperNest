import Testing
@testable import PaperNestCore

/// Which old page became which new page, and what was added, removed or moved.
@Suite struct PageAlignmentTests {
    private let blank = [Double](repeating: 1, count: 256)

    /// A page with distinct words, named by `tag`.
    private func page(_ tag: String) -> PageSignature {
        PageSignature(foldedWords: (0..<20).map { "\(tag)\($0)" }, fingerprint: blank)
    }

    private func blankPage() -> PageSignature { PageSignature(foldedWords: [], fingerprint: blank) }

    @Test func theSameDocumentMatchesPageForPage() {
        let pages = ["a", "b", "c"].map(page)
        #expect(PageAlignment.align(old: pages, new: pages) == [
            .matched(old: 0, new: 0, moved: false), .matched(old: 1, new: 1, moved: false),
            .matched(old: 2, new: 2, moved: false)])
    }

    /// One page at the front is one added page, not every page after it moved.
    @Test func aPageInsertedAtTheFrontIsOneAddedPage() {
        let old = ["a", "b", "c"].map(page)
        let new = ["x", "a", "b", "c"].map(page)
        #expect(PageAlignment.align(old: old, new: new) == [
            .added(new: 0), .matched(old: 0, new: 1, moved: false), .matched(old: 1, new: 2, moved: false),
            .matched(old: 2, new: 3, moved: false)])
    }

    @Test func aDeletedPageIsRemovedAndShownWhereItWas() {
        let old = ["a", "b", "c"].map(page)
        let new = ["a", "c"].map(page)
        #expect(PageAlignment.align(old: old, new: new) == [
            .matched(old: 0, new: 0, moved: false), .removed(old: 1), .matched(old: 2, new: 1, moved: false)])
    }

    @Test func theFirstPageDeletedComesFirst() {
        #expect(PageAlignment.align(old: ["a", "b"].map(page), new: ["b"].map(page)) == [
            .removed(old: 0), .matched(old: 1, new: 0, moved: false)])
    }

    @Test func twoSwappedPagesAreOneMove() {
        let old = ["a", "b", "c", "d"].map(page)
        let new = ["a", "c", "b", "d"].map(page)
        let entries = PageAlignment.align(old: old, new: new)
        let moved = entries.filter { if case .matched(_, _, true) = $0 { true } else { false } }
        #expect(moved.count == 1)
        #expect(entries.count == 4)
    }

    /// Identical blank pages pair in order rather than crosswise.
    @Test func identicalBlankPagesPairByPosition() {
        let old = [page("a"), blankPage(), blankPage(), page("b")]
        #expect(PageAlignment.align(old: old, new: old) == [
            .matched(old: 0, new: 0, moved: false), .matched(old: 1, new: 1, moved: false),
            .matched(old: 2, new: 2, moved: false), .matched(old: 3, new: 3, moved: false)])
    }

    /// A page with a few words changed is the same page, changed; one
    /// rewritten past the threshold is removed and added.
    @Test func aLightlyEditedPageMatchesAndARewrittenOneDoesNot() {
        var edited = page("a")
        for index in 0..<5 { edited.foldedWords[index] = "edit\(index)" }   // 75% shared
        #expect(PageAlignment.align(old: [page("a")], new: [edited]) == [.matched(old: 0, new: 0, moved: false)])

        var rewritten = page("a")
        for index in 0..<16 { rewritten.foldedWords[index] = "new\(index)" }   // 20% shared
        #expect(Set(PageAlignment.align(old: [page("a")], new: [rewritten])) == [.removed(old: 0), .added(new: 0)])
    }

    /// Pages without words are matched by how they look.
    @Test func wordlessPagesMatchByTheirLook() {
        var dark = [Double](repeating: 1, count: 256)
        for index in 0..<128 { dark[index] = 0 }   // top half black
        let photo = PageSignature(foldedWords: [], fingerprint: dark)
        let entries = PageAlignment.align(old: [blankPage(), photo], new: [photo, blankPage()])
        #expect(entries.contains(.matched(old: 1, new: 0, moved: false)) || entries.contains(.matched(old: 1, new: 0, moved: true)))
        #expect(entries.count == 2)
    }

    @Test func diceCountsRepeatedWords() {
        #expect(PageAlignment.dice(["a", "a", "b"], ["a", "b", "b"]) == 2.0 * 2 / 6)
        #expect(PageAlignment.dice([], []) == 1)
    }

    @Test func longestIncreasingRun() {
        #expect(PageAlignment.longestIncreasingRun([0, 2, 1, 3]).count == 3)
        #expect(PageAlignment.longestIncreasingRun([1, 2, 3, 0]) == [0, 1, 2])
        #expect(PageAlignment.longestIncreasingRun([]) == [])
    }
}

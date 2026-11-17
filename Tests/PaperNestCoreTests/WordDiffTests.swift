import Testing
@testable import PaperNestCore

/// The word diff under the comparison: shared words kept, every other word
/// part of exactly one change.
@Suite struct WordDiffTests {
    private func words(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }

    @Test func identicalRunsHaveNoChanges() {
        #expect(WordDiff.changes(words("Invoice total 42"), words("Invoice total 42")).isEmpty)
        #expect(WordDiff.changes([], []).isEmpty)
    }

    @Test func oneWordReplacedIsOneChangeWithBothSides() {
        let changes = WordDiff.changes(words("Paid on 3 March 2026"), words("Paid on 3 April 2026"))
        #expect(changes == [WordDiff.Change(removed: 3..<4, added: 3..<4)])
    }

    @Test func wordsAddedAndRemovedAreSeparateChanges() {
        let changes = WordDiff.changes(words("the quick brown fox jumps"), words("the brown fox quietly jumps"))
        #expect(changes == [WordDiff.Change(removed: 1..<2, added: 1..<1),
                            WordDiff.Change(removed: 4..<4, added: 3..<4)])
    }

    @Test func everythingNewOrEverythingGone() {
        #expect(WordDiff.changes([], words("a b")) == [WordDiff.Change(removed: 0..<0, added: 0..<2)])
        #expect(WordDiff.changes(words("a b"), []) == [WordDiff.Change(removed: 0..<2, added: 0..<0)])
    }

    /// Case, digits and accents are all things someone may be looking for.
    @Test func comparisonIsExactButUnicodeNormalized() {
        #expect(WordDiff.changes(["Total"], ["total"]).count == 1)
        #expect(WordDiff.changes(["10"], ["100"]).count == 1)
        // "é" precomposed and as e + combining accent are the same word.
        #expect(WordDiff.changes(["caf\u{E9}"], ["cafe\u{301}"]).isEmpty)
    }

    /// Every word not shared is in exactly one change, and the kept words
    /// are the same on both sides.
    @Test func changesAccountForEveryWord() {
        let old = words("one two three four five six seven eight nine ten")
        let new = words("zero one three four 4.5 five seven eight ten eleven")
        let changes = WordDiff.changes(old, new)
        let removed = Set(changes.flatMap { Array($0.removed) })
        let added = Set(changes.flatMap { Array($0.added) })
        let keptOld = old.indices.filter { !removed.contains($0) }.map { old[$0] }
        let keptNew = new.indices.filter { !added.contains($0) }.map { new[$0] }
        #expect(keptOld == keptNew)
        #expect(keptOld == words("one three four five seven eight ten"))
    }

    /// Past the table's size the differing middle is one coarse change, and
    /// the shared ends are still left out.
    @Test func aHugeDifferenceIsOneChangeBetweenTheSharedEnds() {
        let middleOld = (0..<2100).map { "a\($0)" }, middleNew = (0..<2100).map { "b\($0)" }
        let changes = WordDiff.changes(["start"] + middleOld + ["end"], ["start"] + middleNew + ["end"])
        #expect(changes == [WordDiff.Change(removed: 1..<2101, added: 1..<2101)])
    }
}

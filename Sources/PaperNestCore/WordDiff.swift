import Foundation

/// What changed between two runs of words: the longest run they share is
/// kept, and everything else is a change — words removed from the old run,
/// words added in the new one, or both at the same spot.
///
/// Words are compared exactly, after Unicode normalization: "Total" and
/// "total" differ, as "10" and "100" do, because either could be the change
/// someone is looking for.
public enum WordDiff {
    /// One place where the runs differ: `removed` indexes the old words,
    /// `added` the new ones. Either may be empty, never both.
    public struct Change: Hashable, Sendable {
        public var removed: Range<Int>
        public var added: Range<Int>

        public init(removed: Range<Int>, added: Range<Int>) {
            self.removed = removed
            self.added = added
        }
    }

    /// The most cells the comparison table may have. Past it, the part that
    /// differs is reported as one change — true, only coarser. A full page of
    /// small print is about 800 words, so two such pages that share nothing
    /// are 640,000 cells.
    public static let maximumCells = 4_000_000

    public static func changes(_ old: [String], _ new: [String]) -> [Change] {
        let a = old.map { $0.precomposedStringWithCanonicalMapping }
        let b = new.map { $0.precomposedStringWithCanonicalMapping }
        // What the runs share at either end is not part of the work.
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        let n = endA - start, m = endB - start
        if n == 0 && m == 0 { return [] }
        if n == 0 || m == 0 || n * m > maximumCells {
            return [Change(removed: start..<endA, added: start..<endB)]
        }

        // lengths[i][j]: the longest shared run of a[start+i...] and b[start+j...].
        let width = m + 1
        var lengths = [Int32](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lengths[i * width + j] = a[start + i] == b[start + j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }

        // Walk the table, collecting runs of removals and additions between
        // the words both sides keep.
        var result: [Change] = []
        var i = 0, j = 0
        var removedStart: Int?, addedStart: Int?
        func flush() {
            let removed = (removedStart ?? (start + i))..<(start + i)
            let added = (addedStart ?? (start + j))..<(start + j)
            if !removed.isEmpty || !added.isEmpty { result.append(Change(removed: removed, added: added)) }
            removedStart = nil; addedStart = nil
        }
        while i < n || j < m {
            if i < n, j < m, a[start + i] == b[start + j] {
                flush()
                i += 1; j += 1
            } else if j < m, i == n || lengths[i * width + j + 1] >= lengths[(i + 1) * width + j] {
                if addedStart == nil { addedStart = start + j }
                if removedStart == nil { removedStart = start + i }
                j += 1
            } else {
                if removedStart == nil { removedStart = start + i }
                if addedStart == nil { addedStart = start + j }
                i += 1
            }
        }
        flush()
        return result
    }
}

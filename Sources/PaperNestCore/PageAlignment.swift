import Foundation

/// What is known about one page for matching it with a page of the other
/// document: its words, folded, and a small grey fingerprint of how it looks.
public struct PageSignature: Hashable, Sendable {
    /// The page's words, case and accents folded, for telling pages apart.
    /// Empty when the page has none to compare.
    public var foldedWords: [String]
    /// `GrayPicture.fingerprint()`.
    public var fingerprint: [Double]

    public init(foldedWords: [String], fingerprint: [Double]) {
        self.foldedWords = foldedWords
        self.fingerprint = fingerprint
    }

    /// Fewer words than this and a page is matched by its look.
    public static let minimumWordsToMatchByText = 3

    var matchesByText: Bool { foldedWords.count >= Self.minimumWordsToMatchByText }
}

/// Which page of the old document became which page of the new one.
///
/// Every page is matched with the page of the other document most like it,
/// best pairs first; a page left without a partner was **removed** (old) or
/// **added** (new). A matched page is **moved** when it is out of order with
/// the rest: of the pairs, the longest run that keeps its order stays put,
/// so one page inserted at the front is one added page, not every page after
/// it moved.
public enum PageAlignment {
    public enum Entry: Hashable, Sendable {
        case matched(old: Int, new: Int, moved: Bool)
        case removed(old: Int)
        case added(new: Int)
    }

    /// Pages matched by their words need at least this much in common
    /// (Dice's coefficient over their words). A page rewritten past it is
    /// reported as removed and added: calling it "changed" would pair it
    /// with something it no longer resembles.
    public static let textThreshold = 0.35
    /// Pages matched by their look need at least this.
    public static let pictureThreshold = 0.9

    /// How alike two pages are, from 0 to 1, by words when both have enough
    /// of them, and otherwise by look.
    public static func similarity(_ a: PageSignature, _ b: PageSignature) -> (value: Double, byText: Bool) {
        if a.matchesByText && b.matchesByText {
            return (dice(a.foldedWords, b.foldedWords), true)
        }
        return (GrayPicture.similarity(a.fingerprint, b.fingerprint), false)
    }

    /// The pages in the order to show them: the new document's order, each
    /// removed page placed after the page that came before it in the old one.
    public static func align(old: [PageSignature], new: [PageSignature]) -> [Entry] {
        struct Candidate { let old: Int, new: Int, value: Double }
        var candidates: [Candidate] = []
        for (i, a) in old.enumerated() {
            for (j, b) in new.enumerated() {
                let (value, byText) = similarity(a, b)
                if value >= (byText ? textThreshold : pictureThreshold) {
                    candidates.append(Candidate(old: i, new: j, value: value))
                }
            }
        }
        // Best pairs first; between equals, the pages nearer each other's
        // place, so identical pages (blank ones, say) pair in order.
        candidates.sort {
            if $0.value != $1.value { return $0.value > $1.value }
            let d0 = abs($0.old - $0.new), d1 = abs($1.old - $1.new)
            if d0 != d1 { return d0 < d1 }
            return ($0.old, $0.new) < ($1.old, $1.new)
        }
        var partnerOfOld = [Int?](repeating: nil, count: old.count)
        var takenNew = [Bool](repeating: false, count: new.count)
        for candidate in candidates where partnerOfOld[candidate.old] == nil && !takenNew[candidate.new] {
            partnerOfOld[candidate.old] = candidate.new
            takenNew[candidate.new] = true
        }

        // In old order, the longest run of partners in increasing new order stays.
        let pairs = partnerOfOld.enumerated().compactMap { i, j in j.map { (old: i, new: $0) } }
        let staying = Set(longestIncreasingRun(pairs.map(\.new)).map { pairs[$0].old })

        // Each entry keyed for the new document's order. A removed page goes
        // after the new partner of the nearest old page before it that has one.
        var keyed: [(key: (Int, Int), entry: Entry)] = []
        for pair in pairs {
            keyed.append(((pair.new, 0), .matched(old: pair.old, new: pair.new, moved: !staying.contains(pair.old))))
        }
        for j in new.indices where !takenNew[j] {
            keyed.append(((j, 0), .added(new: j)))
        }
        for i in old.indices where partnerOfOld[i] == nil {
            let anchor = (0..<i).reversed().lazy.compactMap { partnerOfOld[$0] }.first ?? -1
            keyed.append(((anchor, 1 + i), .removed(old: i)))
        }
        return keyed.sorted { $0.key < $1.key }.map(\.entry)
    }

    /// 2·shared / (both counts), counting repeated words as often as they repeat.
    static func dice(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var counts: [String: Int] = [:]
        for word in a { counts[word, default: 0] += 1 }
        var shared = 0
        for word in b where (counts[word] ?? 0) > 0 {
            counts[word]! -= 1
            shared += 1
        }
        return 2 * Double(shared) / Double(a.count + b.count)
    }

    /// Indexes of one longest strictly increasing run of `values`.
    static func longestIncreasingRun(_ values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var tails: [Int] = []          // index in `values` of the smallest tail of each length
        var previous = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if values[tails[mid]] < value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var run: [Int] = []
        var index = tails.last ?? -1
        while index >= 0 { run.append(index); index = previous[index] }
        return run.reversed()
    }
}

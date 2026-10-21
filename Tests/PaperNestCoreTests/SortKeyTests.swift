import Testing
@testable import PaperNestCore

@Suite struct SortKeyTests {
    @Test func evenlySpacedKeysAreStrictlyIncreasingAndValid() {
        for count in [1, 2, 3, 20, 61, 62, 100, 1000] {
            let keys = SortKey.evenlySpaced(count: count)
            #expect(keys.count == count)
            #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 })
            #expect(keys.allSatisfy(SortKey.isValid))
        }
    }

    @Test func betweenStaysStrictlyBetween() throws {
        let keys = SortKey.evenlySpaced(count: 5)
        for (a, b) in zip(keys, keys.dropFirst()) {
            let mid = try SortKey.between(a, b)
            #expect(a < mid && mid < b)
        }
        let first = try SortKey.between(nil, keys[0])
        #expect(first < keys[0])
        let last = try SortKey.between(keys[4], nil)
        #expect(last > keys[4])
    }

    @Test func repeatedInsertionAtTheSameGapKeepsOrder() throws {
        // Worst case for fractional indexing: always inserting right after
        // the same key. Order must hold and keys must stay valid.
        var lower = "V"
        let upper = "W"
        var produced: [String] = []
        for _ in 0..<200 {
            let k = try SortKey.between(lower, upper)
            #expect(lower < k && k < upper)
            produced.append(k)
            lower = k
        }
        #expect(produced.allSatisfy(SortKey.isValid))
    }

    @Test func randomInsertionsMatchAReferenceArray() throws {
        var generator = SeededGenerator(seed: 42)
        var keys: [String] = []
        for _ in 0..<500 {
            let index = Int.random(in: 0...keys.count, using: &generator)
            let lower = index > 0 ? keys[index - 1] : nil
            let upper = index < keys.count ? keys[index] : nil
            keys.insert(try SortKey.between(lower, upper), at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test func rejectsUnorderedOrInvalidBounds() {
        #expect(throws: SortKey.KeyError.notOrdered("b", "a")) { try SortKey.between("b", "a") }
        #expect(throws: SortKey.KeyError.self) { try SortKey.between("a0", nil) }
        #expect(throws: SortKey.KeyError.self) { try SortKey.between("a-", nil) }
    }
}

/// Deterministic generator so failures reproduce.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

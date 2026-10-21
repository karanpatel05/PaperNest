import Foundation

/// Fractional indexing for stable ordering of pages and page objects.
///
/// Keys are base-62 digit strings read as fractions in (0, 1). Their ASCII
/// order equals their numeric order, so SQLite's default BINARY collation and
/// Swift's `<` agree. Moving a page rewrites only that page's key, which keeps
/// reorders small and mergeable during sync. Two devices can pick the same
/// key concurrently; ties are broken by the stable ID, so order stays
/// deterministic everywhere.
public enum SortKey {
    static let digits: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let base = 62

    public enum KeyError: Error, Equatable {
        case invalidKey(String)
        case notOrdered(String, String)
    }

    /// A key strictly between `lower` and `upper`. `nil` means unbounded.
    public static func between(_ lower: String?, _ upper: String?) throws -> String {
        let a = try lower.map(decode) ?? []
        var b = try upper.map(decode)
        if let lower, let upper, !(lower < upper) {
            throw KeyError.notOrdered(lower, upper)
        }
        var result: [Int] = []
        var i = 0
        while true {
            let da = i < a.count ? a[i] : 0
            let db: Int
            if let bDigits = b {
                // `upper` cannot run out first: that would make it a prefix
                // of `lower`, i.e. not greater.
                db = i < bDigits.count ? bDigits[i] : 0
            } else {
                db = base
            }
            if da == db {
                result.append(da)
                i += 1
                continue
            }
            let mid = (da + db) / 2
            if mid > da {
                result.append(mid)
                return encode(result)
            }
            // Adjacent digits: keep `da` and continue with no upper bound,
            // since any continuation of this prefix is already below `upper`.
            result.append(da)
            i += 1
            b = nil
        }
    }

    /// `count` increasing keys spread evenly, for building a new item.
    public static func evenlySpaced(count: Int) -> [String] {
        guard count > 0 else { return [] }
        // Width chosen so neighbouring keys are at least `base` apart, which
        // leaves room for insertions without immediately growing keys.
        var width = 1
        var capacity = base
        while capacity < (count + 1) * base {
            width += 1
            capacity *= base
        }
        return (1...count).map { i in
            let value = capacity / (count + 1) * i
            var digitsOut = [Int](repeating: 0, count: width)
            var v = value
            for pos in stride(from: width - 1, through: 0, by: -1) {
                digitsOut[pos] = v % base
                v /= base
            }
            while digitsOut.last == 0 { digitsOut.removeLast() }
            return encode(digitsOut)
        }
    }

    public static func isValid(_ key: String) -> Bool {
        (try? decode(key)) != nil
    }

    static func decode(_ key: String) throws -> [Int] {
        guard !key.isEmpty, key.last != "0" else { throw KeyError.invalidKey(key) }
        return try key.map { ch in
            guard let idx = digits.firstIndex(of: ch) else { throw KeyError.invalidKey(key) }
            return idx
        }
    }

    static func encode(_ values: [Int]) -> String {
        String(values.map { digits[$0] })
    }
}

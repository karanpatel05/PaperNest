import Foundation

/// One-based user input becomes stable zero-based indices before starting OCR.
enum OCRPageSelection {
    static func indices(in text: String, pageCount: Int) -> [Int]? {
        guard pageCount > 0 else { return nil }
        let normalized = text.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        var result = Set<Int>()
        for part in normalized.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (1...2).contains(bounds.count), let start = Int(bounds[0]), start >= 1, start <= pageCount else { return nil }
            let end: Int
            if bounds.count == 2 {
                guard let value = Int(bounds[1]), value >= start, value <= pageCount else { return nil }
                end = value
            } else { end = start }
            result.formUnion((start...end).map { $0 - 1 })
        }
        return result.isEmpty ? nil : result.sorted()
    }
}

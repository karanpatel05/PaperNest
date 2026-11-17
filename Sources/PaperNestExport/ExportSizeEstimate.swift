import Foundation
import PaperNestCore

/// How large an export will be, before it is made.
public struct ExportSizeEstimate: Equatable, Sendable {
    public var byteCount: Int64
    /// Every chosen page was exported to measure it: this is the size the
    /// export will be, not an estimate.
    public var isExact: Bool

    public init(byteCount: Int64, isExact: Bool) {
        self.byteCount = byteCount
        self.isExact = isExact
    }
}

/// The arithmetic of an estimate, apart from any exporting.
///
/// **A file's size is a cost paid once plus a cost per page**: embedded
/// fonts, the PDF's cross-reference table, a ZIP's or a Word file's package
/// are paid once, the pages' pictures and words once each. Scaling a few
/// pages' file up to the whole document would multiply the once-per-file
/// part too, and overshoot several times on a text PDF with embedded fonts;
/// exporting one page and a few pages separates the two.
public enum ExportSizeModel {
    /// Up to `limit` page positions spread evenly over `count` pages, the
    /// first and last included, the same ones every time.
    public static func sampleIndices(count: Int, limit: Int) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        guard count > limit else { return Array(0..<count) }
        guard limit > 1 else { return [0] }
        let step = Double(count - 1) / Double(limit - 1)
        var indices: [Int] = []
        for position in 0..<limit {
            let index = Int((Double(position) * step).rounded())
            if indices.last != index { indices.append(index) }
        }
        return indices
    }

    /// `one`: the first sample page alone; `sample`: all `sampleCount`
    /// sample pages together. The cost per page is what the other sample
    /// pages added; the cost per file is what is left of the one-page file.
    public static func estimate(one: Int64, sample: Int64, sampleCount: Int, total: Int) -> Int64 {
        guard sampleCount > 1, total > 0 else { return one }
        let perPage = max(0, Double(sample - one) / Double(sampleCount - 1))
        let perFile = max(0, Double(one) - perPage)
        return Int64((perFile + perPage * Double(total)).rounded())
    }
}

extension Exporter {
    /// How large exporting `pages` with `options` will be, found by really
    /// exporting some of them — the same writer, the same marks, the same
    /// quality — into temporary folders that are removed straight away.
    /// Nothing is stored and nothing is recognized.
    ///
    /// With `samplePages` pages or fewer chosen, they are all exported and the
    /// answer is exact. Otherwise it is worked out from the first sample page
    /// alone and from all of them (`ExportSizeModel`), so a document whose
    /// pages differ a lot — mostly text with a few photographs — can be off.
    ///
    /// No password: protecting a file barely changes its size. Cancelling the
    /// calling task stops it and removes what it wrote.
    public func estimateSize(itemName: String, pages: [Page], options: ExportOptions,
                             samplePages: Int = 4) async throws -> ExportSizeEstimate {
        guard !pages.isEmpty else { throw ExportError.noPages }
        let sample = ExportSizeModel.sampleIndices(count: pages.count, limit: max(2, samplePages))
        if sample.count == pages.count {
            return ExportSizeEstimate(byteCount: try await measure(itemName, pages, options), isExact: true)
        }
        let one = try await measure(itemName, [pages[sample[0]]], options)
        let all = try await measure(itemName, sample.map { pages[$0] }, options)
        return ExportSizeEstimate(byteCount: ExportSizeModel.estimate(one: one, sample: all, sampleCount: sample.count,
                                                                      total: pages.count),
                                  isExact: false)
    }

    private func measure(_ itemName: String, _ pages: [Page], _ options: ExportOptions) async throws -> Int64 {
        let output = try await export(itemName: itemName, pages: pages, options: options)
        defer { output.removeTemporaryFiles() }
        try Task.checkCancellation()
        return output.totalByteCount
    }
}

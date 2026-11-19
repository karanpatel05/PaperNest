import CoreGraphics
import Foundation
import PaperNestCore

/// Where the fold of an open book is on a straightened two-page spread.
///
/// The fold casts a shadow, or shows as a dark line, all the way down. So
/// each column of the spread gets a level that only full-height darkness
/// can lower — the shade 70% of the column is at or below, over the middle
/// 80% of its height, so print (a small share of any column) and a picture
/// covering part of the height do not count — and the fold is the darkest
/// smoothed column in the middle band, if it is a real dip with brighter
/// paper on both sides. Otherwise the spread is split halfway: a wrong
/// split costs adjusting two crops, which each half has.
public enum ScanGutter {
    /// The width the spread is measured at, in pixels.
    static let width = 600
    /// Where across the spread the fold is looked for.
    static let band = 0.35...0.65
    /// How far each column's level is averaged with its neighbours, each
    /// way, as a share of the width.
    static let smoothing = 0.012
    /// The paper beside the fold is looked for this far from it (shares of
    /// the width)…
    static let flank = 0.03...0.15
    /// …and must be at least this much brighter (0…1) on both sides.
    static let leastDip = 0.03

    /// The fold's position across `spread`, a share of its width.
    public static func find(in spread: CGImage) -> Double {
        let height = max(10, Int((Double(width) * Double(spread.height) / Double(max(1, spread.width))).rounded()))
        guard let picture = DocumentComparer.gray(spread, width: width, height: height) else { return 0.5 }
        let top = height / 10, bottom = height - height / 10
        var levels = [Double](repeating: 0, count: width)
        var column: [UInt8] = []
        column.reserveCapacity(bottom - top)
        for x in 0..<width {
            column.removeAll(keepingCapacity: true)
            for y in top..<bottom { column.append(picture.pixels[y * width + x]) }
            column.sort()
            levels[x] = Double(column[column.count * 7 / 10]) / 255
        }
        let reach = max(1, Int((Double(width) * smoothing).rounded()))
        let smoothed = levels.indices.map { x -> Double in
            let range = max(0, x - reach)...min(width - 1, x + reach)
            return range.reduce(0) { $0 + levels[$1] } / Double(range.count)
        }
        let from = Int(band.lowerBound * Double(width)), to = Int(band.upperBound * Double(width))
        guard let fold = (from...to).min(by: { smoothed[$0] < smoothed[$1] }) else { return 0.5 }
        func brightest(_ offsets: ClosedRange<Int>) -> Double {
            let range = max(0, offsets.lowerBound)...min(width - 1, offsets.upperBound)
            return range.map { smoothed[$0] }.max() ?? smoothed[fold]
        }
        let near = Int(flank.lowerBound * Double(width)), far = Int(flank.upperBound * Double(width))
        let left = brightest((fold - far)...(fold - near)), right = brightest((fold + near)...(fold + far))
        guard min(left, right) - smoothed[fold] >= leastDip else { return 0.5 }
        return (Double(fold) + 0.5) / Double(width)
    }
}

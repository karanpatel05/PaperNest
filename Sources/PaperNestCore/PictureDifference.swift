import Foundation

/// A page drawn small in shades of grey, row by row from the top: 0 is black,
/// 255 white. What the comparison looks at when words cannot tell it enough.
public struct GrayPicture: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height, "a picture's pixels must fill it")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The picture stretched or squeezed to `width` × `height`, each new
    /// pixel the mean of the old ones it covers (nearest, when enlarging).
    public func resized(width newWidth: Int, height newHeight: Int) -> GrayPicture {
        guard newWidth != width || newHeight != height else { return self }
        var result = [UInt8](repeating: 255, count: newWidth * newHeight)
        for y in 0..<newHeight {
            let top = y * height / newHeight
            let bottom = max(top + 1, (y + 1) * height / newHeight)
            for x in 0..<newWidth {
                let left = x * width / newWidth
                let right = max(left + 1, (x + 1) * width / newWidth)
                var sum = 0
                for row in top..<bottom {
                    for column in left..<right { sum += Int(pixels[row * width + column]) }
                }
                result[y * newWidth + x] = UInt8(sum / ((bottom - top) * (right - left)))
            }
        }
        return GrayPicture(width: newWidth, height: newHeight, pixels: result)
    }

    /// The picture as a `side` × `side` grid of shades from 0 to 1, whatever
    /// its shape: enough to tell pages apart, small enough to compare every
    /// page with every other.
    public func fingerprint(side: Int = 16) -> [Double] {
        resized(width: side, height: side).pixels.map { Double($0) / 255 }
    }

    /// How alike two fingerprints are, from 0 to 1.
    public static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total = 0.0
        for index in a.indices { total += abs(a[index] - b[index]) }
        return 1 - total / Double(a.count)
    }
}

/// Where two pictures of a page differ, as rectangles of the page.
///
/// The pictures are laid over each other and divided into cells; a cell
/// differs when its pixels do, on average and somewhere strongly, so the
/// grey fringe of a letter drawn half a pixel over is not a difference.
/// Neighbouring cells that differ become one rectangle.
///
/// This compares pixels, not meaning. Two photographs of the same paper,
/// taken separately, differ everywhere, because nothing lines them up; and a
/// page of a different shape is stretched onto the other before comparing.
public enum PictureDifference {
    /// Columns of cells across the page; rows follow the page's shape.
    public static let columns = 40
    /// A cell differs when its pixels differ by this much on average (of 255)…
    public static let meanThreshold = 6.0
    /// …and at least one of them by this much.
    public static let peakThreshold = 96

    /// Rectangles normalized to the page (top-left origin, 0…1), in reading
    /// order. `b` is stretched onto `a`'s size first. Cells touching any of
    /// `ignoring` (normalized the same way) are not counted.
    public static func regions(_ a: GrayPicture, _ b: GrayPicture,
                               ignoring: [NormalizedRect] = []) -> [NormalizedRect] {
        let other = b.resized(width: a.width, height: a.height)
        let columns = min(Self.columns, a.width)
        let rows = max(1, min(a.height, Int((Double(columns) * Double(a.height) / Double(a.width)).rounded())))
        var differs = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows {
            let top = row * a.height / rows, bottom = max(top + 1, (row + 1) * a.height / rows)
            for column in 0..<columns {
                let left = column * a.width / columns, right = max(left + 1, (column + 1) * a.width / columns)
                let cell = NormalizedRect.exact(x: Double(left) / Double(a.width), y: Double(top) / Double(a.height),
                                                width: Double(right - left) / Double(a.width),
                                                height: Double(bottom - top) / Double(a.height))
                if ignoring.contains(where: { $0.overlaps(cell) }) { continue }
                var sum = 0, peak = 0
                for y in top..<bottom {
                    for x in left..<right {
                        let delta = abs(Int(a.pixels[y * a.width + x]) - Int(other.pixels[y * a.width + x]))
                        sum += delta
                        peak = max(peak, delta)
                    }
                }
                let mean = Double(sum) / Double((bottom - top) * (right - left))
                differs[row * columns + column] = mean >= meanThreshold && peak >= peakThreshold
            }
        }
        return merged(differs, columns: columns, rows: rows, width: a.width, height: a.height)
    }

    /// Joins touching cells (sides and corners) into their bounding rectangles.
    private static func merged(_ differs: [Bool], columns: Int, rows: Int, width: Int, height: Int) -> [NormalizedRect] {
        var seen = [Bool](repeating: false, count: differs.count)
        var result: [NormalizedRect] = []
        for start in differs.indices where differs[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var minColumn = columns, maxColumn = -1, minRow = rows, maxRow = -1
            while let cell = stack.popLast() {
                let row = cell / columns, column = cell % columns
                minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let r = row + dy, c = column + dx
                        guard r >= 0, r < rows, c >= 0, c < columns else { continue }
                        let next = r * columns + c
                        if differs[next] && !seen[next] { seen[next] = true; stack.append(next) }
                    }
                }
            }
            let left = minColumn * width / columns, right = max(left + 1, (maxColumn + 1) * width / columns)
            let top = minRow * height / rows, bottom = max(top + 1, (maxRow + 1) * height / rows)
            result.append(.exact(x: Double(left) / Double(width), y: Double(top) / Double(height),
                                 width: Double(right - left) / Double(width), height: Double(bottom - top) / Double(height)))
        }
        return result.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }
}

extension NormalizedRect {
    /// Whether the two share any area.
    public func overlaps(_ other: NormalizedRect) -> Bool {
        x < other.x + other.width && other.x < x + width && y < other.y + other.height && other.y < y + height
    }
}

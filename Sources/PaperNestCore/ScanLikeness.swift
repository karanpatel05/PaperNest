import Accelerate
import Foundation

/// A captured page reduced to what tells one page of print from another:
/// how its shade changes along each row, at a size where words show and
/// letters do not.
///
/// Along the row only, because two different pages set the same way have
/// their lines in the same places: compared whole, their bands of print line
/// up and they look alike. Within a line, where the words begin and end is
/// the page's own; that is what a second photograph of the same page repeats
/// and another page does not.
public struct ScanFingerprint: Sendable, Equatable {
    /// The size every page is drawn at, whatever its shape (its shape is
    /// kept in `aspect`).
    public static let width = 160
    public static let height = 208
    /// How far along a row the row's own level is taken from, each way.
    static let rowReach = 8

    /// The shade minus its row's local level, smoothed by a pixel each way.
    let detail: [Float]
    /// The page's width over its height as captured.
    public let aspect: Double

    /// `picture` must be `width` × `height`.
    public init(_ picture: GrayPicture, aspect: Double) {
        precondition(picture.width == Self.width && picture.height == Self.height, "a fingerprint is drawn at its own size")
        let width = Self.width, height = Self.height
        let plane = picture.pixels.map { Float($0) / 255 }
        var detail = [Float](repeating: 0, count: plane.count)
        for y in 0..<height {
            let row = y * width
            // Prefix sums along the row, so each level is two reads.
            var sums = [Float](repeating: 0, count: width + 1)
            for x in 0..<width { sums[x + 1] = sums[x] + plane[row + x] }
            for x in 0..<width {
                let left = max(0, x - Self.rowReach), right = min(width, x + Self.rowReach + 1)
                detail[row + x] = plane[row + x] - (sums[right] - sums[left]) / Float(right - left)
            }
        }
        self.detail = Self.smoothed(detail, width: width, height: height)
        self.aspect = aspect
    }

    /// The mean of each pixel's 3 × 3 neighbourhood, edges extended: a
    /// second photograph is never laid exactly over the first.
    static func smoothed(_ plane: [Float], width: Int, height: Int) -> [Float] {
        var result = [Float](repeating: 0, count: plane.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for dy in -1...1 {
                    let row = min(height - 1, max(0, y + dy)) * width
                    for dx in -1...1 { sum += plane[row + min(width - 1, max(0, x + dx))] }
                }
                result[y * width + x] = sum / 9
            }
        }
        return result
    }
}

/// Whether two captured pages are the same page photographed twice.
///
/// The pages are first laid over each other at the one shift that matches
/// them best overall; then each tile may slide a little further on its own,
/// since a second photograph is cropped to slightly different corners and
/// the same words land apart by slightly different amounts across the page.
///
/// **Most of the page must match**: the likeness is the lower quartile of
/// the tiles' matches. A second photograph matches nearly everywhere, while
/// different print finds chance matches in a few tiles. Each of these was
/// measured on drawn pages of different print set the same way, against
/// 0.18 at the most as it is now: with the median, short pages read up to
/// 0.41; letting each tile slide the whole way on its own, with no shared
/// shift, 0.36; and with a fixed floor for which tiles count instead of a
/// tenth of the richest tile's detail, a dimmer page had so few tiles left
/// that their median was chance, and pages read up to 0.64.
///
/// **A missed repeat costs a look; a page wrongly called a repeat may be
/// deleted.** So the line is set where drawn pages of different print —
/// set the same way, the hardest case — stay well clear of it, and a page
/// with print in fewer than six tiles is not judged at all.
public enum ScanLikeness {
    public static let tilesAcross = 4
    public static let tilesDown = 4
    /// How far the whole page may slide each way, in pixels of the
    /// fingerprint (about 3% of the page's width)…
    public static let reach = 5
    /// …and each tile a little further.
    public static let tileReach = 2
    /// Pages whose shapes differ by more than this share are not the same
    /// page: a second photograph is cropped to the same paper.
    public static let aspectTolerance = 0.12
    /// A tile is compared when it has at least this share of the detail of
    /// the page's richest tile (margins and blank space are not)…
    static let tileShare: Float = 0.1
    /// …and at least this much (mean squared, 0…1 shades), so grain alone
    /// never counts.
    static let leastTileDetail: Float = 0.00005
    /// At least this many tiles must have something on them: with four, a
    /// page printed only near the top read 0.50 against different print. A
    /// page printed down only about a third of its height is not judged.
    static let leastTiles = 6
    /// At or above this, two pages are the same page.
    public static let sameAtLeast = 0.6

    /// How alike `a` and `b` are, 0…1: the lower quartile of the tiles'
    /// best matches. Nil when `a` has too little on it to tell (a blank page
    /// is not a repeat of another blank page: nothing on either says so).
    public static func likeness(_ a: ScanFingerprint, _ b: ScanFingerprint) -> Double? {
        guard abs(a.aspect / b.aspect - 1) <= aspectTolerance else { return 0 }
        let width = ScanFingerprint.width, height = ScanFingerprint.height
        // Tiles are laid over the inner part, so every slide stays on the page.
        let margin = reach + tileReach
        let tileWidth = (width - 2 * margin) / tilesAcross, tileHeight = (height - 2 * margin) / tilesDown
        let tiles = (0..<(tilesAcross * tilesDown)).map { index in
            (left: margin + (index % tilesAcross) * tileWidth, top: margin + (index / tilesAcross) * tileHeight)
        }
        // Sums of b's squares over any rectangle, from a table of running
        // sums: each slide's own size is then four reads, and only a·b is
        // added up, one row at a time with Accelerate.
        var squares = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width {
                let value = Double(b.detail[y * width + x])
                row += value * value
                squares[(y + 1) * (width + 1) + x + 1] = squares[y * (width + 1) + x + 1] + row
            }
        }
        func theirs(_ left: Int, _ top: Int) -> Double {
            let right = left + tileWidth, bottom = top + tileHeight
            return squares[bottom * (width + 1) + right] - squares[top * (width + 1) + right]
                - squares[bottom * (width + 1) + left] + squares[top * (width + 1) + left]
        }
        return a.detail.withUnsafeBufferPointer { first -> Double? in
            b.detail.withUnsafeBufferPointer { second -> Double? in
                guard let firstBase = first.baseAddress, let secondBase = second.baseAddress else { return nil }
                /// a·b over one tile, with b slid by (dx, dy).
                func both(_ tile: (left: Int, top: Int), _ dx: Int, _ dy: Int, _ own: Bool = false) -> Double {
                    var total = 0.0
                    for y in tile.top..<(tile.top + tileHeight) {
                        var row: Float = 0
                        let mine = firstBase + y * width + tile.left
                        vDSP_dotpr(mine, 1, own ? mine : secondBase + (y + dy) * width + tile.left + dx, 1, &row,
                                   vDSP_Length(tileWidth))
                        total += Double(row)
                    }
                    return total
                }
                let own = tiles.map { both($0, 0, 0, true) }
                let richest = own.max() ?? 0
                let area = Double(tileWidth * tileHeight)
                let counted = tiles.indices.filter {
                    own[$0] / area >= Double(leastTileDetail) && own[$0] >= Double(tileShare) * richest
                }
                guard counted.count >= leastTiles else { return nil }
                // The one shift that matches the counted tiles best together.
                let ownTotal = counted.reduce(0.0) { $0 + own[$1] }
                var best = (dx: 0, dy: 0, score: -2.0)
                for dy in -reach...reach {
                    for dx in -reach...reach {
                        var together = 0.0, theirTotal = 0.0
                        for index in counted {
                            together += both(tiles[index], dx, dy)
                            theirTotal += theirs(tiles[index].left + dx, tiles[index].top + dy)
                        }
                        guard theirTotal > 0 else { continue }
                        let score = together / (ownTotal * theirTotal).squareRoot()
                        if score > best.score { best = (dx, dy, score) }
                    }
                }
                // Each tile's own best near it.
                let scores = counted.map { index -> Double in
                    var top = 0.0
                    for dy in (best.dy - tileReach)...(best.dy + tileReach) {
                        for dx in (best.dx - tileReach)...(best.dx + tileReach) {
                            let size = theirs(tiles[index].left + dx, tiles[index].top + dy)
                            guard size > 0 else { continue }
                            top = max(top, both(tiles[index], dx, dy) / (own[index] * size).squareRoot())
                        }
                    }
                    return top
                }.sorted()
                return scores[scores.count / 4]
            }
        }
    }

    /// Whether `a` and `b` are the same page photographed twice. Both must
    /// have something on them, compared either way round.
    public static func isSamePage(_ a: ScanFingerprint, _ b: ScanFingerprint) -> Bool {
        guard let forward = likeness(a, b), let backward = likeness(b, a) else { return false }
        return min(forward, backward) >= sameAtLeast
    }
}

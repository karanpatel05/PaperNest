import CoreGraphics
import Foundation
import ImageIO
import PaperNestCore

/// Measures a captured page for `ScanQualityReport`: how sharp it is, how
/// bright its paper, and how steeply it was photographed.
///
/// Sharpness blurs the page a little more and asks how much of its fine
/// detail that took away (the re-blur idea of Crété-Roffet et al., 2007). A
/// sharp edge loses much of its steepness to a small blur; an edge that is
/// already soft loses little. As a share it does not depend on how much is
/// written on the page or how dark the ink is, only on how soft the edges
/// are. The page is first drawn at a fixed size, so the same page taken at
/// two resolutions reads the same.
///
/// **It compares the page at two slight blurs, not the picture with one.**
/// A grey picture has 256 shades, so a smooth slope is drawn as a staircase
/// of one-shade steps, and those steps are perfectly sharp; a camera's grain
/// is too. Measured on the picture as it is, a page blurred until its print
/// was faint read as *sharp*, those steps being all the edges it had left.
/// Blurring first by `fineSigma` smooths them away, and the test blur
/// (`coarseSigma`) then adds exactly one pixel's spread, as a single 1-pixel
/// blur of the picture would. (A test blur adding more, 1 to 2 pixels, was
/// tried: a page of small print blurred into soft stripes, one per line,
/// then read as sharp, since a smooth repeating pattern loses a share fixed
/// by its spacing, which a larger test blur makes larger.)
///
/// Measured on the page cropped to its corners and before any look
/// (`ScanAppearance`) is applied: a look that sharpens or brightens would
/// otherwise hide what the camera actually caught.
public enum ScanQualityAnalyzer {
    /// The longer side the page is measured at, in pixels. A larger page is
    /// drawn down to it; a smaller one is measured as it is, since enlarging
    /// would soften it.
    public static let longSide = 1000
    /// The two blurs compared (Gaussians' sigmas, in pixels at `longSide`):
    /// the first smooths away rounding and grain, the second adds one pixel
    /// of spread to it (variances add: 1 + 1 = √2²).
    static let fineSigma = 1.0
    static let coarseSigma = 2.0.squareRoot()
    /// How far around a pixel its surroundings reach (a Gaussian's sigma, in
    /// pixels at `longSide`): wide enough to take in the paper past a line of
    /// print, narrow enough to follow light falling off across the page.
    static let surroundingsSigma = 16.0
    /// Below this depth (0…1) of the page's darkest marks under their own
    /// surroundings there is nothing on the page to judge its focus by: a
    /// blank sheet is not blurry, however unevenly lit. Measured against
    /// the surroundings and not the whole page, because uneven light makes a
    /// blank sheet's corners differ by more than a blurred page's faint print
    /// differs from the paper beside it.
    static let leastMarkDepth = 0.025
    /// A pixel at or above this (of 255) is blown out to white.
    static let blownOut: UInt8 = 250
    /// The side of the cells glare is looked for in, in pixels at `longSide`
    /// (about 5 mm on a sheet of A4).
    static let glareCell = 16
    /// A cell is blown out when at least this share of its pixels is: ink
    /// under a reflection is washed out too, but not always to white.
    static let blownShare = 0.5
    /// Glare stands out from the paper around it: the page's typical paper
    /// (the median of its cells' paper levels) is at most this. A page whose
    /// paper is nearly white all over is exposed brightly, not reflecting.
    static let glarePaperAtMost = 0.9
    /// How many cells around a blown-out patch its halo is looked for in…
    static let haloReach = 2
    /// …and the share of those pixels that must lie between the paper and
    /// white. A reflection is light added, so it falls off gradually around
    /// its white core (measured 0.19 to 0.94); white printed on tinted paper
    /// — a form's box, a panel on a card — has a sharp edge (0.01 to 0.02).
    static let haloAtLeast = 0.1

    /// The report for `page`, the captured page cropped to its corners.
    /// `corners` are shares of the photo it was cropped from, `photoSize`
    /// that photo's size as shown (`photoSize(of:)`); without it, the angle
    /// is not judged.
    public static func report(page: CGImage, corners: [CGPoint], photoSize: CGSize?) -> ScanQualityReport? {
        examine(page: page, corners: corners, photoSize: photoSize)?.report
    }

    /// The report, and the page's `ScanFingerprint` for telling whether it
    /// repeats another, both from one grey picture of it.
    public static func examine(page: CGImage, corners: [CGPoint], photoSize: CGSize?)
        -> (report: ScanQualityReport, fingerprint: ScanFingerprint)? {
        guard let picture = grey(page) else { return nil }
        let fingerprint = ScanFingerprint(picture.resized(width: ScanFingerprint.width, height: ScanFingerprint.height),
                                          aspect: Double(page.width) / Double(max(1, page.height)))
        var histogram = [Int](repeating: 0, count: 256)
        for value in picture.pixels { histogram[Int(value)] += 1 }
        let paper = level(histogram, total: picture.pixels.count, share: 0.9)
        let plane = picture.pixels.map { Float($0) / 255 }
        let sharpness = markDepth(plane, width: picture.width, height: picture.height) < leastMarkDepth
            ? nil : self.sharpness(of: plane, width: picture.width, height: picture.height)
        let stretch = photoSize.flatMap { ScanQualityReport.stretch(of: corners, photoSize: $0) }
        return (ScanQualityReport(sharpness: sharpness, paperBrightness: paper, stretch: stretch, glare: glare(of: picture)),
                fingerprint)
    }

    /// The share of the page in its largest patch of blown-out cells
    /// (touching side by side), or 0 when the page's paper is itself nearly
    /// white, so nothing stands out, or when the patch has no halo, so it is
    /// white print and not light. One patch and not all of them: scattered
    /// white specks are not a reflection.
    static func glare(of picture: GrayPicture) -> Double {
        let cell = max(4, glareCell * max(picture.width, picture.height) / longSide)
        let columns = picture.width / cell, rows = picture.height / cell
        guard columns > 0, rows > 0 else { return 0 }
        var blown = [Bool](repeating: false, count: columns * rows)
        var paperLevels: [UInt8] = []
        var values: [UInt8] = []
        values.reserveCapacity(cell * cell)
        for row in 0..<rows {
            for column in 0..<columns {
                values.removeAll(keepingCapacity: true)
                var white = 0
                for y in (row * cell)..<((row + 1) * cell) {
                    let start = y * picture.width
                    for x in (column * cell)..<((column + 1) * cell) {
                        let value = picture.pixels[start + x]
                        values.append(value)
                        if value >= blownOut { white += 1 }
                    }
                }
                values.sort()
                // The cell's paper: a level most of it is at or below, past its ink.
                paperLevels.append(values[values.count * 3 / 4])
                blown[row * columns + column] = Double(white) >= blownShare * Double(values.count)
            }
        }
        let typicalPaper = Double(paperLevels.sorted()[paperLevels.count / 2]) / 255
        guard typicalPaper <= glarePaperAtMost else { return 0 }
        var seen = [Bool](repeating: false, count: blown.count)
        var largest: [Int] = []
        for start in blown.indices where blown[start] && !seen[start] {
            var stack = [start], patch: [Int] = []
            seen[start] = true
            while let index = stack.popLast() {
                patch.append(index)
                let row = index / columns, column = index % columns
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let r = row + dr, c = column + dc
                    guard (0..<rows).contains(r), (0..<columns).contains(c) else { continue }
                    let neighbour = r * columns + c
                    if blown[neighbour] && !seen[neighbour] { seen[neighbour] = true; stack.append(neighbour) }
                }
            }
            if patch.count > largest.count { largest = patch }
        }
        guard !largest.isEmpty,
              halo(around: largest, blown: blown, columns: columns, rows: rows, cell: cell, picture: picture,
                   typicalPaper: typicalPaper) >= haloAtLeast else { return 0 }
        return Double(largest.count) / Double(blown.count)
    }

    /// The share of the pixels within `haloReach` cells of `patch` (not in
    /// any blown-out cell) whose shade lies between the paper and white:
    /// the light falling off around a reflection.
    static func halo(around patch: [Int], blown: [Bool], columns: Int, rows: Int, cell: Int, picture: GrayPicture,
                     typicalPaper: Double) -> Double {
        var ring = Set<Int>()
        for index in patch {
            let row = index / columns, column = index % columns
            for r in max(0, row - haloReach)...min(rows - 1, row + haloReach) {
                for c in max(0, column - haloReach)...min(columns - 1, column + haloReach) where !blown[r * columns + c] {
                    ring.insert(r * columns + c)
                }
            }
        }
        guard !ring.isEmpty else { return 0 }
        let low = UInt8(min(255, (typicalPaper + 0.05) * 255)), high = blownOut
        var between = 0, total = 0
        for index in ring {
            let row = index / columns, column = index % columns
            for y in (row * cell)..<((row + 1) * cell) {
                let start = y * picture.width
                for x in (column * cell)..<((column + 1) * cell) {
                    let value = picture.pixels[start + x]
                    total += 1
                    if value >= low && value < high { between += 1 }
                }
            }
        }
        return Double(between) / Double(total)
    }

    /// The size of the photo in `data` as it is shown, its orientation
    /// applied: the frame its corners are shares of. Read from the file's
    /// header, without decoding the picture.
    public static func photoSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        // Orientations 5 to 8 turn the picture a quarter, so it is shown on its side.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The page in grey, its longer side at most `longSide`.
    static func grey(_ image: CGImage) -> GrayPicture? {
        let long = max(image.width, image.height)
        guard long > 0 else { return nil }
        let scale = min(1, Double(longSide) / Double(long))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        return DocumentComparer.gray(image, width: width, height: height)
    }

    /// The shade (0…1) that `share` of the pixels are at or below.
    static func level(_ histogram: [Int], total: Int, share: Double) -> Double {
        let target = max(1, Int((Double(total) * share).rounded(.up)))
        var seen = 0
        for (value, count) in histogram.enumerated() {
            seen += count
            if seen >= target { return Double(value) / 255 }
        }
        return 1
    }

    /// How much darker than their surroundings the page's darkest marks
    /// are, 0…1: the depth that only a hundredth of the page goes below.
    static func markDepth(_ plane: [Float], width: Int, height: Int) -> Double {
        let surroundings = ScanImageProcessor.Lighting.blurred(plane, width: width, height: height,
                                                               sigma: surroundingsSigma, extendingEdges: true)
        var depths = [Int](repeating: 0, count: 256)
        for index in plane.indices {
            let depth = max(0, min(1, surroundings[index] - plane[index]))
            depths[255 - Int((depth * 255).rounded())] += 1
        }
        // Counted from the deepest down, so the level at 1% is the depth only a hundredth exceeds.
        return 1 - level(depths, total: plane.count, share: 0.01)
    }

    /// How much of the picture's edge steepness, blurred by `fineSigma`, a
    /// further pixel of blur takes away, 0…1. Only called for a page with
    /// marks on it, so a picture with no steepness left at all is fully blurry.
    static func sharpness(of plane: [Float], width: Int, height: Int) -> Double {
        func blurred(_ sigma: Double) -> [Float] {
            ScanImageProcessor.Lighting.blurred(plane, width: width, height: height, sigma: sigma, extendingEdges: true)
        }
        let before = energy(blurred(fineSigma), width: width, height: height)
        guard before > 0 else { return 0 }
        let after = energy(blurred(coarseSigma), width: width, height: height)
        return min(1, max(0, 1 - after / before))
    }

    /// The sum of squared steps between neighbouring pixels, across and down.
    static func energy(_ plane: [Float], width: Int, height: Int) -> Double {
        plane.withUnsafeBufferPointer { pixels in
            var total = 0.0
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let here = pixels[row + x]
                    if x + 1 < width {
                        let step = Double(pixels[row + x + 1] - here)
                        total += step * step
                    }
                    if y + 1 < height {
                        let step = Double(pixels[row + width + x] - here)
                        total += step * step
                    }
                }
            }
            return total
        }
    }
}

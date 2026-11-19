import CoreGraphics
import Foundation

/// Something about a captured page worth a second look. Advice only: a page
/// is never refused, retaken or held back for it.
public enum ScanQualityIssue: String, CaseIterable, Sendable {
    /// The page's detail is soft: out of focus, or the camera moved.
    case blurry
    /// Photographed at a steep angle: the far side of the page is squeezed,
    /// so its writing has fewer pixels and straightening cannot add them back.
    case steepAngle
    /// The page itself is dark, not just its surroundings.
    case tooDark
}

/// What was measured on a captured page (`ScanQualityAnalyzer`), and the
/// verdict drawn from it.
///
/// Thresholds come from drawn pages — sharp and blurred text, darkened
/// paper, flat and tilted corners — **not from a real camera**, so they lean
/// towards saying nothing: a missed warning costs a look at the page, a
/// wrong one costs trust in every warning.
public struct ScanQualityReport: Equatable, Sendable {
    /// How much of the page's fine detail a slight further blur takes away,
    /// 0…1: a sharp page loses much of it, an already blurred one little.
    /// Nil when the page has too little on it to judge (a blank page is not
    /// blurry).
    public var sharpness: Double?
    /// How bright the page's paper is, 0 black … 1 white: the level only a
    /// tenth of the page is brighter than, so a page dense with print is not
    /// taken for a dark one.
    public var paperBrightness: Double
    /// The longer of each pair of opposite sides over the shorter, the worse
    /// pair (1 for a page photographed square on). Nil without corners.
    public var stretch: Double?

    /// Below this, a page with enough on it is blurry. Set from drawn print
    /// measured at `ScanQualityAnalyzer.longSide`: sharp pages read 0.38
    /// (headlines) to 0.62, softened by a 1-pixel blur 0.34 to 0.49, and
    /// blurred by 3 pixels or more, about 1 mm on a sheet of A4 where the
    /// print can no longer be read, 0.07 to 0.19, grain or not, down to print
    /// blurred until it is faint. A 2-pixel blur (0.22 to 0.26) is left
    /// unflagged on purpose: it is where print size starts to matter more
    /// than focus.
    public static let blurryBelow = 0.2
    /// Below this, the paper is too dark. Paper photographed in reasonable
    /// light is well above it; the live guide's darkness level is for the
    /// whole frame, background included, so it is lower.
    public static let darkBelow = 0.3
    /// Above this, one side of the page is half as long again as its
    /// opposite, so the far side has two thirds of the near side's pixels
    /// or fewer. The angle that takes depends on how close the camera is.
    public static let steepAbove = 1.5

    public init(sharpness: Double?, paperBrightness: Double, stretch: Double?) {
        self.sharpness = sharpness
        self.paperBrightness = paperBrightness
        self.stretch = stretch
    }

    /// The issues found, most worth fixing first: no use refocusing in the dark.
    public var issues: [ScanQualityIssue] {
        var found: [ScanQualityIssue] = []
        if paperBrightness < Self.darkBelow { found.append(.tooDark) }
        // A dark capture is grainy, and grain reads as detail: no verdict on focus.
        if let sharpness, sharpness < Self.blurryBelow, paperBrightness >= Self.darkBelow { found.append(.blurry) }
        if let stretch, stretch > Self.steepAbove { found.append(.steepAngle) }
        return found
    }

    /// How stretched a page's outline is in the photo: the larger of the two
    /// ratios between opposite sides. `corners` are shares of the photo from
    /// its top-left, in order around the page; `photoSize` turns them into
    /// lengths, since a share across is not a share down.
    public static func stretch(of corners: [CGPoint], photoSize: CGSize) -> Double? {
        guard corners.count == 4, photoSize.width > 0, photoSize.height > 0 else { return nil }
        let points = corners.map { CGPoint(x: $0.x * photoSize.width, y: $0.y * photoSize.height) }
        func length(_ a: Int, _ b: Int) -> Double { Double(hypot(points[a].x - points[b].x, points[a].y - points[b].y)) }
        let sides = [length(0, 1), length(1, 2), length(2, 3), length(3, 0)]
        guard sides.allSatisfy({ $0 > 0 }) else { return nil }
        func ratio(_ a: Double, _ b: Double) -> Double { max(a, b) / min(a, b) }
        return max(ratio(sides[0], sides[2]), ratio(sides[1], sides[3]))
    }
}

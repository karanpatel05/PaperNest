import CoreGraphics
import Foundation

/// An open book's two pages, photographed as one outline.
///
/// Corners are shares of the photo from its top-left, in crop order
/// (top-left, top-right, bottom-right, bottom-left), as `ScanQuad.corners`.
public enum ScanSpread {
    /// The outline is a spread when it is at least this much wider than
    /// tall in the photo's true proportions. Two pages side by side are
    /// about 1.3 to 1.6 times as wide as tall; one upright page about 0.7.
    /// A shorter-over-longer ratio cannot tell them apart — an A5 page and
    /// an A5 spread (A4 on its side) are both 0.707 — so it is which way the
    /// outline lies that does.
    public static let wideAtLeast = 1.1

    /// Whether `corners` outline two pages side by side, measured in the
    /// photo's pixels (`photoSize`, as shown). Cutting one page in half is
    /// the costly mistake, so anything not plainly wider than tall is one page.
    public static func isSpread(_ corners: [CGPoint], photoSize: CGSize) -> Bool {
        guard corners.count == 4, photoSize.width > 0, photoSize.height > 0 else { return false }
        let points = corners.map { CGPoint(x: $0.x * photoSize.width, y: $0.y * photoSize.height) }
        func length(_ a: Int, _ b: Int) -> Double { Double(hypot(points[a].x - points[b].x, points[a].y - points[b].y)) }
        let across = (length(0, 1) + length(3, 2)) / 2, down = (length(0, 3) + length(1, 2)) / 2
        return down > 0 && across / down >= wideAtLeast
    }

    /// The point at `(u, v)` of the straightened outline — 0…1 across from
    /// its left, 0…1 down from its top — in the photo. Projective, as the
    /// perspective correction that straightens a crop is: on a page seen at
    /// an angle, halfway across the straightened page is not halfway along
    /// its edges in the photo.
    public static func point(_ u: Double, _ v: Double, in corners: [CGPoint]) -> CGPoint {
        let x = corners.map { Double($0.x) }, y = corners.map { Double($0.y) }
        // The unit square's (0,0), (1,0), (1,1), (0,1) onto the corners (Heckbert's square-to-quad).
        let dx1 = x[1] - x[2], dx2 = x[3] - x[2], dx3 = x[0] - x[1] + x[2] - x[3]
        let dy1 = y[1] - y[2], dy2 = y[3] - y[2], dy3 = y[0] - y[1] + y[2] - y[3]
        var g = 0.0, h = 0.0
        let denominator = dx1 * dy2 - dx2 * dy1
        if abs(dx3) > 1e-12 || abs(dy3) > 1e-12, abs(denominator) > 1e-12 {
            g = (dx3 * dy2 - dx2 * dy3) / denominator
            h = (dx1 * dy3 - dx3 * dy1) / denominator
        }
        let a = x[1] - x[0] + g * x[1], b = x[3] - x[0] + h * x[3], c = x[0]
        let d = y[1] - y[0] + g * y[1], e = y[3] - y[0] + h * y[3], f = y[0]
        let w = g * u + h * v + 1
        return CGPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }

    /// The left and right pages of the spread `corners`, split at `gutter`
    /// (a share across the straightened spread), each in crop order.
    public static func halves(of corners: [CGPoint], at gutter: Double) -> [[CGPoint]] {
        guard corners.count == 4 else { return [] }
        let fold = min(0.9, max(0.1, gutter))
        let top = point(fold, 0, in: corners), bottom = point(fold, 1, in: corners)
        return [[corners[0], top, bottom, corners[3]], [top, corners[1], corners[2], bottom]]
    }
}

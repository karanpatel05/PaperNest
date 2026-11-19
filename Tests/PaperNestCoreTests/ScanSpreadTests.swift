import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// An open book's outline: whether it is two pages, and where the fold
/// line falls on it in the photo.
@Suite struct ScanSpreadTests {
    private let photo = CGSize(width: 4000, height: 3000)

    private func close(_ a: CGPoint, _ b: CGPoint, within: Double = 1e-9) -> Bool {
        Double(hypot(a.x - b.x, a.y - b.y)) <= within
    }

    /// The straightened outline's corners are the outline's corners.
    @Test func theCornersOfTheSquareAreTheOutlinesCorners() {
        let outline = [CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.9, y: 0.2), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.1, y: 0.8)]
        for (u, v, index) in [(0.0, 0.0, 0), (1.0, 0.0, 1), (1.0, 1.0, 2), (0.0, 1.0, 3)] {
            #expect(close(ScanSpread.point(u, v, in: outline), outline[index]), "corner \(index)")
        }
    }

    /// Seen square on, halfway across is halfway along the edges.
    @Test func aRectangleSplitsHalfway() {
        let outline = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.2), CGPoint(x: 0.9, y: 0.8), CGPoint(x: 0.1, y: 0.8)]
        let halves = ScanSpread.halves(of: outline, at: 0.5)
        #expect(halves.count == 2)
        #expect(close(halves[0][1], CGPoint(x: 0.5, y: 0.2)) && close(halves[0][2], CGPoint(x: 0.5, y: 0.8)))
        #expect(halves[0][0] == outline[0] && halves[0][3] == outline[3])
        #expect(halves[1][1] == outline[1] && halves[1][2] == outline[2])
        #expect(halves[0][1] == halves[1][0] && halves[0][2] == halves[1][3], "the halves share the fold")
    }

    /// Seen at an angle — the right side much nearer the camera, so taller —
    /// halfway across the straightened spread is nearer the far side in the
    /// photo than halfway along the edges, as perspective puts it. Checked
    /// independently: the fold must be where the outline's diagonals cross,
    /// which a projective map sends to the middle of the square.
    @Test func aSpreadSeenAtAnAngleSplitsWherePerspectivePutsTheMiddle() {
        let outline = [CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.7)]
        let middle = ScanSpread.point(0.5, 0.5, in: outline)
        // Where the diagonals 0–2 and 1–3 cross.
        let (p, r) = (outline[0], CGPoint(x: outline[2].x - outline[0].x, y: outline[2].y - outline[0].y))
        let (q, s) = (outline[1], CGPoint(x: outline[3].x - outline[1].x, y: outline[3].y - outline[1].y))
        let t = ((q.x - p.x) * s.y - (q.y - p.y) * s.x) / (r.x * s.y - r.y * s.x)
        #expect(close(middle, CGPoint(x: p.x + t * r.x, y: p.y + t * r.y), within: 1e-9))
        // And that is not halfway along the edges: interpolating would put the fold wrong.
        let halves = ScanSpread.halves(of: outline, at: 0.5)
        #expect(halves[0][1].x < 0.5 - 0.05, "the fold should sit toward the far (smaller) side: \(halves[0][1])")
    }

    @Test func aWideOutlineIsASpreadAndAnUprightOneIsAPage() {
        // 0.8 by 0.6 of a 4:3 photo: 3200 by 1800, wider than tall.
        let spread = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.2), CGPoint(x: 0.9, y: 0.8), CGPoint(x: 0.1, y: 0.8)]
        #expect(ScanSpread.isSpread(spread, photoSize: photo))
        // 0.4 by 0.8 of it: 1600 by 2400, a page standing up.
        let page = [CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.1), CGPoint(x: 0.7, y: 0.9), CGPoint(x: 0.3, y: 0.9)]
        #expect(!ScanSpread.isSpread(page, photoSize: photo))
        // The same shares in a photo held upright are 1200 by 3200: not a spread.
        #expect(!ScanSpread.isSpread(spread, photoSize: CGSize(width: 1500, height: 4000)))
        // Square (2400 by 2400 here) is one page: cutting one page in half is the costly mistake.
        let squarish = [CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.8, y: 0.1), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.2, y: 0.9)]
        #expect(!ScanSpread.isSpread(squarish, photoSize: photo))
        #expect(!ScanSpread.isSpread([], photoSize: photo))
    }

    /// A fold found too near an edge is held in, so neither page is a sliver.
    @Test func theFoldIsKeptAwayFromTheEdges() {
        let outline = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        #expect(close(ScanSpread.halves(of: outline, at: 0.01)[0][1], CGPoint(x: 0.1, y: 0)))
        #expect(close(ScanSpread.halves(of: outline, at: 0.99)[0][1], CGPoint(x: 0.9, y: 0)))
    }
}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender

/// Each mode's request, put to the real rectangle detector on scenes drawn
/// here: flat shapes on a flat ground, corners given as shares of the
/// picture from its top-left. One at a time: the detector parks the thread
/// it is called on.
@Suite(.serialized) struct ScanEdgeDetectorTests {
    typealias Shape = (corners: [CGPoint], gray: CGFloat)

    /// A picture `width` by `height` with `shapes` painted in order.
    static func scene(width: Int, height: Int, ground: CGFloat, _ shapes: [Shape]) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: ground, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for shape in shapes {
            context.setFillColor(CGColor(gray: shape.gray, alpha: 1))
            context.beginPath()
            // Core Graphics counts up from the bottom; the corners count down from the top.
            let points = shape.corners.map { CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height)) }
            context.addLines(between: points)
            context.closePath()
            context.fillPath()
        }
        return context.makeImage()!
    }

    static func corners(_ tl: (Double, Double), _ tr: (Double, Double), _ br: (Double, Double), _ bl: (Double, Double)) -> [CGPoint] {
        [tl, tr, br, bl].map { CGPoint(x: $0.0, y: $0.1) }
    }

    /// The furthest any found corner is from where it was drawn.
    static func worstMiss(_ quad: ScanQuad, _ drawn: [CGPoint]) -> Double {
        zip(quad.corners, drawn).map { Double(hypot($0.x - $1.x, $0.y - $1.y)) }.max() ?? 1
    }

    @Test func aSheetOnADeskIsFoundCornerForCorner() throws {
        let sheet = Self.corners((0.18, 0.15), (0.80, 0.12), (0.86, 0.84), (0.14, 0.88))
        let picture = Self.scene(width: 1200, height: 1600, ground: 0.2, [(sheet, 0.95)])
        let detection = try #require(ScanCaptureMode.document.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: picture), "no sheet found")
        #expect(Self.worstMiss(found, sheet) < 0.03, "found \(found.corners)")
    }

    /// The board, not the sheet pinned to it: Whiteboard takes the largest
    /// rectangle in view.
    @Test func whiteboardModeTakesTheWholeBoard() throws {
        let board = Self.corners((0.06, 0.22), (0.94, 0.20), (0.95, 0.76), (0.05, 0.78))
        let pinned = Self.corners((0.40, 0.34), (0.62, 0.34), (0.62, 0.62), (0.40, 0.62))
        let picture = Self.scene(width: 1600, height: 1200, ground: 0.45, [(board, 0.93), (pinned, 0.70)])
        let detection = try #require(ScanCaptureMode.whiteboard.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: picture), "no board found")
        #expect(Self.worstMiss(found, board) < 0.03, "found \(found.corners)")
    }

    /// From the side of a room a board's corners are far from square.
    @Test func aBoardSeenFromTheSideIsFound() throws {
        let board = Self.corners((0.10, 0.30), (0.92, 0.12), (0.92, 0.88), (0.10, 0.70))
        let picture = Self.scene(width: 1600, height: 1200, ground: 0.4, [(board, 0.92)])
        let detection = try #require(ScanCaptureMode.whiteboard.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: picture), "no board found")
        #expect(Self.worstMiss(found, board) < 0.03, "found \(found.corners)")
    }

    /// A card held away from the camera, with a sheet of paper lying behind it.
    @Test func cardModeTakesTheCardAndNotThePaperBesideIt() throws {
        // 3:4 picture. Card: 0.36 of the width by 0.170 of the height is 1.08 by 0.68, short side 0.63 of long.
        let card = Self.corners((0.55, 0.70), (0.91, 0.70), (0.91, 0.87), (0.55, 0.87))
        // Sheet: 0.42 of the width by 0.445 of the height is 1.26 by 1.78, short side 0.707 of long.
        let sheet = Self.corners((0.06, 0.08), (0.48, 0.08), (0.48, 0.525), (0.06, 0.525))
        let picture = Self.scene(width: 1200, height: 1600, ground: 0.25, [(sheet, 0.95), (card, 0.80)])
        let detection = try #require(ScanCaptureMode.card.detection)
        let found = try #require(ScanEdgeDetector.detect(detection, in: picture), "no card found")
        #expect(Self.worstMiss(found, card) < 0.03, "found \(found.corners)")
        #expect(abs(found.aspectRatio(imageAspect: 0.75) - 0.63) < 0.05)
    }

    @Test func anEmptyFrameHasNothingToCropTo() throws {
        let picture = Self.scene(width: 1200, height: 1600, ground: 0.5, [])
        for mode in [ScanCaptureMode.document, .whiteboard, .card] {
            let detection = try #require(mode.detection)
            #expect(ScanEdgeDetector.detect(detection, in: picture) == nil, "\(mode)")
        }
    }
}

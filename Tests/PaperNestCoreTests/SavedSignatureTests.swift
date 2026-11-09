import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Row 23. A saved signature is **a picture of a handwritten signature** — ink
/// a person drew once, kept, and placed again. It is not a cryptographic
/// signature: it proves nothing about who placed it and anyone with the file
/// can copy it out. The honest verb is *placed*.
@Suite struct SavedSignatureTests {
    private func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(tool: .pen, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), width: 2,
                  points: points.map { InkPoint(x: $0.0, y: $0.1) })
    }

    /// Drawn anywhere on a page, a signature is kept in its own unit box — so
    /// placing it later never has to remember the page it came from.
    @Test func capturingNormalisesInkIntoAUnitBox() throws {
        let drawn = [stroke([(100, 200), (300, 200), (300, 260)])]

        let signature = try #require(SavedSignature(name: "Mine", capturing: drawn))

        let xs = signature.strokes.flatMap { $0.points.map(\.x) }
        let ys = signature.strokes.flatMap { $0.points.map(\.y) }
        #expect(xs.min() == 0 && xs.max() == 1, "the longer side should run 0...1: \(xs)")
        #expect(ys.min() == 0, "y was not normalised: \(ys)")
        // 200 wide by 60 tall: the shorter side keeps its proportion rather
        // than being stretched to 1, or the signature is squared up at capture.
        #expect(abs(ys.max()! - 0.3) < 0.0001, "shape was lost at capture: \(ys.max()!)")
    }

    @Test func anEmptySignatureIsRefused() throws {
        #expect(SavedSignature(name: "Nothing", capturing: []) == nil)
        #expect(SavedSignature(name: "Nothing", capturing: [stroke([])]) == nil)
    }

    @Test func captureAndPlacementPreserveStrokeWidthAtTheOriginalSize() throws {
        let signature = try #require(SavedSignature(name: "Mine",
            capturing: [stroke([(10, 20), (210, 70)])]))
        let original = signature.placed(in: .exact(x: 0, y: 0, width: 1, height: 1),
                                        on: CGSize(width: 200, height: 50))
        let doubled = signature.placed(in: .exact(x: 0, y: 0, width: 1, height: 1),
                                       on: CGSize(width: 400, height: 100))
        #expect(abs(try #require(original.first).width - 2) < 0.0001)
        #expect(abs(try #require(doubled.first).width - 4) < 0.0001)
    }

    @Test func capturedDotFitsItsDiameterInsideTheTarget() throws {
        let signature = try #require(SavedSignature(name: "Dot", capturing: [stroke([(12, 18)])]))
        let placed = signature.placed(in: .exact(x: 0, y: 0, width: 1, height: 1),
                                      on: CGSize(width: 40, height: 20))
        let dot = try #require(placed.first)
        #expect(dot.width == 20)
        #expect(dot.points.first?.x == 20 && dot.points.first?.y == 10)
    }

    @Test func flatSignatureUsesItsNonzeroAxisToFit() throws {
        let horizontal = try #require(SavedSignature(name: "Line",
            capturing: [stroke([(10, 20), (210, 20)])]))
        let vertical = try #require(SavedSignature(name: "Line",
            capturing: [stroke([(10, 20), (10, 220)])]))
        let placedHorizontal = try #require(horizontal.placed(in: .full,
            on: CGSize(width: 200, height: 50)).first)
        let placedVertical = try #require(vertical.placed(in: .full,
            on: CGSize(width: 50, height: 200)).first)
        #expect(placedHorizontal.points.last?.x == 200)
        #expect(placedVertical.points.last?.y == 200)
        #expect(abs(placedHorizontal.width - 2) < 0.0001)
        #expect(abs(placedVertical.width - 2) < 0.0001)
    }

    @Test func placingPutsEveryPointInsideTheTarget() throws {
        let signature = try #require(SavedSignature(name: "Mine",
                                                    capturing: [stroke([(0, 0), (200, 0), (200, 50)])]))
        let page = CGSize(width: 612, height: 792)
        let target = NormalizedRect.exact(x: 0.5, y: 0.8, width: 0.4, height: 0.1)

        let placed = signature.placed(in: target, on: page)

        let minX = target.x * page.width, maxX = (target.x + target.width) * page.width
        let minY = target.y * page.height, maxY = (target.y + target.height) * page.height
        for point in placed.flatMap(\.points) {
            #expect(point.x >= minX - 0.001 && point.x <= maxX + 0.001, "x \(point.x) outside")
            #expect(point.y >= minY - 0.001 && point.y <= maxY + 0.001, "y \(point.y) outside")
        }
    }

    /// A signature stretched to fill a box is a different shape from the one
    /// the person drew — a visual lie about their hand.
    @Test func aspectRatioSurvivesPlacement() throws {
        // Four times as wide as it is tall.
        let signature = try #require(SavedSignature(name: "Wide",
                                                    capturing: [stroke([(0, 0), (400, 0), (400, 100)])]))
        let page = CGSize(width: 1000, height: 1000)
        // A square target: it must letterbox, not stretch.
        let placed = signature.placed(in: .exact(x: 0, y: 0, width: 0.5, height: 0.5), on: page)

        let xs = placed.flatMap { $0.points.map(\.x) }
        let ys = placed.flatMap { $0.points.map(\.y) }
        let width = xs.max()! - xs.min()!
        let height = ys.max()! - ys.min()!
        #expect(abs(width / height - 4) < 0.01, "aspect became \(width / height), not 4")
    }

    @Test func theSamePlacementOnTwoPageSizesIsProportionallyEqual() throws {
        let signature = try #require(SavedSignature(name: "Mine",
                                                    capturing: [stroke([(0, 0), (100, 0), (100, 40)])]))
        let target = NormalizedRect.exact(x: 0.1, y: 0.1, width: 0.3, height: 0.2)

        let small = signature.placed(in: target, on: CGSize(width: 500, height: 500))
        let large = signature.placed(in: target, on: CGSize(width: 1000, height: 1000))

        for (a, b) in zip(small.flatMap(\.points), large.flatMap(\.points)) {
            #expect(abs(a.x * 2 - b.x) < 0.001, "\(a.x) * 2 != \(b.x)")
            #expect(abs(a.y * 2 - b.y) < 0.001)
        }
    }

    /// Placing never consumes the signature: it can be used again, unchanged.
    @Test func placingDoesNotChangeTheStoredSignature() throws {
        let signature = try #require(SavedSignature(name: "Mine",
                                                    capturing: [stroke([(0, 0), (100, 0)])]))
        let before = signature.strokes

        _ = signature.placed(in: .exact(x: 0, y: 0, width: 1, height: 1), on: CGSize(width: 600, height: 600))

        #expect(signature.strokes == before)
    }
}

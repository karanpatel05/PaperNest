import CoreGraphics
import Testing
@testable import PaperNestCore

@Suite struct ShapeAnnotationTests {
    @Test(arguments: ShapeAnnotation.allCases) func geometryStaysInsideCroppedRotatedPage(_ kind: ShapeAnnotation) throws {
        for rotation in [QuarterTurns.none, .clockwise90, .half, .clockwise270] {
            let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800),
                                        crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6), rotation: rotation)
            for reversed in [false, true] {
                let a = CGPoint(x: reversed ? 1 : 0, y: reversed ? 1 : 0)
                let b = CGPoint(x: reversed ? 0 : 1, y: reversed ? 0 : 1)
                let stroke = try kind.stroke(from: a, to: b, geometry: geometry, color: .black, width: 4)
                #expect(stroke.tool == .pen)
                #expect(stroke.points.count >= 2)
                for point in stroke.points {
                    let p = CGPoint(x: point.x, y: point.y).applying(geometry.sourceToPage)
                    #expect(p.x >= 1.99 && p.y >= 1.99)
                    #expect(p.x <= geometry.pageSize.width - 1.99 && p.y <= geometry.pageSize.height - 1.99)
                }
                if kind == .rectangle || kind == .ellipse {
                    #expect(stroke.points.first?.x == stroke.points.last?.x)
                    #expect(stroke.points.first?.y == stroke.points.last?.y)
                }
            }
        }
    }

    @Test func stampPresetsAreDistinctAndKeepTheirCorners() throws {
        #expect(ShapeAnnotation.stamps == [.checkmark, .cross, .star])
        #expect(ShapeAnnotation.shapes == [.rectangle, .ellipse, .line, .arrow])
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        for kind in ShapeAnnotation.stamps {
            let ink = try kind.stroke(from: .init(x: 0.2, y: 0.2), to: .init(x: 0.8, y: 0.8), geometry: geometry, color: .black, width: 4)
            #expect(ink.points.count >= 9)
            #expect(ink.points[0] == ink.points[1] && ink.points[1] == ink.points[2])
            #expect(throws: ShapeAnnotationError.self) {
                try kind.stroke(from: .init(x: 0.5, y: 0.2), to: .init(x: 0.5, y: 0.8), geometry: geometry, color: .black, width: 4)
            }
        }
        let check = try ShapeAnnotation.checkmark.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: geometry, color: .black, width: 4)
        #expect(check.points[3].y > check.points[0].y)
        #expect(check.points.last!.y < check.points[3].y)
        let star = try ShapeAnnotation.star.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: geometry, color: .black, width: 4)
        #expect(star.points.first == star.points.last)
    }

    @Test func invalidOrDegenerateGeometryIsRejected() {
        let g = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        for end in [CGPoint.zero, CGPoint(x: .nan, y: 0.5), CGPoint(x: 2, y: 0.5)] {
            #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.rectangle.stroke(from: .zero, to: end, geometry: g, color: .black, width: 2) }
        }
        #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.line.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: g, color: .black, width: 0) }
        #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.arrow.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: g, color: .init(red: 0, green: 0, blue: 0, alpha: 0), width: 2) }
    }

    /// The Shapes tool's grid. The two older lists are pinned above and must
    /// not change when this one grows.
    @Test func theLibraryOffersEveryShapeOnceAndNoStampButTheStar() {
        #expect(ShapeAnnotation.library == [.line, .arrow, .rectangle, .roundedRectangle, .ellipse, .triangle,
                                            .diamond, .pentagon, .hexagon, .star, .speechBubble])
        #expect(Set(ShapeAnnotation.library).count == ShapeAnnotation.library.count)
    }

    @Test(arguments: ShapeAnnotation.library) func closedShapesEndWhereTheyBegin(_ kind: ShapeAnnotation) throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let stroke = try kind.stroke(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.7, y: 0.6), geometry: geometry,
                                     color: .black, width: 2)
        let first = try #require(stroke.points.first), last = try #require(stroke.points.last)
        #expect(stroke.points.count >= 2)
        if kind.isClosed {
            #expect(abs(first.x - last.x) < 0.001 && abs(first.y - last.y) < 0.001, "\(kind)")
        }
        // Every point is inside the box that was dragged out.
        let box = CGRect(x: 120, y: 160, width: 300, height: 320).insetBy(dx: -0.01, dy: -0.01)
        #expect(stroke.points.allSatisfy { box.contains(CGPoint(x: $0.x, y: $0.y)) }, "\(kind)")
    }

    @Test func aPolygonHasTheNumberOfCornersItsNamePromises() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        for (kind, corners) in [(ShapeAnnotation.triangle, 3), (.diamond, 4), (.pentagon, 5), (.hexagon, 6)] {
            let stroke = try kind.stroke(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.7, y: 0.6), geometry: geometry,
                                         color: .black, width: 2)
            // Each corner is written three times and the first is repeated to close.
            #expect(stroke.points.count == (corners + 1) * 3, "\(kind)")
            let distinct = Set(stroke.points.map { "\(Int(($0.x * 100).rounded())),\(Int(($0.y * 100).rounded()))" })
            #expect(distinct.count == corners, "\(kind)")
        }
    }

    @Test(arguments: ShapeAnnotation.allCases) func everyShapeHasAPictureForItsButton(_ kind: ShapeAnnotation) {
        let rect = CGRect(x: 4, y: 4, width: 30, height: 30)
        let outline = kind.previewOutline(in: rect)
        #expect(outline.count >= 2, "\(kind)")
        #expect(outline.allSatisfy { rect.insetBy(dx: -0.01, dy: -0.01).contains($0) }, "\(kind)")
    }
}

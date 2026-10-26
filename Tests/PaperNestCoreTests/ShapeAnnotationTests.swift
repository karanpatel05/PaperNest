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

    @Test func invalidOrDegenerateGeometryIsRejected() {
        let g = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        for end in [CGPoint.zero, CGPoint(x: .nan, y: 0.5), CGPoint(x: 2, y: 0.5)] {
            #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.rectangle.stroke(from: .zero, to: end, geometry: g, color: .black, width: 2) }
        }
        #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.line.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: g, color: .black, width: 0) }
        #expect(throws: ShapeAnnotationError.self) { try ShapeAnnotation.arrow.stroke(from: .zero, to: .init(x: 1, y: 1), geometry: g, color: .init(red: 0, green: 0, blue: 0, alpha: 0), width: 2) }
    }
}

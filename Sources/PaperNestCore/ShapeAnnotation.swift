import CoreGraphics
import Foundation

public enum ShapeAnnotationError: Error, Equatable, Sendable { case invalidGeometry, invalidStyle }

/// Outlined shapes saved as ordinary editable ink. Input endpoints are
/// normalized to the displayed (cropped/rotated) page, not the source image.
public enum ShapeAnnotation: String, CaseIterable, Sendable {
    case rectangle, ellipse, line, arrow, checkmark, cross, star

    public static let shapes: [Self] = [.rectangle, .ellipse, .line, .arrow]
    public static let stamps: [Self] = [.checkmark, .cross, .star]
    public var isStamp: Bool { Self.stamps.contains(self) }

    public func stroke(from start: CGPoint, to end: CGPoint, geometry: PageGeometry,
                       color: RGBAColor, width: Double) throws -> InkStroke {
        guard color.isVisibleInkColor, width.isFinite, width > 0, width <= 20 else { throw ShapeAnnotationError.invalidStyle }
        let size = geometry.pageSize
        guard size.width.isFinite, size.height.isFinite, size.width > width * 2, size.height > width * 2,
              [start.x, start.y, end.x, end.y].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ShapeAnnotationError.invalidGeometry
        }
        let inset = width / 2
        func bounded(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, inset), size.width - inset), y: min(max(p.y, inset), size.height - inset))
        }
        let a = bounded(CGPoint(x: start.x * size.width, y: start.y * size.height))
        let b = bounded(CGPoint(x: end.x * size.width, y: end.y * size.height))
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length >= max(width * 2, 1) else { throw ShapeAnnotationError.invalidGeometry }
        var points: [CGPoint]
        switch self {
        case .line: points = [a, b]
        case .arrow:
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
            let head = min(max(width * 4, 10), length / 3)
            points = [a, b,
                      bounded(CGPoint(x: b.x - ux * head - uy * head / 2, y: b.y - uy * head + ux * head / 2)), b,
                      bounded(CGPoint(x: b.x - ux * head + uy * head / 2, y: b.y - uy * head - ux * head / 2))]
        case .checkmark, .cross, .star:
            guard rect.width >= width * 2, rect.height >= width * 2 else { throw ShapeAnnotationError.invalidGeometry }
            func at(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            switch self {
            case .checkmark:
                points = [at(0, 0.5), at(0.35, 1), at(1, 0)]
            case .cross:
                points = [at(0, 0), at(1, 1), at(0.5, 0.5), at(1, 0), at(0, 1)]
            default:
                points = (0..<10).map { index in
                    let angle = Double(index) * .pi / 5 - .pi / 2
                    let radius = index.isMultiple(of: 2) ? 0.5 : 0.2
                    return at(0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius)
                }
                points.append(points[0])
            }
        case .rectangle, .ellipse:
            guard rect.width >= width * 2, rect.height >= width * 2 else { throw ShapeAnnotationError.invalidGeometry }
            if self == .rectangle {
                points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            } else {
                points = (0..<96).map { index in
                    let angle = Double(index) * 2 * .pi / 96
                    return bounded(CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2))
                }
            }
            points.append(points[0])
        }
        // PencilKit treats stored points as cubic B-spline control points.
        // Repeated vertices preserve sharp corners and arrowhead reversals;
        // the ordinary ink renderer sees the same polyline with zero-length joins.
        if self == .rectangle || self == .arrow || isStamp {
            points = points.flatMap { [$0, $0, $0] }
        }
        return InkStroke(tool: .pen, color: color, width: width, points: points.map {
            let source = $0.applying(geometry.pageToSource)
            return InkPoint(x: source.x, y: source.y)
        })
    }
}

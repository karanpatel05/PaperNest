import CoreGraphics
import Foundation

public enum ShapeAnnotationError: Error, Equatable, Sendable { case invalidGeometry, invalidStyle }

/// Outlined shapes saved as ordinary editable ink. Input endpoints are
/// normalized to the displayed (cropped/rotated) page, not the source image.
public enum ShapeAnnotation: String, CaseIterable, Sendable {
    case rectangle, ellipse, line, arrow, checkmark, cross, star
    case roundedRectangle, triangle, diamond, pentagon, hexagon, speechBubble

    public static let shapes: [Self] = [.rectangle, .ellipse, .line, .arrow]
    public static let stamps: [Self] = [.checkmark, .cross, .star]
    /// Everything the notes editor's Shapes tool offers, in the order its
    /// grid shows them. `shapes` and `stamps` stay as they were: the older
    /// placement sheet is built from those two and must not grow by accident.
    public static let library: [Self] = [.line, .arrow, .rectangle, .roundedRectangle, .ellipse, .triangle,
                                         .diamond, .pentagon, .hexagon, .star, .speechBubble]
    public var isStamp: Bool { Self.stamps.contains(self) }

    /// Whether the outline comes back to where it started. A line and an
    /// arrow do not, and are sized by their length rather than by a box.
    public var isClosed: Bool {
        switch self {
        case .line, .arrow, .checkmark, .cross: false
        default: true
        }
    }

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
        case .roundedRectangle, .triangle, .diamond, .pentagon, .hexagon, .speechBubble:
            guard rect.width >= width * 2, rect.height >= width * 2 else { throw ShapeAnnotationError.invalidGeometry }
            return InkStroke(tool: .pen, color: color, width: width,
                             points: Self.outline(of: self, in: rect).map {
                let source = bounded($0).applying(geometry.pageToSource)
                return InkPoint(x: source.x, y: source.y)
            })
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
    /// The shape drawn to fill `rect`, as one polyline, for a picture of it
    /// on a button. Not what is saved — `stroke(from:to:geometry:color:width:)`
    /// is, with the page's bounds and line width taken into account — but the
    /// same geometry, so the button shows the shape the page will get.
    public func previewOutline(in rect: CGRect) -> [CGPoint] {
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        switch self {
        case .line: return [at(0, 1), at(1, 0)]
        case .arrow: return [at(0, 1), at(1, 0), at(0.62, 0.06), at(1, 0), at(0.94, 0.38)]
        case .rectangle: return [at(0, 0.12), at(1, 0.12), at(1, 0.88), at(0, 0.88), at(0, 0.12)]
        case .ellipse:
            return (0...48).map { index in
                let angle = Double(index) * 2 * .pi / 48
                return at(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5)
            }
        case .checkmark: return [at(0, 0.5), at(0.35, 1), at(1, 0)]
        case .cross: return [at(0, 0), at(1, 1), at(0.5, 0.5), at(1, 0), at(0, 1)]
        case .star:
            var points = (0..<10).map { index -> CGPoint in
                let angle = Double(index) * .pi / 5 - .pi / 2
                let radius = index.isMultiple(of: 2) ? 0.5 : 0.2
                return at(0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius)
            }
            points.append(points[0])
            return points
        case .roundedRectangle, .speechBubble:
            return Self.outline(of: self, in: rect.insetBy(dx: 0, dy: rect.height * 0.1))
        case .triangle, .diamond, .pentagon, .hexagon:
            return Self.outline(of: self, in: rect)
        }
    }

    /// The outline of one of the polygonal or rounded shapes inside `rect`,
    /// in page points, closed.
    ///
    /// Sharp corners are written three times and curves once. PencilKit reads
    /// stored points as spline controls, so a corner written once is rounded
    /// off on iPad; the ordinary renderer sees the repeats as zero-length
    /// joins and draws the same polygon either way.
    static func outline(of kind: ShapeAnnotation, in rect: CGRect) -> [CGPoint] {
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func sharp(_ corners: [CGPoint]) -> [CGPoint] {
            (corners + [corners[0]]).flatMap { [$0, $0, $0] }
        }
        func regular(_ sides: Int) -> [CGPoint] {
            sharp((0..<sides).map { index in
                let angle = Double(index) * 2 * .pi / Double(sides) - .pi / 2
                return at(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5)
            })
        }
        /// A quarter turn round `center`, starting at `from` radians.
        func arc(_ center: CGPoint, _ radius: Double, from: Double) -> [CGPoint] {
            (0...8).map { step in
                let angle = from + Double(step) / 8 * .pi / 2
                return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }
        }
        func rounded(_ body: CGRect, tail: [CGPoint] = []) -> [CGPoint] {
            let radius = min(body.width, body.height) * 0.22
            var points = arc(CGPoint(x: body.maxX - radius, y: body.minY + radius), radius, from: -.pi / 2)
            points += arc(CGPoint(x: body.maxX - radius, y: body.maxY - radius), radius, from: 0)
            points += tail.flatMap { [$0, $0, $0] }
            points += arc(CGPoint(x: body.minX + radius, y: body.maxY - radius), radius, from: .pi / 2)
            points += arc(CGPoint(x: body.minX + radius, y: body.minY + radius), radius, from: .pi)
            points.append(points[0])
            return points
        }
        switch kind {
        case .triangle: return sharp([at(0.5, 0), at(1, 1), at(0, 1)])
        case .diamond: return sharp([at(0.5, 0), at(1, 0.5), at(0.5, 1), at(0, 0.5)])
        case .pentagon: return regular(5)
        case .hexagon: return regular(6)
        case .roundedRectangle: return rounded(rect)
        case .speechBubble:
            // The body takes the top four fifths; the tail hangs from the
            // bottom edge, a third of the way along from the left.
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.78)
            return rounded(body, tail: [CGPoint(x: rect.minX + rect.width * 0.46, y: body.maxY),
                                        CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY),
                                        CGPoint(x: rect.minX + rect.width * 0.3, y: body.maxY)])
        default: return []
        }
    }
}

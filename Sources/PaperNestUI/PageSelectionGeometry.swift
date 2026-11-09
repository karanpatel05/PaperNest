import CoreGraphics
import PaperNestCore
import PaperNestRender

/// Transient selection geometry. Stored objects remain in PageGeometry source space.
enum PageSelectionMode: String, CaseIterable { case freehand, rectangle }

/// A freehand contour remains in source space relative to the selected group.
/// Reading the group's current bounds makes it follow movement and undo/redo,
/// while the current PageGeometry mapping keeps zoom and rotation accurate.
struct PageSelectionContour {
    private let relativePoints: [CGPoint]

    init(viewPoints: [CGPoint], selectionBounds: CGRect, sourceToView: CGAffineTransform) {
        let inverse = sourceToView.inverted()
        relativePoints = viewPoints.map {
            let source = $0.applying(inverse)
            return CGPoint(x: source.x - selectionBounds.minX, y: source.y - selectionBounds.minY)
        }
    }

    func viewPoints(selectionBounds: CGRect, sourceToView: CGAffineTransform) -> [CGPoint] {
        relativePoints.map {
            CGPoint(x: $0.x + selectionBounds.minX, y: $0.y + selectionBounds.minY).applying(sourceToView)
        }
    }

    func contains(_ point: CGPoint, selectionBounds: CGRect, sourceToView: CGAffineTransform) -> Bool {
        PageSelectionGeometry.contains(point, polygon: viewPoints(selectionBounds: selectionBounds, sourceToView: sourceToView), tolerance: 3)
    }
}

enum PageSelectionGeometry {
    static func bounds(of object: PageObject) -> CGRect? {
        switch object.payload {
        case .text(let box): return box.frame
        case .image(let image): return image.frame
        case .comment: return nil
        case .ink(let ink):
            guard let first = ink.points.first else { return nil }
            var rect = CGRect(x: first.x, y: first.y, width: 0, height: 0)
            for point in ink.points.dropFirst() { rect = rect.union(CGRect(x: point.x, y: point.y, width: 0, height: 0)) }
            let reach = ink.width * (ink.points.map(\.widthScale).max() ?? 1) / 2
            return rect.insetBy(dx: -reach, dy: -reach)
        }
    }

    static func bounds(of objects: [PageObject]) -> CGRect? {
        objects.compactMap { bounds(of: $0) }.reduce(nil) { accumulated, next in
            accumulated.map { $0.union(next) } ?? next
        }
    }

    static func loop(from points: [CGPoint], mode: PageSelectionMode) -> [CGPoint] {
        guard mode == .rectangle, let first = points.first, let last = points.last else { return points }
        return [first, CGPoint(x: last.x, y: first.y), last, CGPoint(x: first.x, y: last.y)]
    }

    static func selection(from points: [CGPoint], mode: PageSelectionMode,
                          objects: [PageObject], sourceToView: CGAffineTransform) -> [PageObject] {
        guard let first = points.first else { return [] }
        if points.allSatisfy({ hypot($0.x - first.x, $0.y - first.y) <= 3 }) {
            return hit(at: first, objects: objects, sourceToView: sourceToView).map { [$0] } ?? []
        }
        let polygon = loop(from: points, mode: mode)
        guard polygon.count >= 3, let second = polygon.first(where: { $0 != first }),
              polygon.contains(where: { abs((second.x - first.x) * ($0.y - first.y) - (second.y - first.y) * ($0.x - first.x)) > 0.001 }) else { return [] }
        return objects.filter { object in
            let samples: [CGPoint]
            switch object.payload {
            case .ink(let ink): samples = ink.points.map { CGPoint(x: $0.x, y: $0.y) }
            case .text(let box):
                // Select the whole editable object when the loop contains a
                // visible letter, rather than requiring its invisible margins.
                return PageRenderer.textSelectionRects(box).contains { rect in
                    contains(CGPoint(x: rect.midX, y: rect.midY).applying(sourceToView), polygon: polygon, tolerance: 3)
                }
            case .image:
                guard let rect = bounds(of: object) else { return false }
                samples = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                           CGPoint(x: rect.midX, y: rect.midY)]
            case .comment: return false
            }
            return !samples.isEmpty && samples.allSatisfy { contains($0.applying(sourceToView), polygon: polygon, tolerance: 3) }
        }
    }

    static func hit(at point: CGPoint, objects: [PageObject], sourceToView: CGAffineTransform) -> PageObject? {
        let scale = sqrt(abs(sourceToView.a * sourceToView.d - sourceToView.b * sourceToView.c))
        return objects.sorted { $0.zKey > $1.zKey }.first { object in
            switch object.payload {
            case .ink(let ink):
                let path = ink.points.map { CGPoint(x: $0.x, y: $0.y).applying(sourceToView) }
                let reach = max(ink.width * scale / 2, 1) + 6
                guard let first = path.first else { return false }
                if path.count == 1 { return hypot(first.x - point.x, first.y - point.y) <= reach }
                return zip(path, path.dropFirst()).contains { distance(point, $0, $1) <= reach }
            case .text, .image: return bounds(of: object)?.applying(sourceToView).insetBy(dx: -3, dy: -3).contains(point) ?? false
            case .comment: return false
            }
        }
    }

    static func viewDelta(_ delta: CGPoint, sourceToView: CGAffineTransform) -> CGSize {
        let end = delta.applying(sourceToView), start = CGPoint.zero.applying(sourceToView)
        return CGSize(width: end.x - start.x, height: end.y - start.y)
    }

    static func dragTranslation(of bounds: CGRect, by viewDelta: CGSize,
                                sourceToView: CGAffineTransform, crop: CGRect) -> CGPoint {
        // A click (including touch jitter) must never reposition a cropped object.
        guard hypot(viewDelta.width, viewDelta.height) > 3 else { return .zero }
        // Already clipped content can move back into view without snapping on
        // the other axis or being pushed farther beyond its current boundary.
        return DocumentModel.clampedTranslation(of: bounds,
            by: DocumentModel.sourceDelta(of: viewDelta, sourceToView: sourceToView),
            within: crop.union(bounds))
    }

    fileprivate static func contains(_ point: CGPoint, polygon: [CGPoint], tolerance: CGFloat) -> Bool {
        guard polygon.count >= 3 else { return false }
        var previous = polygon.count - 1, inside = false
        for current in polygon.indices {
            let a = polygon[previous], b = polygon[current]
            if distance(point, a, b) <= tolerance { return true }
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            previous = current
        }
        return inside
    }

    private static func distance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared))
        return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
    }
}

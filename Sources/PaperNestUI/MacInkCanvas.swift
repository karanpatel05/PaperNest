#if os(macOS)
import CoreGraphics
import PaperNestCore
import SwiftUI

/// Drawing on a page with a mouse or trackpad.
///
/// macOS has no PencilKit, so this is the Mac's own canvas rather than a
/// wrapper around Apple's. It is deliberately small: collect the points of one
/// drag, show them while the drag is happening, and save a single `InkStroke`
/// when it ends. The iOS canvas reconciles PencilKit's whole drawing against
/// what is stored and needs to; appending one stroke at a time does not.
///
/// Points are captured in view space and converted with the **inverse of the
/// transform the page was drawn with**, so a stroke lands where the pointer
/// was no matter the zoom, and is stored in the same upright source space as
/// everything else on the page.
///
/// **No pressure.** A drag gives position only, so every stroke has one width.
/// On iOS, Apple Pencil varies it. That difference is real and is not hidden.
struct MacInkCanvas: View {
    let model: DocumentModel
    let page: Page
    /// Source points to points in this view, the mapping the page was drawn with.
    let sourceToView: CGAffineTransform
    let tool: MacMarkupTool
    let color: RGBAColor
    let width: Double
    let undoManager: UndoManager?

    @State private var points: [CGPoint] = []

    private var scale: CGFloat {
        let determinant = sourceToView.a * sourceToView.d - sourceToView.b * sourceToView.c
        return max(sqrt(abs(determinant)), 0.0001)
    }

    private var previewColor: Color {
        guard tool != .eraser else { return Color.secondary.opacity(0.5) }
        let opacity = tool == .highlighter ? InkStroke.highlighterOpacity : 1
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue,
                     opacity: color.alpha * opacity)
    }

    /// How wide the eraser reaches, in source points. Generous compared with a
    /// pen, because aiming a mouse at a thin line is harder than aiming a
    /// finger, and an eraser that misses feels broken.
    static let eraserRadius: Double = 8

    var body: some View {
        Canvas { context, _ in
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            // A click with no movement is a dot, as it is when drawn.
            if points.count == 1 { path.addLine(to: first) }
            context.stroke(path, with: .color(previewColor),
                           style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { points.append($0.location) }
                .onEnded { value in
                    if points.isEmpty { points = [value.location] }
                    commit()
                }
        )
        .accessibilityIdentifier("mac-ink-canvas")
        .accessibilityLabel(L10n.markup)
    }

    private func commit() {
        let captured = points
        points = []
        guard !captured.isEmpty else { return }
        if tool == .eraser {
            let viewToSource = sourceToView.inverted()
            let path = captured.map { $0.applying(viewToSource) }
            let hit = Self.strokesHit(by: path, in: model.selectedPageObjects.filter { $0.pageID == page.id },
                                      radius: Self.eraserRadius)
            guard !hit.isEmpty else { return }
            Task { try? await model.eraseInk(hit, on: page, undoManager: undoManager) }
            return
        }
        guard let inkTool = tool.ink,
              let stroke = Self.stroke(from: captured, sourceToView: sourceToView,
                                       tool: inkTool, color: color, width: width) else { return }
        Task { try? await model.addInkStroke(stroke, to: page, undoManager: undoManager) }
    }

    /// The ink objects an eraser drag touched.
    ///
    /// **Whole strokes.** A stroke the eraser crosses goes entirely, rather
    /// than being split where it was crossed. That is a real limitation and a
    /// deliberate one: splitting means rewriting a stroke's points and
    /// deciding what happens to the halves, and a whole-stroke eraser is a
    /// behaviour people already know. It is said plainly in TEST_MATRIX rather
    /// than left to be discovered.
    ///
    /// All distances are in source points, so the eraser reaches the same
    /// distance on the page whatever the zoom.
    nonisolated static func strokesHit(by eraserPath: [CGPoint], in objects: [PageObject],
                                       radius: Double) -> [PageObject] {
        guard !eraserPath.isEmpty else { return [] }
        return objects.filter { object in
            guard case .ink(let stroke) = object.payload, !stroke.points.isEmpty else { return false }
            let reach = radius + stroke.width / 2
            let strokePoints = stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
            // Both directions, because either path can be sampled sparsely:
            // checking only the recorded points misses the middle of a long
            // straight stroke, and checking only the stroke's points misses a
            // dot that falls between two samples of a fast eraser drag. The
            // first of those was a real bug caught by a test.
            return Self.anyPoint(strokePoints, within: reach, ofSegmentsOf: eraserPath)
                || Self.anyPoint(eraserPath, within: reach, ofSegmentsOf: strokePoints)
        }
    }

    private nonisolated static func anyPoint(_ points: [CGPoint], within reach: Double,
                                             ofSegmentsOf path: [CGPoint]) -> Bool {
        guard !path.isEmpty else { return false }
        return points.contains { point in
            if path.count == 1 { return hypot(point.x - path[0].x, point.y - path[0].y) <= reach }
            return zip(path, path.dropFirst()).contains { start, end in
                distance(from: point, toSegmentFrom: start, to: end) <= reach
            }
        }
    }

    /// Shortest distance from a point to a line segment, clamped to the
    /// segment's ends rather than its infinite line.
    private nonisolated static func distance(from point: CGPoint, toSegmentFrom a: CGPoint,
                                             to b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// One drag's points as a stroke in source space.
    ///
    /// Returns nil for nothing at all; a single point is kept, because a dot is
    /// something someone meant to draw.
    nonisolated static func stroke(from viewPoints: [CGPoint], sourceToView: CGAffineTransform,
                       tool: InkStroke.Tool, color: RGBAColor, width: Double) -> InkStroke? {
        guard !viewPoints.isEmpty else { return nil }
        let viewToSource = sourceToView.inverted()
        let points = viewPoints.map { point -> InkPoint in
            let inSource = point.applying(viewToSource)
            return InkPoint(x: inSource.x, y: inSource.y)
        }
        return InkStroke(tool: tool, color: color, width: width, points: points)
    }
}
#endif

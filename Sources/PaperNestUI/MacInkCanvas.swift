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

    /// The drag in progress, in view points.
    @State private var points: [CGPoint] = []
    /// What the lasso has hold of, by **id**: the strokes themselves are read
    /// back from the model when they are needed, so an undo between selecting
    /// and dragging cannot leave this holding points that are no longer there.
    @State private var selection: [PageObjectID] = []
    /// Set on the first event of a drag and not revisited, so a drag that
    /// started on the selection goes on moving it even once the pointer
    /// leaves.
    @State private var isMovingSelection = false
    @State private var moveTranslation: CGSize = .zero

    private var scale: CGFloat {
        let determinant = sourceToView.a * sourceToView.d - sourceToView.b * sourceToView.c
        return max(sqrt(abs(determinant)), 0.0001)
    }

    private var previewColor: Color {
        guard tool.ink != nil else { return Color.secondary.opacity(0.5) }
        let opacity = tool == .highlighter ? InkStroke.highlighterOpacity : 1
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue,
                     opacity: color.alpha * opacity)
    }

    /// How wide the eraser reaches, in source points. Generous compared with a
    /// pen, because aiming a mouse at a thin line is harder than aiming a
    /// finger, and an eraser that misses feels broken.
    static let eraserRadius: Double = 8

    /// How far outside its own box a selection can be grabbed, in view points.
    /// A dashed line is thin to aim at, and the strokes inside it are thinner.
    static let selectionGrip: CGFloat = 6

    /// This page's objects. Right after a page switch the previous page's are
    /// still loaded, so the filter is not decoration.
    private var pageObjects: [PageObject] {
        model.selectedPageObjects.filter { $0.pageID == page.id }
    }

    /// The lassoed strokes as they are **now**, not as they were when lassoed.
    private var selectedObjects: [PageObject] {
        let wanted = Set(selection)
        return pageObjects.filter { wanted.contains($0.id) }
    }

    var body: some View {
        Canvas { context, _ in
            paintSelection(&context)
            paintDrag(&context)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if points.isEmpty, !isMovingSelection {
                        isMovingSelection = tool == .lasso && startsOnSelection(value.startLocation)
                    }
                    if isMovingSelection {
                        moveTranslation = value.translation
                    } else {
                        points.append(value.location)
                    }
                }
                .onEnded { value in
                    if isMovingSelection {
                        isMovingSelection = false
                        moveTranslation = .zero
                        commitMove(value.translation)
                        return
                    }
                    if points.isEmpty { points = [value.location] }
                    commit()
                }
        )
        // A selection belongs to one tool on one page. Leaving it up after a
        // switch would show a dashed box round strokes the next drag cannot
        // move.
        .onChange(of: tool) { _, _ in clearSelection() }
        .onChange(of: page.id) { _, _ in clearSelection() }
        .accessibilityIdentifier("mac-ink-canvas")
        .accessibilityLabel(L10n.markup)
        .accessibilityValue(selection.isEmpty ? "" : L10n.inkSelectionCount(selection.count))
    }

    private func clearSelection() {
        selection = []
        isMovingSelection = false
        moveTranslation = .zero
    }

    /// The dashed box round the lassoed strokes, and while they are being
    /// dragged, where they are going.
    private func paintSelection(_ context: inout GraphicsContext) {
        let objects = selectedObjects
        guard let bounds = Self.selectionBounds(of: objects) else { return }
        let box = bounds.applying(sourceToView)
            .offsetBy(dx: moveTranslation.width, dy: moveTranslation.height)
        context.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        // The page underneath goes on drawing the ink where it still is until
        // the move is committed, so during the drag both are on screen: the
        // original and this outline of where it will land.
        guard isMovingSelection else { return }
        for object in objects {
            guard case .ink(let stroke) = object.payload, let first = stroke.points.first else { continue }
            var path = Path()
            path.move(to: CGPoint(x: first.x, y: first.y).applying(sourceToView))
            for point in stroke.points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y).applying(sourceToView))
            }
            if stroke.points.count == 1 { path.addLine(to: path.currentPoint ?? .zero) }
            context.stroke(
                path.offsetBy(dx: moveTranslation.width, dy: moveTranslation.height),
                with: .color(Theme.accent.opacity(0.7)),
                style: StrokeStyle(lineWidth: max(stroke.width * scale, 1), lineCap: .round, lineJoin: .round))
        }
    }

    /// The drag in progress: the stroke being drawn, or the loop being closed.
    private func paintDrag(_ context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if tool == .lasso {
            // Shown closed, because that is how it is measured.
            path.closeSubpath()
            context.stroke(path, with: .color(Theme.accent),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            return
        }
        // A click with no movement is a dot, as it is when drawn.
        if points.count == 1 { path.addLine(to: first) }
        context.stroke(path, with: .color(previewColor),
                       style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
    }

    private func startsOnSelection(_ location: CGPoint) -> Bool {
        guard let bounds = Self.selectionBounds(of: selectedObjects) else { return false }
        return bounds.applying(sourceToView)
            .insetBy(dx: -Self.selectionGrip, dy: -Self.selectionGrip)
            .contains(location)
    }

    private func commit() {
        let captured = points
        points = []
        guard !captured.isEmpty else { return }
        let viewToSource = sourceToView.inverted()
        switch tool {
        case .eraser:
            let path = captured.map { $0.applying(viewToSource) }
            let hit = Self.strokesHit(by: path, in: pageObjects, radius: Self.eraserRadius)
            guard !hit.isEmpty else { return }
            Task { try? await model.eraseInk(hit, on: page, undoManager: undoManager) }
        case .lasso:
            let loop = captured.map { $0.applying(viewToSource) }
            // A loop that caught nothing clears the selection, which is how a
            // click on empty page lets go of what was held.
            selection = Self.strokesEnclosed(by: loop, in: pageObjects).map(\.id)
        case .pen, .highlighter:
            guard let inkTool = tool.ink,
                  let stroke = Self.stroke(from: captured, sourceToView: sourceToView,
                                           tool: inkTool, color: color, width: width) else { return }
            Task { try? await model.addInkStroke(stroke, to: page, undoManager: undoManager) }
        }
    }

    private func commitMove(_ viewTranslation: CGSize) {
        // A click on the selection holds on to it without moving it.
        guard abs(viewTranslation.width) > 1 || abs(viewTranslation.height) > 1,
              let bounds = Self.selectionBounds(of: selectedObjects) else { return }
        let delta = DocumentModel.clampedTranslation(
            of: bounds,
            by: DocumentModel.sourceDelta(of: viewTranslation, sourceToView: sourceToView),
            within: page.sourceSize)
        let ids = selection
        Task { try? await model.moveInk(ids, on: page, by: delta, undoManager: undoManager) }
    }

    /// The ink objects a lasso loop encloses **wholly**.
    ///
    /// Every point of a stroke has to be inside, which is what drawing a
    /// circle round handwriting means, and it is what keeps a loop from
    /// dragging off the neighbouring word by its tail. The loop is closed from
    /// its last point back to its first, because a drag ends where the pointer
    /// stopped rather than where it started.
    ///
    /// Ink only: a text box or a placed image inside the loop stays put, and
    /// is moved its own way with the markup canvas down.
    nonisolated static func strokesEnclosed(by loop: [CGPoint], in objects: [PageObject]) -> [PageObject] {
        guard loop.count >= 3 else { return [] }
        return objects.filter { object in
            guard case .ink(let stroke) = object.payload, !stroke.points.isEmpty else { return false }
            return stroke.points.allSatisfy { contains(CGPoint(x: $0.x, y: $0.y), in: loop) }
        }
    }

    /// Whether a point is inside a closed polygon, by the even-odd rule: a ray
    /// cast from the point crosses the outline an odd number of times.
    ///
    /// Each side is taken from the previous vertex to this one, starting with
    /// the side from the **last** vertex, so the loop is closed here rather
    /// than by whoever drew it.
    private nonisolated static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for current in polygon.indices {
            let a = polygon[current], b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    /// The box a selection of strokes occupies, in source points, covering the
    /// **width** of the ink rather than the line through its middle — a thick
    /// stroke sticking out of its own box looks like a bug.
    ///
    /// Nil when nothing is selected, or when nothing selected is ink.
    nonisolated static func selectionBounds(of objects: [PageObject]) -> CGRect? {
        var box: CGRect?
        for object in objects {
            guard case .ink(let stroke) = object.payload, !stroke.points.isEmpty else { continue }
            let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
            let reach = stroke.width / 2
            let strokeBox = CGRect(x: xs.min()! - reach, y: ys.min()! - reach,
                                   width: xs.max()! - xs.min()! + stroke.width,
                                   height: ys.max()! - ys.min()! + stroke.width)
            box = box.map { $0.union(strokeBox) } ?? strokeBox
        }
        return box
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

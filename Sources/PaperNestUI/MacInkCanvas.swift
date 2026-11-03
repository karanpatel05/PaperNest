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
    let tool: InkStroke.Tool
    let color: RGBAColor
    let width: Double
    let undoManager: UndoManager?

    @State private var points: [CGPoint] = []

    private var scale: CGFloat {
        let determinant = sourceToView.a * sourceToView.d - sourceToView.b * sourceToView.c
        return max(sqrt(abs(determinant)), 0.0001)
    }

    private var previewColor: Color {
        let opacity = tool == .highlighter ? InkStroke.highlighterOpacity : 1
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue,
                     opacity: color.alpha * opacity)
    }

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
        guard let stroke = Self.stroke(from: captured, sourceToView: sourceToView,
                                       tool: tool, color: color, width: width) else { return }
        Task { try? await model.addInkStroke(stroke, to: page, undoManager: undoManager) }
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

import PaperNestCore
import SwiftUI

/// Dragging out a shape on the page.
///
/// Press where one corner goes, drag to the opposite one, let go. What is
/// shown during the drag is the stroke `ShapeAnnotation` would save for those
/// two points, mapped onto the page with the same transform the page itself
/// was drawn with — so the outline under the finger is the outline that
/// lands, at any zoom, crop or rotation.
struct ShapeDrawOverlay: View {
    let model: DocumentModel
    let page: Page
    /// Source points to points in this view.
    let sourceToView: CGAffineTransform
    let kind: ShapeAnnotation
    let color: RGBAColor
    let width: Double
    let locksAspect: Bool
    let undoManager: UndoManager?

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var isSaving = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                surface
                Canvas { context, size in
                    guard let stroke = stroke(in: size) else { return }
                    let points = stroke.points.map { point -> InkPoint in
                        let mapped = CGPoint(x: point.x, y: point.y).applying(sourceToView)
                        return InkPoint(x: mapped.x, y: mapped.y)
                    }
                    InkPainter.draw(points, width: stroke.width * InkConversion.uniformScale(sourceToView),
                                    color: stroke.color, in: &context)
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.toolShapes)
            .accessibilityValue(kind.title)
            .accessibilityHint(L10n.shapeDragToDraw)
            .accessibilityIdentifier("shape-draw-canvas")
            // Someone who cannot drag still gets the shape: placed across the
            // middle of the page, where the selection tool can move it.
            .accessibilityAction(named: Text(L10n.shapeAdd)) {
                commit(from: CGPoint(x: proxy.size.width * 0.3, y: proxy.size.height * 0.35),
                       to: CGPoint(x: proxy.size.width * 0.7, y: proxy.size.height * 0.55), in: proxy.size)
            }
            .onChange(of: page.id) { _, _ in start = nil; current = nil }
        }
    }

    @ViewBuilder private var surface: some View {
        GeometryReader { proxy in
            #if os(iOS)
            // The lasso's touch surface, for the same reasons the lasso has
            // one: a single finger or the Pencil draws, and a second finger
            // arriving cancels the drag and hands the page to scrolling.
            NotebookLassoTouchSurface(
                changed: { origin, location, _ in start = origin; current = location },
                ended: { location, _ in
                    if let origin = start { commit(from: origin, to: location, in: proxy.size) }
                    start = nil; current = nil
                },
                cancelled: { start = nil; current = nil },
                opened: { _ in })
            #else
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { start = $0.startLocation; current = $0.location }
                    .onEnded { value in
                        commit(from: value.startLocation, to: value.location, in: proxy.size)
                        start = nil; current = nil
                    })
            #endif
        }
    }

    /// The far corner, held to a square box when proportions are locked.
    private func end(from origin: CGPoint, to location: CGPoint) -> CGPoint {
        guard locksAspect, kind.isClosed else { return location }
        let side = max(abs(location.x - origin.x), abs(location.y - origin.y))
        return CGPoint(x: origin.x + (location.x < origin.x ? -side : side),
                       y: origin.y + (location.y < origin.y ? -side : side))
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x / max(size.width, 1), 0), 1), y: min(max(point.y / max(size.height, 1), 0), 1))
    }

    private func stroke(in size: CGSize) -> InkStroke? {
        guard let start, let current else { return nil }
        return try? kind.stroke(from: normalized(start, in: size), to: normalized(end(from: start, to: current), in: size),
                                geometry: page.geometry, color: color, width: width)
    }

    private func commit(from origin: CGPoint, to location: CGPoint, in size: CGSize) {
        guard !isSaving else { return }
        let a = normalized(origin, in: size), b = normalized(end(from: origin, to: location), in: size)
        // A tap, or a drag too small to be a shape, is not an error worth an
        // alert. It is nothing, and nothing is what it leaves.
        guard (try? kind.stroke(from: a, to: b, geometry: page.geometry, color: color, width: width)) != nil else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.addShape(to: page, kind: kind, start: a, end: b, color: color, width: width,
                                         undoManager: undoManager)
            } catch is ProAccessError {
                model.presentedError = PresentedError(title: L10n.proTitle, message: L10n.proRequired)
            } catch {
                model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.shapeSaveFailed)
            }
        }
    }
}

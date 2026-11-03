import CoreGraphics
import PaperNestCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Lets a text box or a placed image be picked up and moved on the page,
/// resized by a corner, and opened with a double click.
///
/// It sits over the rendered page and claims **only** the rectangles those
/// marks occupy, so everywhere else — scrolling, zooming, the ink canvas on
/// iOS — behaves exactly as before. Ink is not moved here: the drawing canvas
/// has its own lasso, and a page comment has no frame to move.
///
/// The page is drawn from the same `sourceToView` the ink canvas uses, so a
/// mark's handle sits exactly where the mark is rather than on a second guess
/// at where that is.
struct MovableMarksOverlay: View {
    let model: DocumentModel
    let page: Page
    /// Source points to points in this view, the mapping the page was drawn with.
    let sourceToView: CGAffineTransform
    let undoManager: UndoManager?

    @Binding var selected: PageObjectID?
    /// Called when a mark is opened — a double click or double tap, the
    /// idiom on both platforms for "let me change this one".
    var onOpen: (PageObject) -> Void = { _ in }
    @State private var dragging: PageObjectID?
    @State private var dragTranslation: CGSize = .zero
    @State private var resizing: Resize?
    @State private var lastClick: Click?

    /// A click that might turn out to be the first half of a double one.
    struct Click: Equatable {
        let id: PageObjectID
        let time: Date
    }

    /// A corner drag in progress.
    private struct Resize {
        let id: PageObjectID
        let corner: MarkCorner
        var translation: CGSize
    }

    /// The smallest a mark may be made, in source points. Small enough not to
    /// get in the way, large enough that its own handles stay grabbable.
    static let minimumSize: Double = 16
    /// How big a corner handle is drawn, in view points.
    private static let handleSize: CGFloat = 11

    private var marks: [PageObject] {
        model.selectedPageObjects.filter { object in
            guard object.pageID == page.id else { return false }
            switch object.payload {
            case .text, .image: return true
            case .ink, .comment: return false
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.id) { mark in
                if let source = Self.frame(of: mark) {
                    let frame = shownFrame(of: mark, source: source).applying(sourceToView)
                    let offset = dragging == mark.id ? dragTranslation : .zero
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .overlay {
                            if selected == mark.id {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                        // Handles only on the selected mark, so an unselected
                        // one keeps its whole rectangle for dragging.
                        .overlay {
                            if selected == mark.id {
                                ForEach(MarkCorner.allCases, id: \.self) { corner in
                                    handle(corner, of: mark, source: source)
                                        // Centred on its corner, so half the
                                        // target hangs outside the mark.
                                        .offset(x: corner.growsRight ? Self.handleSize : -Self.handleSize,
                                                y: corner.growsDown ? Self.handleSize : -Self.handleSize)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                                               alignment: corner.alignment)
                                }
                            }
                        }
                        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                        .offset(x: frame.minX + offset.width, y: frame.minY + offset.height)
                        .gesture(gesture(for: mark))
                        .accessibilityIdentifier("movable-mark")
                        .accessibilityValue(Self.describe(mark))
                        .accessibilityHint(L10n.moveObjectHint)
                        .accessibilityAction(named: L10n.textBoxEdit) { onOpen(mark) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Nothing outside a mark is claimed, so the page keeps its own gestures.
        .allowsHitTesting(true)
    }

    /// A corner handle. A 1.5-point dashed line is not something to aim at,
    /// so the handle is drawn as a small square and given a target twice its
    /// size, centred on the corner by the caller.
    private func handle(_ corner: MarkCorner, of mark: PageObject, source: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.canvas)
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accent, lineWidth: 1.5) }
            .frame(width: Self.handleSize, height: Self.handleSize)
            // A target twice the square it draws: 11 points is small to aim a
            // mouse at. `contentShape` has to come after this frame, or it
            // describes a shape at the origin of whatever frame follows —
            // which is how the first version put every corner's hit area in
            // the mark's top-left and left the handles looking decorative.
            .frame(width: Self.handleSize * 2, height: Self.handleSize * 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        resizing = Resize(id: mark.id, corner: corner, translation: value.translation)
                    }
                    .onEnded { value in
                        resizing = nil
                        guard abs(value.translation.width) > 1 || abs(value.translation.height) > 1 else { return }
                        let frame = Self.resized(source, corner: corner,
                                                 by: DocumentModel.sourceDelta(of: value.translation,
                                                                               sourceToView: sourceToView),
                                                 minimum: Self.minimumSize, aspect: Self.aspect(of: mark),
                                                 within: CGRect(origin: .zero, size: page.sourceSize))
                        Task { try? await model.resizeObject(mark, to: frame, undoManager: undoManager) }
                    }
            )
            // Pointer-only: four identically labelled stops would be worse
            // for VoiceOver than none, and there is no gesture-free way to
            // resize yet. Said plainly in TEST_MATRIX.
            .accessibilityHidden(true)
    }

    /// Where the mark is drawn right now — its saved frame, or where the
    /// corner being dragged has got to.
    private func shownFrame(of mark: PageObject, source: CGRect) -> CGRect {
        guard let resizing, resizing.id == mark.id else { return source }
        return Self.resized(source, corner: resizing.corner,
                            by: DocumentModel.sourceDelta(of: resizing.translation, sourceToView: sourceToView),
                            minimum: Self.minimumSize, aspect: Self.aspect(of: mark),
                            within: CGRect(origin: .zero, size: page.sourceSize))
    }

    private func gesture(for mark: PageObject) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                selected = mark.id
                dragging = mark.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                dragging = nil
                dragTranslation = .zero
                // A tap rather than a drag selects, and opens the mark when
                // it is the second one in quick succession.
                guard abs(value.translation.width) > 1 || abs(value.translation.height) > 1 else {
                    let click = Click(id: mark.id, time: Date())
                    if Self.opens(lastClick, with: click) {
                        lastClick = nil
                        onOpen(mark)
                    } else {
                        lastClick = click
                    }
                    return
                }
                lastClick = nil
                commit(mark, viewTranslation: value.translation)
            }
    }

    private func commit(_ mark: PageObject, viewTranslation: CGSize) {
        guard let frame = Self.frame(of: mark) else { return }
        // The drag happened in view points; the frame lives in source points.
        let delta = DocumentModel.sourceDelta(of: viewTranslation, sourceToView: sourceToView)
        let moved = frame.offsetBy(dx: delta.x, dy: delta.y)
        let clamped = DocumentModel.clamped(moved, within: page.sourceSize)
        Task { try? await model.moveObject(mark, to: clamped, undoManager: undoManager) }
    }

    /// A mark's frame after one corner has been dragged.
    ///
    /// The corner **opposite** the one dragged stays exactly where it is —
    /// the whole contract of a corner handle, and getting it wrong makes a box
    /// look like it is running away from the pointer.
    ///
    /// `aspect` locks the shape when it is given: a placed image keeps its
    /// proportions, because squashing a photo is what the placing code went to
    /// trouble to avoid and a resize must not undo it. A text box passes nil —
    /// it has no proportions worth keeping. Which axis drives a locked resize
    /// is decided by **whichever was dragged further**, so the gesture follows
    /// the pointer rather than ignoring one direction.
    ///
    /// Nothing shrinks past `minimum` in either direction — a negative width
    /// draws nothing and leaves something on the page nobody can grab — and
    /// nothing grows past `region`, which is the page, for the same reason a
    /// move is clamped: corners off the page cannot be reached.
    ///
    /// All of it is in source points.
    nonisolated static func resized(_ frame: CGRect, corner: MarkCorner, by delta: CGPoint,
                                    minimum: Double, aspect: Double?, within region: CGRect) -> CGRect {
        let anchor = corner.anchor(of: frame)
        // How much room there is from the anchor, in the direction being dragged.
        let roomX = corner.growsRight ? region.maxX - anchor.x : anchor.x - region.minX
        let roomY = corner.growsDown ? region.maxY - anchor.y : anchor.y - region.minY

        var width = frame.width + (corner.growsRight ? delta.x : -delta.x)
        var height = frame.height + (corner.growsDown ? delta.y : -delta.y)

        if let aspect, aspect > 0, frame.width > 0, frame.height > 0 {
            // The axis dragged further wins, then the other follows from it.
            let byWidth = width / frame.width, byHeight = height / frame.height
            let scale = abs(byWidth - 1) >= abs(byHeight - 1) ? byWidth : byHeight
            width = frame.width * scale
            height = frame.height * scale
            // Fit inside the page and above the minimum **as a pair**, or the
            // shape the lock exists to keep is lost at the edges.
            let fit = min(1, min(roomX / max(width, 0.001), roomY / max(height, 0.001)))
            width *= fit
            height *= fit
            let grow = max(1, max(minimum / max(width, 0.001), minimum / max(height, 0.001)))
            width *= grow
            height *= grow
        } else {
            width = min(max(width, minimum), max(roomX, minimum))
            height = min(max(height, minimum), max(roomY, minimum))
        }

        return CGRect(x: corner.growsRight ? anchor.x : anchor.x - width,
                      y: corner.growsDown ? anchor.y : anchor.y - height,
                      width: width, height: height)
    }

    /// How long after one click a second one still counts as a double, which
    /// is the system's own setting where there is one.
    nonisolated static var doubleClickInterval: TimeInterval {
        #if os(macOS)
        NSEvent.doubleClickInterval
        #else
        0.4
        #endif
    }

    /// Whether this click finishes a double click on the same mark.
    ///
    /// Counted here rather than with a `TapGesture(count: 2)`, which cannot
    /// live beside the move gesture: whether it is attached as
    /// `highPriorityGesture` or `simultaneousGesture`, it waits to see whether
    /// a second click is coming and swallows the single click that never
    /// becomes one — so clicking a mark stopped selecting it at all. That
    /// shipped once, in the commit that added opening, and was found by
    /// taking the tap gesture out and watching selection come back.
    nonisolated static func opens(_ previous: Click?, with next: Click) -> Bool {
        guard let previous, previous.id == next.id else { return false }
        let gap = next.time.timeIntervalSince(previous.time)
        return gap >= 0 && gap <= doubleClickInterval
    }

    /// The proportions a resize has to keep, or nil when there are none.
    nonisolated static func aspect(of object: PageObject) -> Double? {
        guard case .image(let image) = object.payload,
              image.frame.width > 0, image.frame.height > 0 else { return nil }
        return image.frame.width / image.frame.height
    }

    nonisolated static func frame(of object: PageObject) -> CGRect? {
        switch object.payload {
        case .text(let box): box.frame
        case .image(let image): image.frame
        case .ink, .comment: nil
        }
    }

    private static func describe(_ object: PageObject) -> String {
        switch object.payload {
        case .text(let box): box.text
        case .image: L10n.textBox
        case .ink, .comment: ""
        }
    }
}

/// Which corner of a mark a resize handle sits on.
///
/// Named by where it is on screen, in the page's own upright space: `top` is
/// the smaller y, as everywhere else in source coordinates.
enum MarkCorner: String, Hashable, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// The corner that stays put while this one is dragged.
    func anchor(of frame: CGRect) -> CGPoint {
        CGPoint(x: growsRight ? frame.minX : frame.maxX,
                y: growsDown ? frame.minY : frame.maxY)
    }

    /// Whether dragging right makes the mark wider (rather than narrower).
    var growsRight: Bool { self == .topTrailing || self == .bottomTrailing }
    /// Whether dragging down makes the mark taller.
    var growsDown: Bool { self == .bottomLeading || self == .bottomTrailing }

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

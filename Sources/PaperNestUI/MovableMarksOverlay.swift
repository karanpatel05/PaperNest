import CoreGraphics
import PaperNestCore
import SwiftUI

/// Lets a text box or a placed image be picked up and moved on the page.
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
    @State private var dragging: PageObjectID?
    @State private var dragTranslation: CGSize = .zero

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
                if let frame = Self.frame(of: mark)?.applying(sourceToView) {
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
                        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                        .offset(x: frame.minX + offset.width, y: frame.minY + offset.height)
                        .gesture(gesture(for: mark))
                        .accessibilityIdentifier("movable-mark")
                        .accessibilityValue(Self.describe(mark))
                        .accessibilityHint(L10n.moveObjectHint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Nothing outside a mark is claimed, so the page keeps its own gestures.
        .allowsHitTesting(true)
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
                // A tap rather than a drag only selects.
                guard abs(value.translation.width) > 1 || abs(value.translation.height) > 1 else { return }
                commit(mark, viewTranslation: value.translation)
            }
    }

    private func commit(_ mark: PageObject, viewTranslation: CGSize) {
        guard let frame = Self.frame(of: mark) else { return }
        // The drag happened in view points; the frame lives in source points.
        let viewToSource = sourceToView.inverted()
        let origin = CGPoint(x: viewTranslation.width, y: viewTranslation.height).applying(viewToSource)
        let zero = CGPoint.zero.applying(viewToSource)
        let moved = frame.offsetBy(dx: origin.x - zero.x, dy: origin.y - zero.y)
        let clamped = DocumentModel.clamped(moved, within: page.sourceSize)
        Task { try? await model.moveObject(mark, to: clamped, undoManager: undoManager) }
    }

    static func frame(of object: PageObject) -> CGRect? {
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

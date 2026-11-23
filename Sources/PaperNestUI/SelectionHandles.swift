import CoreGraphics
import SwiftUI

/// A resize or a turn of a lassoed selection while its handle is held.
///
/// Lives in view space only, for the preview; the change itself is worked out
/// again in page space from `scale` or `angle` when the handle is let go, and
/// saved through the store like every other edit of a page.
struct SelectionHandleDrag: Equatable {
    enum Kind: Equatable { case resize, rotate }

    let kind: Kind
    /// Resize: the corner that stays put. Turn: the selection's centre.
    let anchor: CGPoint
    /// Where on screen the handle was picked up.
    let start: CGPoint
    var scale: Double = 1
    var angle: Double = 0

    /// What the preview is drawn through while the handle is held.
    var viewTransform: CGAffineTransform {
        let change = kind == .resize ? CGAffineTransform(scaleX: scale, y: scale) : CGAffineTransform(rotationAngle: angle)
        return CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(change)
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    /// How much larger the selection is with the corner handle at `current`:
    /// the drag measured along the diagonal from the anchor, so moving the
    /// handle sideways along an edge does not change the size by itself.
    static func scale(anchor: CGPoint, start: CGPoint, current: CGPoint) -> Double {
        let diagonal = CGPoint(x: start.x - anchor.x, y: start.y - anchor.y)
        let length = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        guard length > 1 else { return 1 }
        let along = (current.x - anchor.x) * diagonal.x + (current.y - anchor.y) * diagonal.y
        let scale = along / length
        return scale.isFinite ? max(scale, 0.01) : 1
    }

    /// How far the selection is turned with the turn handle moved from
    /// `start` to `current` about `anchor`, clockwise positive on screen.
    /// Within a few degrees of a multiple of 45° it settles on that angle, so
    /// writing can be put back level or square without a steady hand.
    static func angle(anchor: CGPoint, start: CGPoint, current: CGPoint) -> Double {
        let began = atan2(start.y - anchor.y, start.x - anchor.x)
        let now = atan2(current.y - anchor.y, current.x - anchor.x)
        var turn = now - began
        while turn > .pi { turn -= 2 * .pi }
        while turn <= -.pi { turn += 2 * .pi }
        let step = Double.pi / 4
        let nearest = (turn / step).rounded() * step
        let snap = 4 * Double.pi / 180
        return abs(turn - nearest) < snap ? nearest : turn
    }
}

/// One round handle on a lassoed selection, 44 points to touch.
struct SelectionHandle: View {
    let symbol: String
    let label: String
    let identifier: String
    let changed: (CGPoint, CGPoint) -> Void
    let ended: () -> Void
    let increase: () -> Void
    let decrease: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(Theme.accent, in: Circle())
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
            .shadow(color: Theme.paperShadow, radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(SelectionHandle.space))
                .onChanged { changed($0.startLocation, $0.location) }
                .onEnded { _ in ended() })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: increase()
                case .decrement: decrease()
                @unknown default: break
                }
            }
    }

    /// The overlay's own space, which the selection is drawn in.
    static let space = "page-selection"
}

import SwiftUI

/// Original notebook glyphs on one optical grid, with a shared stroke weight.
/// Labels and accessibility belong to the containing controls.
struct NotebookToolIcon: View {
    enum Kind { case pen, eraser, highlighter, lasso, image, text, more, shapes, sticker, insert }
    let kind: Kind
    /// Drawn on a filled purple button: the small colour accents inside the
    /// glyphs become white washes, since purple on purple would vanish.
    var onAccent = false

    var body: some View {
        Canvas { context, _ in
            let line = StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
            let accent: (Color) -> GraphicsContext.Shading = { color in
                .color(onAccent ? Color.white.opacity(0.4) : color)
            }
            var path = Path()
            switch kind {
            case .shapes:
                path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 12, height: 12), cornerSize: CGSize(width: 2.5, height: 2.5))
                let circle = Path(ellipseIn: CGRect(x: 10, y: 10, width: 11, height: 11))
                context.fill(circle, with: accent(Theme.accent.opacity(0.3)))
                context.stroke(circle, with: .foreground, style: line)
            case .sticker:
                var body = Path()
                body.move(to: CGPoint(x: 21, y: 12))
                body.addLine(to: CGPoint(x: 21, y: 8))
                body.addQuadCurve(to: CGPoint(x: 16, y: 3), control: CGPoint(x: 21, y: 3))
                body.addLine(to: CGPoint(x: 8, y: 3))
                body.addQuadCurve(to: CGPoint(x: 3, y: 8), control: CGPoint(x: 3, y: 3))
                body.addLine(to: CGPoint(x: 3, y: 16))
                body.addQuadCurve(to: CGPoint(x: 8, y: 21), control: CGPoint(x: 3, y: 21))
                body.addLine(to: CGPoint(x: 13, y: 21))
                body.closeSubpath()
                context.fill(body, with: accent(Color.yellow.opacity(0.45)))
                path.addPath(body)
                // The peeled corner.
                path.move(to: CGPoint(x: 13, y: 21))
                path.addQuadCurve(to: CGPoint(x: 15, y: 14), control: CGPoint(x: 13, y: 14))
                path.addQuadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 21, y: 14))
                context.fill(Path(ellipseIn: CGRect(x: 7.4, y: 8, width: 2.2, height: 2.2)), with: .foreground)
                context.fill(Path(ellipseIn: CGRect(x: 13.4, y: 8, width: 2.2, height: 2.2)), with: .foreground)
            case .insert:
                path.addLines([CGPoint(x: 13, y: 3), CGPoint(x: 6, y: 3), CGPoint(x: 6, y: 21), CGPoint(x: 12, y: 21)])
                path.move(to: CGPoint(x: 13, y: 3)); path.addLine(to: CGPoint(x: 18, y: 8))
                path.addLine(to: CGPoint(x: 18, y: 11))
                path.move(to: CGPoint(x: 13, y: 3)); path.addLine(to: CGPoint(x: 13, y: 8))
                path.addLine(to: CGPoint(x: 18, y: 8))
                context.fill(Path(ellipseIn: CGRect(x: 12.5, y: 12.5, width: 9.5, height: 9.5)),
                             with: accent(Theme.accent.opacity(0.3)))
                path.move(to: CGPoint(x: 17.25, y: 14.5)); path.addLine(to: CGPoint(x: 17.25, y: 20))
                path.move(to: CGPoint(x: 14.5, y: 17.25)); path.addLine(to: CGPoint(x: 20, y: 17.25))
            case .pen:
                path.move(to: CGPoint(x: 8, y: 15))
                path.addLine(to: CGPoint(x: 16, y: 4))
                path.addQuadCurve(to: CGPoint(x: 20, y: 8), control: CGPoint(x: 23, y: 1))
                path.addLine(to: CGPoint(x: 12, y: 18))
                path.closeSubpath()
                var nib = Path()
                nib.addLines([CGPoint(x: 8, y: 15), CGPoint(x: 5, y: 21), CGPoint(x: 12, y: 18)])
                nib.closeSubpath()
                context.fill(nib, with: accent(Theme.accent.opacity(0.35)))
                context.stroke(nib, with: .foreground, style: line)
                context.fill(Path(ellipseIn: CGRect(x: 2, y: 19, width: 5, height: 4)), with: accent(Theme.accent))
            case .eraser:
                var rubber = Path()
                rubber.addLines([CGPoint(x: 4, y: 13), CGPoint(x: 8, y: 9), CGPoint(x: 15, y: 16), CGPoint(x: 12, y: 19),
                                 CGPoint(x: 9, y: 19), CGPoint(x: 4, y: 14)])
                rubber.closeSubpath()
                context.fill(rubber, with: accent(Color.pink.opacity(0.35)))
                path.addLines([CGPoint(x: 4, y: 13), CGPoint(x: 13, y: 4), CGPoint(x: 20, y: 11), CGPoint(x: 12, y: 19),
                               CGPoint(x: 9, y: 19), CGPoint(x: 4, y: 14), CGPoint(x: 4, y: 13)])
                path.move(to: CGPoint(x: 8, y: 9)); path.addLine(to: CGPoint(x: 15, y: 16))
            case .highlighter:
                var nib = Path()
                nib.addLines([CGPoint(x: 7, y: 13), CGPoint(x: 4, y: 17), CGPoint(x: 3, y: 20), CGPoint(x: 7, y: 19), CGPoint(x: 11, y: 17)])
                nib.closeSubpath()
                context.fill(nib, with: accent(Color.yellow.opacity(0.85)))
                context.stroke(nib, with: .foreground, style: line)
                path.addLines([CGPoint(x: 6, y: 12), CGPoint(x: 14, y: 4), CGPoint(x: 20, y: 10), CGPoint(x: 12, y: 18),
                               CGPoint(x: 6, y: 12)])
            case .lasso:
                var loop = Path()
                loop.move(to: CGPoint(x: 8, y: 20))
                loop.addCurve(to: CGPoint(x: 7, y: 5), control1: CGPoint(x: 0, y: 20), control2: CGPoint(x: 2, y: 10))
                loop.addCurve(to: CGPoint(x: 21, y: 9), control1: CGPoint(x: 13, y: 0), control2: CGPoint(x: 23, y: 2))
                loop.addCurve(to: CGPoint(x: 8, y: 20), control1: CGPoint(x: 20, y: 15), control2: CGPoint(x: 14, y: 18))
                loop.closeSubpath()
                context.stroke(loop, with: .foreground,
                               style: StrokeStyle(lineWidth: 1.65, lineCap: .round, dash: [2.2, 3]))
            case .image:
                path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 2.5, height: 2.5))
                path.addLines([CGPoint(x: 4, y: 17), CGPoint(x: 9, y: 12), CGPoint(x: 13, y: 16), CGPoint(x: 16, y: 13), CGPoint(x: 20, y: 17)])
                context.fill(Path(ellipseIn: CGRect(x: 14, y: 7, width: 3, height: 3)), with: .foreground)
            case .text:
                path.addLines([CGPoint(x: 5, y: 7), CGPoint(x: 5, y: 4), CGPoint(x: 19, y: 4), CGPoint(x: 19, y: 7)])
                path.move(to: CGPoint(x: 12, y: 4)); path.addLine(to: CGPoint(x: 12, y: 20))
                path.move(to: CGPoint(x: 8, y: 20)); path.addLine(to: CGPoint(x: 16, y: 20))
            case .more:
                for x in [CGFloat(5), 12, 19] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: 10.6, width: 2.8, height: 2.8)), with: .foreground)
                }
            }
            context.stroke(path, with: .foreground, style: line)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

struct NotebookToolFace: View {
    let kind: NotebookToolIcon.Kind
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        NotebookToolIcon(kind: kind)
            .foregroundStyle(Theme.primaryText)
            .frame(width: 44, height: 44)
            .background(selected ? Theme.selection : hovered && isEnabled ? Theme.selection.opacity(0.4) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Theme.accent.opacity(0.16) : .clear, lineWidth: 0.75)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovered = $0 }
            .accessibilityElement(children: .ignore)
    }
}

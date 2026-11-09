import SwiftUI

/// Original notebook glyphs on one optical grid, with a shared stroke weight.
/// Labels and accessibility belong to the containing controls.
struct NotebookToolIcon: View {
    enum Kind { case pen, eraser, highlighter, lasso, image, text, more }
    let kind: Kind

    var body: some View {
        Canvas { context, _ in
            let line = StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
            var path = Path()
            switch kind {
            case .pen:
                path.move(to: CGPoint(x: 8, y: 15))
                path.addLine(to: CGPoint(x: 16, y: 4))
                path.addQuadCurve(to: CGPoint(x: 20, y: 8), control: CGPoint(x: 23, y: 1))
                path.addLine(to: CGPoint(x: 12, y: 18))
                path.closeSubpath()
                var nib = Path()
                nib.addLines([CGPoint(x: 8, y: 15), CGPoint(x: 5, y: 21), CGPoint(x: 12, y: 18)])
                nib.closeSubpath()
                context.fill(nib, with: .color(Theme.accent.opacity(0.35)))
                context.stroke(nib, with: .foreground, style: line)
                context.fill(Path(ellipseIn: CGRect(x: 2, y: 19, width: 5, height: 4)), with: .color(Theme.accent))
            case .eraser:
                var rubber = Path()
                rubber.addLines([CGPoint(x: 4, y: 13), CGPoint(x: 8, y: 9), CGPoint(x: 15, y: 16), CGPoint(x: 12, y: 19),
                                 CGPoint(x: 9, y: 19), CGPoint(x: 4, y: 14)])
                rubber.closeSubpath()
                context.fill(rubber, with: .color(.pink.opacity(0.35)))
                path.addLines([CGPoint(x: 4, y: 13), CGPoint(x: 13, y: 4), CGPoint(x: 20, y: 11), CGPoint(x: 12, y: 19),
                               CGPoint(x: 9, y: 19), CGPoint(x: 4, y: 14), CGPoint(x: 4, y: 13)])
                path.move(to: CGPoint(x: 8, y: 9)); path.addLine(to: CGPoint(x: 15, y: 16))
            case .highlighter:
                var nib = Path()
                nib.addLines([CGPoint(x: 7, y: 13), CGPoint(x: 4, y: 17), CGPoint(x: 3, y: 20), CGPoint(x: 7, y: 19), CGPoint(x: 11, y: 17)])
                nib.closeSubpath()
                context.fill(nib, with: .color(.yellow.opacity(0.85)))
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

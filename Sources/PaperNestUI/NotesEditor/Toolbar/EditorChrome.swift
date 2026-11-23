import PaperNestCore
import SwiftUI

/// The notes editor's own surface: floating, lightly lavender, purple where
/// something is chosen. Light and dark are both spelled out, because a
/// translucent white panel over a dark canvas is grey, not dark.
enum EditorChrome {
    // Light values are the earlier approved ones. Dark values are the owner's
    // Option 6 palette (2026-11-14): #151222 background, #241F37 panels,
    // #302A46 raised surfaces, #49405F borders, white and #BFB9D1 text. On
    // the dark panels the accent is the lavender #B99AFF, because #7438F5 on
    // #241F37 is too low in contrast to read as text or a thin line.
    static let purple = Theme.adaptive(0x7438F5, 0xB99AFF)
    static let deepPurple = Theme.adaptive(0x5521CB, 0x7438F5)
    static let navy = Theme.adaptive(0x172347, 0xFFFFFF)
    static let lavender = Theme.adaptive(0xF2EDFF, 0x302A46)
    static let surface = Theme.adaptive(0xFFFFFF, 0x241F37)
    static let secondaryBackground = Theme.adaptive(0xF8F9FD, 0x151222)
    static let border = Theme.adaptive(0xE7E5F0, 0x49405F)
    static let secondaryText = Theme.adaptive(0x6B7190, 0xBFB9D1)

    /// A chosen tool. The label on it is always white, so both stops stay
    /// dark enough for white in either appearance.
    static let selection = LinearGradient(
        colors: [Theme.adaptive(0x8750FF, 0x7438F5), Theme.adaptive(0x5521CB, 0x5521CB)],
        startPoint: .top, endPoint: .bottom)

    static let toolbarRadius: CGFloat = 22
    static let panelRadius: CGFloat = 20
    static let controlRadius: CGFloat = 12
}

/// The floating card every toolbar and panel section sits on.
struct EditorFloatingSurface: ViewModifier {
    var radius = EditorChrome.toolbarRadius
    var elevated = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(EditorChrome.surface)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(EditorChrome.surface.opacity(0.82))
                    shape.fill(EditorChrome.lavender.opacity(0.18))
                }
            }
            .overlay { shape.strokeBorder(EditorChrome.border, lineWidth: 0.75) }
            .shadow(color: EditorChrome.deepPurple.opacity(elevated ? 0.10 : 0), radius: 14, y: 5)
            .shadow(color: .black.opacity(elevated ? 0.04 : 0), radius: 2, y: 1)
    }
}

extension View {
    func editorFloatingSurface(radius: CGFloat = EditorChrome.toolbarRadius, elevated: Bool = true) -> some View {
        modifier(EditorFloatingSurface(radius: radius, elevated: elevated))
    }
}

/// One tool on the main toolbar: its glyph, and its name where there is room.
struct EditorToolButtonFace: View {
    let kind: NotebookToolIcon.Kind
    var title: String?
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            NotebookToolIcon(kind: kind, onAccent: selected)
            if let title {
                Text(verbatim: title)
                    .font(.app(.caption2).weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(selected ? Color.white : EditorChrome.navy)
        .padding(.horizontal, title == nil ? 0 : 8)
        .frame(minWidth: title == nil ? 44 : 58, minHeight: title == nil ? 44 : 52)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            if selected {
                shape.fill(EditorChrome.selection)
                    .shadow(color: EditorChrome.purple.opacity(0.35), radius: 6, y: 3)
            } else if hovered && isEnabled {
                shape.fill(EditorChrome.lavender)
            }
        }
        .scaleEffect(hovered && isEnabled && !selected && !reduceMotion ? 1.03 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
    }
}

/// A thin rule between groups of tools.
struct EditorToolbarDivider: View {
    var body: some View {
        Rectangle().fill(EditorChrome.border).frame(width: 1, height: 26).padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

/// Draws ink into a SwiftUI canvas the way the page renderer draws it into a
/// page: a width at every point, and a see-through stroke faded as a whole so
/// its joins do not bead.
///
/// The pen panel's preview and the Mac's live stroke both go through this, so
/// neither can drift from what is saved.
enum InkPainter {
    static func draw(_ points: [InkPoint], width: Double, color: RGBAColor, tool: InkStroke.Tool = .pen,
                     cap: InkStroke.Cap? = nil, in context: inout GraphicsContext) {
        guard let first = points.first else { return }
        let alpha = color.alpha * (tool == .highlighter ? InkStroke.highlighterOpacity : 1)
        let paint = Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
        let lineCap: CGLineCap = cap == .flat ? .butt : .round
        var layer = context
        layer.opacity = alpha
        if tool == .highlighter { layer.blendMode = .multiply }
        layer.drawLayer { inner in
            let uniform = points.allSatisfy { $0.widthScale == first.widthScale }
            if uniform || points.count == 1 {
                var path = Path()
                path.move(to: CGPoint(x: first.x, y: first.y))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                if points.count == 1 { path.addLine(to: CGPoint(x: first.x, y: first.y)) }
                inner.stroke(path, with: .color(paint),
                             style: StrokeStyle(lineWidth: max(width * first.widthScale, 0.3),
                                                lineCap: lineCap, lineJoin: .round))
                return
            }
            for (a, b) in zip(points, points.dropFirst()) {
                var segment = Path()
                segment.move(to: CGPoint(x: a.x, y: a.y))
                segment.addLine(to: CGPoint(x: b.x, y: b.y))
                inner.stroke(segment, with: .color(paint),
                             style: StrokeStyle(lineWidth: max(width * (a.widthScale + b.widthScale) / 2, 0.3),
                                                lineCap: .round, lineJoin: .round))
            }
        }
    }
}

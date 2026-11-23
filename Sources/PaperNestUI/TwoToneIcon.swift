import SwiftUI

/// The filled two-tone icons the owner approved with Plus Jakarta Sans
/// (2026-11-22, Subframe samples "Fonts & icons B"). Each glyph is drawn on a
/// 24-point grid in two or three tones of one hue, so a selected row reads
/// lavender-and-violet and an unselected one grey-and-slate.
enum TwoToneGlyph: CaseIterable {
    case home, notes, scan, folder, newNote, importFile, newFolder
    case profile, allDocuments, favorites, trash, cloudOff

    enum Tone { case soft, mid, strong }

    struct Layer {
        let path: Path
        let tone: Tone
    }

    /// Back to front.
    var layers: [Layer] {
        switch self {
        case .home:
            return [
                Layer(path: Self.polygon([(12, 3.2, 1), (20.5, 10.5, 0.8), (20.5, 21, 1), (15, 21, 0), (15, 15, 0),
                                          (9, 15, 0), (9, 21, 0), (3.5, 21, 1), (3.5, 10.5, 0.8)]), tone: .mid),
                Layer(path: Path(roundedRect: CGRect(x: 9, y: 15, width: 6, height: 6), cornerRadius: 0.4), tone: .strong),
            ]
        case .notes:
            return [Layer(path: Self.pencilBody, tone: .mid), Layer(path: Self.pencilBand, tone: .strong)]
        case .scan:
            var bar = Path()
            bar.addRoundedRect(in: CGRect(x: 6, y: 11, width: 12, height: 2), cornerSize: CGSize(width: 1, height: 1))
            return [Layer(path: bar, tone: .mid), Layer(path: Self.viewfinderCorners, tone: .strong)]
        case .folder:
            return [Layer(path: Self.folderBack, tone: .mid), Layer(path: Self.folderFront, tone: .strong)]
        case .newNote:
            return [
                Layer(path: Self.polygon([(4, 2, 2), (14, 2, 0), (20, 8, 0), (20, 22, 2), (4, 22, 2)]), tone: .soft),
                Layer(path: Self.polygon([(14, 2, 0), (14, 8, 2), (20, 8, 0)]), tone: .mid),
                Layer(path: Self.plus(centerX: 12, centerY: 15, arm: 4, thickness: 2), tone: .strong),
            ]
        case .importFile:
            return [
                Layer(path: Self.polygon([(3, 14, 0.6), (8, 14, 0.6), (9.5, 16, 0.6), (14.5, 16, 0.6), (16, 14, 0.6),
                                          (21, 14, 0.6), (21, 21, 2), (3, 21, 2)]), tone: .soft),
                Layer(path: Self.polygon([(11, 3, 0.5), (13, 3, 0.5), (13, 11.2, 0), (15.6, 8.6, 0.5), (17, 10, 0.5),
                                          (12, 15, 0.5), (7, 10, 0.5), (8.4, 8.6, 0.5), (11, 11.2, 0)]), tone: .strong),
            ]
        case .newFolder:
            var whole = Self.folderBack
            whole.addPath(Self.folderFront)
            return [Layer(path: whole, tone: .soft),
                    Layer(path: Self.plus(centerX: 12, centerY: 13.5, arm: 3.5, thickness: 2), tone: .strong)]
        case .profile:
            var shoulders = Path()
            shoulders.addArc(center: CGPoint(x: 12, y: 20.5), radius: 8,
                             startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            shoulders.closeSubpath()
            return [Layer(path: shoulders, tone: .mid),
                    Layer(path: Path(ellipseIn: CGRect(x: 8, y: 4, width: 8, height: 8)), tone: .strong)]
        case .allDocuments:
            return [
                Layer(path: Self.polygon([(7, 2, 2), (15.5, 2, 0), (20, 6.5, 0), (20, 19, 2), (7, 19, 2)]), tone: .mid),
                Layer(path: Self.polygon([(4, 6.5, 0), (6, 6.5, 0), (6, 20, 0), (15.5, 20, 0), (15.5, 22, 0),
                                          (4, 22, 2)]), tone: .strong),
            ]
        case .favorites:
            let star: [(CGFloat, CGFloat, CGFloat)] = [(12, 2.5, 0.8), (14.9, 8.5, 0.4), (21.5, 9.3, 0.8), (16.6, 13.8, 0.4),
                                                       (17.9, 20.3, 0.8), (12, 17, 0.4), (6.1, 20.3, 0.8), (7.4, 13.8, 0.4),
                                                       (2.5, 9.3, 0.8), (9.1, 8.5, 0.4)]
            return [Layer(path: Self.polygon(star), tone: .mid),
                    Layer(path: Self.polygon([(12, 2.5, 0), (12, 17, 0), (6.1, 20.3, 0.8), (7.4, 13.8, 0.4),
                                              (2.5, 9.3, 0.8), (9.1, 8.5, 0.4)]), tone: .strong)]
        case .trash:
            return [
                Layer(path: Self.polygon([(6, 8, 0.5), (18, 8, 0.5), (17, 22, 2), (7, 22, 2)]), tone: .mid),
                Layer(path: Self.polygon([(9, 3, 0.5), (15, 3, 0.5), (16, 5, 0), (20, 5, 0.6), (20, 7, 0.6),
                                          (4, 7, 0.6), (4, 5, 0.6), (8, 5, 0)]), tone: .strong),
            ]
        case .cloudOff:
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: 4, y: 10, width: 9, height: 9))
            cloud.addEllipse(in: CGRect(x: 7.5, y: 5, width: 11, height: 11))
            cloud.addEllipse(in: CGRect(x: 13.3, y: 10.6, width: 8.4, height: 8.4))
            cloud.addRect(CGRect(x: 8.5, y: 12, width: 9, height: 7))
            return [Layer(path: cloud, tone: .soft),
                    Layer(path: Self.polygon([(4, 3.3, 0), (20.7, 20, 0), (19.3, 21.4, 0), (2.6, 4.7, 0)]), tone: .strong)]
        }
    }

    // MARK: - Shared pieces

    private static var folderBack: Path {
        polygon([(3, 4, 2), (9, 4, 0.6), (11, 6, 0.6), (21, 6, 2), (21, 20, 2), (3, 20, 2)])
    }

    private static var folderFront: Path {
        UnevenRoundedRectangle(topLeadingRadius: 0.5, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 0.5)
            .path(in: CGRect(x: 3, y: 9, width: 18, height: 11))
    }

    private static var viewfinderCorners: Path {
        var corners = Path()
        let segments: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 4, y: 8), CGPoint(x: 4, y: 4), CGPoint(x: 8, y: 4)),
            (CGPoint(x: 16, y: 4), CGPoint(x: 20, y: 4), CGPoint(x: 20, y: 8)),
            (CGPoint(x: 20, y: 16), CGPoint(x: 20, y: 20), CGPoint(x: 16, y: 20)),
            (CGPoint(x: 8, y: 20), CGPoint(x: 4, y: 20), CGPoint(x: 4, y: 16)),
        ]
        for (start, corner, end) in segments {
            corners.move(to: start)
            corners.addArc(tangent1End: corner, tangent2End: end, radius: 2)
            corners.addLine(to: end)
        }
        return corners.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// The pencil is drawn along its own axis, tip at the origin, then turned
    /// 45° and set with its tip at (4, 20).
    private static let pencilTransform = CGAffineTransform(a: 0.7071, b: -0.7071, c: 0.7071, d: 0.7071, tx: 4, ty: 20)

    private static var pencilBody: Path {
        var body = Path()
        body.move(to: .zero)
        body.addLine(to: CGPoint(x: 4, y: -2.8))
        body.addLine(to: CGPoint(x: 4, y: 2.8))
        body.closeSubpath()
        body.addRoundedRect(in: CGRect(x: 4, y: -2.8, width: 13, height: 5.6),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        return body.applying(pencilTransform)
    }

    private static var pencilBand: Path {
        Path(CGRect(x: 12.5, y: -2.8, width: 2, height: 5.6)).applying(pencilTransform)
    }

    private static func plus(centerX x: CGFloat, centerY y: CGFloat, arm: CGFloat, thickness t: CGFloat) -> Path {
        var plus = Path()
        let corner = CGSize(width: 0.6, height: 0.6)
        plus.addRoundedRect(in: CGRect(x: x - t / 2, y: y - arm, width: t, height: arm * 2), cornerSize: corner)
        plus.addRoundedRect(in: CGRect(x: x - arm, y: y - t / 2, width: arm * 2, height: t), cornerSize: corner)
        return plus
    }

    /// A closed polygon whose corners are each rounded by their own radius
    /// (0 for a sharp corner).
    static func polygon(_ points: [(CGFloat, CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }
        let p = points.map { CGPoint(x: $0.0, y: $0.1) }
        let last = p[p.count - 1]
        path.move(to: CGPoint(x: (last.x + p[0].x) / 2, y: (last.y + p[0].y) / 2))
        for i in p.indices {
            let next = p[(i + 1) % p.count]
            if points[i].2 > 0 {
                path.addArc(tangent1End: p[i], tangent2End: next, radius: points[i].2)
            } else {
                path.addLine(to: p[i])
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The colours a glyph's tones take.
struct IconPalette {
    let soft: Color
    let mid: Color
    let strong: Color

    func color(_ tone: TwoToneGlyph.Tone) -> Color {
        switch tone {
        case .soft: soft
        case .mid: mid
        case .strong: strong
        }
    }

    /// Actions and the selected place: lavender and violet.
    static let accent = IconPalette(soft: Theme.adaptive(0xD9CCFF, 0x4B3D7A),
                                    mid: Theme.adaptive(0xB9A5FF, 0x6D5AAE),
                                    strong: Theme.accent)
    /// Everything that is not the selection or the primary action: neutral
    /// slate, so the violet ones stand out (owner, 2026-11-22).
    static let inactive = IconPalette(soft: Theme.adaptive(0xC7C9D2, 0x45474F),
                                      mid: Theme.adaptive(0xC7C9D2, 0x45474F),
                                      strong: Theme.adaptive(0x545767, 0xC4C6CF))
    static let slate = inactive
    /// On a filled accent button: lilac and white.
    static let onFilled = IconPalette(soft: Theme.adaptive(0xC9B8FF, 0xC9B8FF),
                                      mid: Theme.adaptive(0xC9B8FF, 0xC9B8FF),
                                      strong: .white)

    /// One hue at three strengths, for a folder card's own tint.
    static func tinted(_ tint: Color) -> IconPalette {
        IconPalette(soft: tint.opacity(0.3), mid: tint.opacity(0.45), strong: tint)
    }
}

/// A two-tone glyph at a size. Decorative: the control around it carries the
/// accessible name.
struct TwoToneIcon: View {
    let glyph: TwoToneGlyph
    var palette: IconPalette = .accent
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            ForEach(Array(glyph.layers.enumerated()), id: \.offset) { _, layer in
                GlyphShape(path: layer.path).fill(palette.color(layer.tone))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A path drawn on the 24-point grid, scaled into whatever frame it gets.
private struct GlyphShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX + (rect.width - 24 * scale) / 2,
                                             y: rect.minY + (rect.height - 24 * scale) / 2)))
    }
}

/// A sidebar row's glyph: violet when its place is selected, slate when not,
/// and white when the system fills the selected row with the accent (iPad
/// and Mac sidebars with keyboard focus), where violet on violet vanished.
struct SidebarGlyph: View {
    let glyph: TwoToneGlyph
    let selected: Bool
    var size: CGFloat = 24
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        TwoToneIcon(glyph: glyph,
                    palette: prominence == .increased ? .onFilled : (selected ? .accent : .inactive),
                    size: size)
    }
}

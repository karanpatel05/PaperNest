import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum StickerCategory: String, CaseIterable, Sendable {
    case productivity, planning, education, decorative

    var title: String {
        switch self {
        case .productivity: L10n.stickerProductivity
        case .planning: L10n.stickerPlanning
        case .education: L10n.stickerEducation
        case .decorative: L10n.stickerDecorative
        }
    }
}

/// One of Paper NEST's own stickers.
///
/// Every sticker here is drawn by this file, from paths, in the app's own
/// palette. None is a system symbol, an emoji or anyone else's artwork: a
/// sticker ends up inside the user's document and in what they export, which
/// is not a place for an interface glyph on loan.
///
/// A sticker is placed as an ordinary image, so it moves, resizes, deletes,
/// saves, reopens and exports exactly as a photo does, with no second kind of
/// page object to keep in step.
struct Sticker: Identifiable, Hashable, Sendable {
    let id: String
    let category: StickerCategory

    var name: String {
        switch id {
        case "check": L10n.stickerCheck
        case "star": L10n.stickerStar
        case "flag": L10n.stickerFlag
        case "important": L10n.stickerImportant
        case "idea": L10n.stickerIdea
        case "calendar": L10n.stickerCalendar
        case "clock": L10n.stickerClock
        case "target": L10n.stickerTarget
        case "note": L10n.stickerNote
        case "book": L10n.stickerBook
        case "pencil": L10n.stickerPencil
        case "grade": L10n.stickerGrade
        case "heart": L10n.stickerHeart
        case "arrow": L10n.stickerArrow
        case "ribbon": L10n.stickerRibbon
        default: L10n.stickerBubble
        }
    }
}

enum StickerLibrary {
    static let all: [Sticker] = [
        Sticker(id: "check", category: .productivity), Sticker(id: "star", category: .productivity),
        Sticker(id: "flag", category: .productivity), Sticker(id: "important", category: .productivity),
        Sticker(id: "idea", category: .productivity),
        Sticker(id: "calendar", category: .planning), Sticker(id: "clock", category: .planning),
        Sticker(id: "target", category: .planning), Sticker(id: "note", category: .planning),
        Sticker(id: "book", category: .education), Sticker(id: "pencil", category: .education),
        Sticker(id: "grade", category: .education),
        Sticker(id: "heart", category: .decorative), Sticker(id: "arrow", category: .decorative),
        Sticker(id: "ribbon", category: .decorative), Sticker(id: "bubble", category: .decorative),
    ]

    static func sticker(_ id: String) -> Sticker? { all.first { $0.id == id } }

    /// Stickers whose name contains the query, ignoring case and accents, so
    /// "etoile" finds "Étoile".
    static func search(_ query: String, in stickers: [Sticker] = all) -> [Sticker] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return stickers }
        return stickers.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The sticker as a bitmap with a transparent background.
    static func image(for sticker: Sticker, pixels: Int = 320) -> CGImage? {
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Unit space with the origin at the top left, the way the artwork
        // below is written.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(pixels), y: -CGFloat(pixels))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        draw(sticker, in: context)
        return context.makeImage()
    }

    /// The sticker as PNG bytes, which is what gets stored as its asset.
    /// Identical for every use of the same sticker, so the content-addressed
    /// asset store keeps one copy however many times it is placed.
    static func pngData(for sticker: Sticker, pixels: Int = 320) -> Data? {
        guard let image = image(for: sticker, pixels: pixels) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Artwork

    // Computed, not stored: a `CGColor` constant shared across actors is not
    // something strict concurrency lets a type keep.
    private static var purple: CGColor { rgb(0x7438F5) }
    private static var deepPurple: CGColor { rgb(0x5521CB) }
    private static var navy: CGColor { rgb(0x172347) }
    private static var gold: CGColor { rgb(0xFFC83D) }
    private static var amber: CGColor { rgb(0xF59E0B) }
    private static var red: CGColor { rgb(0xEF4444) }
    private static var green: CGColor { rgb(0x22C55E) }
    private static var sky: CGColor { rgb(0x38BDF8) }
    private static var paper: CGColor { rgb(0xFFFFFF) }
    private static var cream: CGColor { rgb(0xFFF3B0) }
    private static var lavender: CGColor { rgb(0xE9DDFF) }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func polygon(_ points: [(Double, Double)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return path
    }

    private static func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
    }

    private static func fill(_ path: CGPath, _ color: CGColor, in context: CGContext) {
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
    }

    private static func stroke(_ points: [(Double, Double)], _ color: CGColor, width: Double, in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { context.addLine(to: CGPoint(x: point.0, y: point.1)) }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.strokePath()
    }

    private static func starPoints(cx: Double, cy: Double, outer: Double, inner: Double) -> [(Double, Double)] {
        (0..<10).map { index in
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            return (cx + cos(angle) * radius, cy + sin(angle) * radius)
        }
    }

    private static func draw(_ sticker: Sticker, in c: CGContext) {
        switch sticker.id {
        case "check":
            fill(rounded(0.1, 0.1, 0.8, 0.8, 0.2), green, in: c)
            stroke([(0.29, 0.52), (0.44, 0.67), (0.72, 0.35)], paper, width: 0.1, in: c)
        case "star":
            fill(polygon(starPoints(cx: 0.5, cy: 0.53, outer: 0.44, inner: 0.19)), gold, in: c)
            fill(polygon(starPoints(cx: 0.5, cy: 0.53, outer: 0.2, inner: 0.09)), cream, in: c)
        case "flag":
            stroke([(0.26, 0.1), (0.26, 0.92)], navy, width: 0.07, in: c)
            fill(polygon([(0.3, 0.13), (0.86, 0.2), (0.7, 0.36), (0.86, 0.54), (0.3, 0.55)]), red, in: c)
        case "important":
            fill(circle(0.5, 0.5, 0.42), amber, in: c)
            fill(rounded(0.44, 0.22, 0.12, 0.36, 0.06), paper, in: c)
            fill(circle(0.5, 0.72, 0.07), paper, in: c)
        case "idea":
            fill(circle(0.5, 0.42, 0.3), gold, in: c)
            fill(rounded(0.38, 0.66, 0.24, 0.1, 0.03), navy, in: c)
            fill(rounded(0.42, 0.79, 0.16, 0.07, 0.03), navy, in: c)
            stroke([(0.42, 0.44), (0.5, 0.56), (0.58, 0.44)], paper, width: 0.05, in: c)
        case "calendar":
            fill(rounded(0.12, 0.16, 0.76, 0.72, 0.12), paper, in: c)
            c.addPath(rounded(0.12, 0.16, 0.76, 0.72, 0.12))
            c.setStrokeColor(navy); c.setLineWidth(0.05); c.strokePath()
            c.saveGState()
            c.addPath(rounded(0.12, 0.16, 0.76, 0.72, 0.12)); c.clip()
            c.setFillColor(purple); c.fill(CGRect(x: 0.12, y: 0.16, width: 0.76, height: 0.2))
            c.restoreGState()
            for row in 0..<2 {
                for column in 0..<3 {
                    fill(circle(0.31 + Double(column) * 0.19, 0.53 + Double(row) * 0.18, 0.055),
                         row == 1 && column == 1 ? red : navy, in: c)
                }
            }
            stroke([(0.32, 0.1), (0.32, 0.22)], navy, width: 0.06, in: c)
            stroke([(0.68, 0.1), (0.68, 0.22)], navy, width: 0.06, in: c)
        case "clock":
            fill(circle(0.5, 0.5, 0.42), navy, in: c)
            fill(circle(0.5, 0.5, 0.34), paper, in: c)
            stroke([(0.5, 0.28), (0.5, 0.5), (0.66, 0.6)], purple, width: 0.07, in: c)
        case "target":
            fill(circle(0.5, 0.5, 0.42), red, in: c)
            fill(circle(0.5, 0.5, 0.3), paper, in: c)
            fill(circle(0.5, 0.5, 0.19), red, in: c)
            fill(circle(0.5, 0.5, 0.07), paper, in: c)
        case "note":
            fill(polygon([(0.12, 0.12), (0.88, 0.12), (0.88, 0.64), (0.64, 0.88), (0.12, 0.88)]), gold, in: c)
            fill(polygon([(0.88, 0.64), (0.64, 0.64), (0.64, 0.88)]), amber, in: c)
            for line in 0..<3 {
                let y = 0.32 + Double(line) * 0.14
                stroke([(0.26, y), (line == 2 ? 0.5 : 0.74, y)], navy, width: 0.045, in: c)
            }
        case "book":
            fill(polygon([(0.08, 0.24), (0.5, 0.32), (0.5, 0.86), (0.08, 0.78)]), purple, in: c)
            fill(polygon([(0.92, 0.24), (0.5, 0.32), (0.5, 0.86), (0.92, 0.78)]), deepPurple, in: c)
            fill(polygon([(0.15, 0.2), (0.5, 0.27), (0.5, 0.78), (0.15, 0.71)]), paper, in: c)
            fill(polygon([(0.85, 0.2), (0.5, 0.27), (0.5, 0.78), (0.85, 0.71)]), lavender, in: c)
        case "pencil":
            fill(polygon([(0.64, 0.1), (0.9, 0.36), (0.36, 0.9), (0.1, 0.64)]), gold, in: c)
            fill(polygon([(0.64, 0.1), (0.9, 0.36), (0.8, 0.46), (0.54, 0.2)]), red, in: c)
            fill(polygon([(0.1, 0.64), (0.36, 0.9), (0.08, 0.92)]), cream, in: c)
            fill(polygon([(0.14, 0.82), (0.18, 0.86), (0.08, 0.92)]), navy, in: c)
        case "grade":
            fill(circle(0.5, 0.5, 0.42), purple, in: c)
            stroke([(0.26, 0.68), (0.42, 0.3), (0.58, 0.68)], paper, width: 0.08, in: c)
            stroke([(0.33, 0.55), (0.51, 0.55)], paper, width: 0.07, in: c)
            stroke([(0.62, 0.4), (0.8, 0.4)], gold, width: 0.07, in: c)
            stroke([(0.71, 0.31), (0.71, 0.49)], gold, width: 0.07, in: c)
        case "heart":
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: 0.5, y: 0.86))
            heart.addCurve(to: CGPoint(x: 0.08, y: 0.38), control1: CGPoint(x: 0.3, y: 0.72), control2: CGPoint(x: 0.08, y: 0.58))
            heart.addCurve(to: CGPoint(x: 0.5, y: 0.26), control1: CGPoint(x: 0.08, y: 0.08), control2: CGPoint(x: 0.42, y: 0.08))
            heart.addCurve(to: CGPoint(x: 0.92, y: 0.38), control1: CGPoint(x: 0.58, y: 0.08), control2: CGPoint(x: 0.92, y: 0.08))
            heart.addCurve(to: CGPoint(x: 0.5, y: 0.86), control1: CGPoint(x: 0.92, y: 0.58), control2: CGPoint(x: 0.7, y: 0.72))
            heart.closeSubpath()
            fill(heart, red, in: c)
            stroke([(0.26, 0.3), (0.2, 0.4)], paper, width: 0.05, in: c)
        case "arrow":
            fill(polygon([(0.08, 0.38), (0.56, 0.38), (0.56, 0.18), (0.94, 0.5), (0.56, 0.82), (0.56, 0.62),
                          (0.08, 0.62)]), purple, in: c)
        case "ribbon":
            fill(polygon([(0.06, 0.34), (0.3, 0.34), (0.3, 0.72), (0.06, 0.72), (0.16, 0.53)]), deepPurple, in: c)
            fill(polygon([(0.94, 0.34), (0.7, 0.34), (0.7, 0.72), (0.94, 0.72), (0.84, 0.53)]), deepPurple, in: c)
            fill(rounded(0.2, 0.26, 0.6, 0.38, 0.05), purple, in: c)
            fill(polygon(starPoints(cx: 0.5, cy: 0.46, outer: 0.13, inner: 0.055)), gold, in: c)
        default:
            fill(rounded(0.08, 0.14, 0.84, 0.56, 0.16), sky, in: c)
            fill(polygon([(0.26, 0.66), (0.22, 0.9), (0.46, 0.68)]), sky, in: c)
            for dot in 0..<3 { fill(circle(0.33 + Double(dot) * 0.17, 0.42, 0.055), paper, in: c) }
        }
    }
}
